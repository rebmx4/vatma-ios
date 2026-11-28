import Foundation
import WebKit
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class DownloadService: NSObject, WKDownloadDelegate {
    private var paths: [String: URL] = [:]
    private var active: [ObjectIdentifier: WKDownload] = [:]
    // Only publish completed transfers in the directory visible to the iOS Files picker.
    private var transfers: [ObjectIdentifier: (temporary: URL, filename: String)] = [:]
    private var sourceTabs: [ObjectIdentifier: String] = [:]
    private(set) var completionVersion = 0
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
            do {
                guard let safe = try safeFile(url, root: root) else { return nil }
                let id = SHA256.hash(data: Data(safe.lastPathComponent.utf8)).map { String(format: "%02x", $0) }.joined()
                let row = try metadata(safe, id: id)
                paths[id] = safe
                return row
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                // Files can rename or remove an item while the panel is refreshing.
                return nil
            }
        }
        return ["files": rows, "downloading": !active.isEmpty]
    }

    func fileURL(id: String) throws -> URL {
        _ = try list()
        guard let candidate = paths[id], let url = try safeFile(candidate, root: safeFolder()) else {
            throw BrowserFailure.invalid("File is unavailable. Refresh the Downloads list.")
        }
        return url
    }

    func preview(id: String) throws -> [String: Any] {
        let url = try fileURL(id: id)
        var result = try metadata(url, id: id)
        let size = result["size"] as? Int ?? 0
        let kind = result["kind"] as? String ?? "other"
        result["canSaveToPhotos"] = kind == "image" || kind == "video"
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

    func start(_ url: URL, in page: WKWebView, tabID: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            page.startDownload(using: URLRequest(url: url)) { download in
                self.attach(download, tabID: tabID)
                continuation.resume()
            }
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        do {
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw BrowserFailure.invalid("HTTP \(http.statusCode) · \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))")
            }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            var filename = DownloadFilename.make(suggestedFilename)
            if (filename as NSString).pathExtension.isEmpty, let mime = response.mimeType,
               mime != "application/octet-stream", let type = UTType(mimeType: mime),
               let ext = type.preferredFilenameExtension {
                filename += "." + ext
            }
            transfers[ObjectIdentifier(download)] = (temporary, filename)
            completionHandler(temporary)
        } catch {
            // WebKit can follow a nil destination with a generic cancellation callback.
            let tabID = sourceTabs[ObjectIdentifier(download)]
            release(download)
            completionHandler(nil)
            didChange?(tabID, error.localizedDescription)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let tabID = sourceTabs[ObjectIdentifier(download)]
        guard let transfer = transfers[ObjectIdentifier(download)] else { return }
        do {
            _ = try publishFile(transfer.temporary, suggestedFilename: transfer.filename)
            release(download); didChange?(tabID, nil)
        } catch {
            release(download); didChange?(tabID, error.localizedDescription)
        }
    }

    @discardableResult
    func publishFile(_ temporary: URL, suggestedFilename: String) throws -> URL {
        let root = try safeFolder()
        var name = DownloadFilename.make(suggestedFilename)
        while true {
            let target = root.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: temporary, to: target)
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                name = DownloadFilename.make(suggestedFilename, suffix: UUID().uuidString)
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let tabID = sourceTabs[ObjectIdentifier(download)] else { return }
        let failure = error as NSError
        let cancelled = failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled
        release(download); didChange?(tabID, cancelled ? nil : error.localizedDescription)
    }

    private func release(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        active.removeValue(forKey: id)
        sourceTabs.removeValue(forKey: id)
        if let transfer = transfers.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: transfer.temporary)
        }
        completionVersion += 1
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let host = challenge.protectionSpace.host
        guard SiteTrust.allowsBundledRoots(for: host) else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard SiteTrust.evaluate(trust, for: host) else {
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
