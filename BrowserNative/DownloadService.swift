import Foundation
import WebKit
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class DownloadService: NSObject, WKDownloadDelegate {
    private var paths: [String: URL] = [:]
    @MainActor
    final class Transfer {
        let id = UUID().uuidString
        let tabID: String
        weak var page: WKWebView?
        var request: URLRequest?
        var download: WKDownload?
        var destination: ((URL?) -> Void)?
        var temporary: URL?
        var name: String
        var host: String
        var status = "connecting"
        var expected: Int64 = -1
        var error: String?
        var fileID: String?
        var received: Int64 { max(0, download?.progress.completedUnitCount ?? 0) }
        var total: Int64 {
            if expected >= 0 { return expected }
            if status == "running", let length = download?.progress.totalUnitCount, length > 0 { return length }
            return -1
        }
        var canRetry: Bool {
            guard page != nil, let request, let scheme = request.url?.scheme?.lowercased() else { return false }
            return (request.httpMethod ?? "GET") == "GET" && ["http","https","blob","data"].contains(scheme)
        }
        init(_ download: WKDownload, tabID: String, page: WKWebView) {
            self.tabID = tabID
            self.download = download
            self.page = page
            let original = download.originalRequest
            request = (original?.httpMethod ?? "GET") == "GET" ? original : nil
            let url = download.originalRequest?.url
            name = DownloadFilename.make(["http","https"].contains(url?.scheme ?? "") ? url?.lastPathComponent ?? "" : "")
            host = url?.host ?? page.url?.host ?? ""
        }
    }
    private(set) var tasks: [Transfer] = []
    private var active: [ObjectIdentifier: Transfer] = [:]
    private(set) var notice: Transfer?
    var rows: [[String: Any]] {
        tasks.map { task in
            ["id":task.id, "name":task.name, "status":task.status, "total":task.total,
             "received":task.received, "retry":task.canRetry, "error":task.error ?? "",
             "fileID":task.fileID ?? "", "tabID":task.tabID, "canOpen":task.page != nil]
        }
    }
    private(set) var completionVersion = 0
    var didChange: (() -> Void)?
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
                let id = Self.fileID(for: safe)
                let row = try metadata(safe, id: id)
                paths[id] = safe
                return row
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                // Files can rename or remove an item while the panel is refreshing.
                return nil
            }
        }
        return ["files": rows]
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

    func attach(_ download: WKDownload, tabID: String, page: WKWebView) {
        let task = Transfer(download, tabID: tabID, page: page)
        tasks.append(task)
        active[ObjectIdentifier(download)] = task
        download.delegate = self
        didChange?()
    }

    func start(_ url: URL, in page: WKWebView, tabID: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            page.startDownload(using: URLRequest(url: url)) { download in
                self.attach(download, tabID: tabID, page: page)
                continuation.resume()
            }
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        guard let task = active[ObjectIdentifier(download)] else { completionHandler(nil); return }
        guard task.status != "cancelling" else { completionHandler(nil); return }
        task.name = DownloadFilename.make(suggestedFilename)
        task.host = response.url?.host ?? task.host
        task.expected = response.expectedContentLength
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            finish(task, status: "failed", error: "HTTP \(http.statusCode) · \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))")
            completionHandler(nil)
            return
        }
        if (task.name as NSString).pathExtension.isEmpty, let mime = response.mimeType,
           mime != "application/octet-stream", let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
            task.name += "." + ext
        }
        task.status = "confirm"
        task.destination = completionHandler
        didChange?()
    }

    func confirm(_ id: String) {
        guard let task = tasks.first(where: { $0.id == id }), let decide = task.destination else { return }
        task.destination = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        task.temporary = url
        task.status = "running"
        decide(url)
        didChange?()
    }

    func cancel(_ id: String) {
        guard let task = tasks.first(where: { $0.id == id }), let download = task.download else { return }
        if task.destination != nil {
            finish(task, status: "cancelled")
        } else {
            guard task.status != "cancelling" else { return }
            task.status = "cancelling"
            download.cancel { [weak self] _ in
                guard self?.active[ObjectIdentifier(download)] === task else { return }
                self?.finish(task, status: "cancelled")
            }
            didChange?()
        }
    }

    func retry(_ id: String) throws {
        guard let task = tasks.first(where: { $0.id == id }), ["failed","cancelled","done"].contains(task.status),
              task.canRetry, let page = task.page, let request = task.request else {
            throw BrowserFailure.invalid("Open the original page to download this file again.")
        }
        if task.status != "done" { tasks.removeAll { $0 === task } }
        if notice === task { notice = nil }
        page.startDownload(using: request) { self.attach($0, tabID: task.tabID, page: page) }
        didChange?()
    }

    func removeRecord(_ id: String) {
        tasks.removeAll { $0.id == id && ["failed","cancelled"].contains($0.status) }
        if notice?.id == id { notice = nil }
        didChange?()
    }

    func removeFile(_ id: String) throws {
        try FileManager.default.removeItem(at: fileURL(id: id))
        tasks.removeAll { $0.fileID == id }
        if notice?.fileID == id { notice = nil }
        completionVersion += 1
        didChange?()
    }

    func dismissNotice() { notice = nil; didChange?() }

    func tabClosed(_ id: String) {
        for task in tasks where task.tabID == id {
            task.request = nil
            task.page = nil
            if ["connecting","confirm"].contains(task.status) { cancel(task.id) }
        }
        tasks.removeAll { $0.tabID == id && $0.status == "done" }
        if notice?.tabID == id { dismissNotice() }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let task = active[ObjectIdentifier(download)], let temporary = task.temporary else { return }
        guard task.status != "cancelling" else { finish(task, status: "cancelled"); return }
        do {
            let file = try publishFile(temporary, suggestedFilename: task.name)
            task.name = file.lastPathComponent
            task.fileID = Self.fileID(for: file)
            finish(task, status: "done")
        } catch {
            finish(task, status: "failed", error: error.localizedDescription)
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
        guard let task = active[ObjectIdentifier(download)] else { return }
        let failure = error as NSError
        let cancelled = task.status == "cancelling" || (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
        finish(task, status: cancelled ? "cancelled" : "failed", error: cancelled ? nil : error.localizedDescription)
    }

    private func finish(_ task: Transfer, status: String, error: String? = nil) {
        if let download = task.download { active.removeValue(forKey: ObjectIdentifier(download)) }
        let decision = task.destination
        task.destination = nil
        task.download = nil
        task.status = status
        task.error = error
        if let temporary = task.temporary { try? FileManager.default.removeItem(at: temporary); task.temporary = nil }
        decision?(nil)
        if status == "done" || status == "failed" { notice = task }
        completionVersion += 1
        didChange?()
    }

    private static func fileID(for url: URL) -> String {
        SHA256.hash(data: Data(url.lastPathComponent.utf8)).map { String(format: "%02x", $0) }.joined()
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
