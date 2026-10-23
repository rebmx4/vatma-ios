import Foundation
import WebKit
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class DownloadService: NSObject, WKDownloadDelegate {
    private var paths: [String: URL] = [:]
    private var active: [ObjectIdentifier: WKDownload] = [:]
    private var reserved = Set<String>()
    private var destinations: [ObjectIdentifier: String] = [:]
    private var sourceTabs: [ObjectIdentifier: String] = [:]
    var didChange: ((String?, String?) -> Void)?
    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent("Downloads", isDirectory: true)
    }

    private func safeFolder() throws -> URL {
        let url = folder
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else {
            throw BrowserFailure.invalid("Downloads folder must not be a symbolic link.")
        }
        return url
    }

    func list() throws -> [String: Any] {
        let root = try safeFolder()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
        paths.removeAll()
        let rows = try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url -> [String: Any]? in
            guard let safe = try safeFile(url, root: root) else { return nil }
            let id = SHA256.hash(data: Data(safe.lastPathComponent.utf8)).map { String(format: "%02x", $0) }.joined()
            paths[id] = safe
            return try metadata(safe, id: id)
        }
        return ["files": rows]
    }

    func preview(id: String) throws -> [String: Any] {
        _ = try list()
        guard let candidate = paths[id], let url = try safeFile(candidate, root: safeFolder()) else {
            throw BrowserFailure.invalid("File is unavailable. Refresh the Downloads list.")
        }
        var result = try metadata(url, id: id)
        let size = result["size"] as? Int ?? 0
        let kind = result["kind"] as? String ?? "other"
        if kind == "text" {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: 100_000) ?? Data()
            result["text"] = String(decoding: bytes, as: UTF8.self)
            result["truncated"] = size > bytes.count
        } else if ["image", "audio", "video", "pdf"].contains(kind), size <= 8 * 1024 * 1024 {
            result["base64"] = try Data(contentsOf: url).base64EncodedString()
        } else {
            result["kind"] = "other"
            result["note"] = size > 8 * 1024 * 1024 ? "Preview is limited to 8 MB; the downloaded file remains saved." : "No preview is available for this file type."
        }
        return result
    }

    private func safeFile(_ url: URL, root: URL) throws -> URL? {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else { return nil }
        return url
    }

    private func metadata(_ url: URL, id: String) throws -> [String: Any] {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let type = UTType(filenameExtension: url.pathExtension)
        let kind: String
        if type?.conforms(to: .text) == true || ["json", "md", "csv", "log"].contains(url.pathExtension.lowercased()) { kind = "text" }
        else if type?.conforms(to: .image) == true { kind = "image" }
        else if type?.conforms(to: .audio) == true { kind = "audio" }
        else if type?.conforms(to: .movie) == true { kind = "video" }
        else if type?.conforms(to: .pdf) == true { kind = "pdf" }
        else { kind = "other" }
        return ["id": id, "name": url.lastPathComponent, "size": values.fileSize ?? 0,
                "modified": ISO8601DateFormatter().string(from: values.contentModificationDate ?? .distantPast),
                "extension": url.pathExtension, "kind": kind,
                "mime": type?.preferredMIMEType ?? "application/octet-stream"]
    }

    func attach(_ download: WKDownload, tabID: String) {
        active[ObjectIdentifier(download)] = download
        sourceTabs[ObjectIdentifier(download)] = tabID
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        do {
            let root = try safeFolder()
            let name = DownloadFilename.make(suggestedFilename)
            var destination = root.appendingPathComponent(name)
            while FileManager.default.fileExists(atPath: destination.path) || reserved.contains(destination.path) {
                destination = root.appendingPathComponent(DownloadFilename.make(suggestedFilename, suffix: UUID().uuidString))
            }
            reserved.insert(destination.path)
            destinations[ObjectIdentifier(download)] = destination.path
            completionHandler(destination)
        } catch { completionHandler(nil); didChange?(sourceTabs[ObjectIdentifier(download)], error.localizedDescription) }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let tabID = sourceTabs[ObjectIdentifier(download)]
        release(download); didChange?(tabID, nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let tabID = sourceTabs[ObjectIdentifier(download)]
        release(download); didChange?(tabID, error.localizedDescription)
    }

    private func release(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        active.removeValue(forKey: id)
        sourceTabs.removeValue(forKey: id)
        if let path = destinations.removeValue(forKey: id) { reserved.remove(path) }
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard let trust = challenge.protectionSpace.serverTrust, SiteTrust.evaluate(trust) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        let allowed = request.url.flatMap { try? AddressResolver.validated($0.absoluteString) } != nil
        decisionHandler(allowed ? .allow : .cancel)
    }
}
