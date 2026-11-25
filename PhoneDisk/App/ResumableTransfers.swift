import CryptoKit
import Foundation
import OSLog
import UIKit

struct TransferReading {
    var confirmed: Int64
    var total: Int64
    var bytesPerSecond: Double = 0
    var connection: String
}

private struct UploadManifest: Decodable {
    var id: String
    var size: Int64
    var partSize: Int64
    var parts: [Int64]
    var received: Int64
    var complete: Bool
}

final class ResumableTransfers: NSObject, URLSessionDownloadDelegate {
    private struct Slice {
        var id: String
        var start: Int64

        init?(_ task: URLSessionTask) {
            guard let value = task.taskDescription else { return nil }
            let parts = value.split(separator:":")
            guard parts.count == 2, parts[0].count == 32, let start = Int64(parts[1]) else { return nil }
            self.id = String(parts[0])
            self.start = start
        }
    }

    private struct TaskKey: Hashable {
        let session: ObjectIdentifier
        let task: Int

        init(_ session: URLSession, _ task: URLSessionTask) {
            self.session = ObjectIdentifier(session)
            self.task = task.taskIdentifier
        }
    }

    private let directory: URL
    private var openLedger: TransferLedger?
    private var ledger: TransferLedger? {
        if openLedger == nil { openLedger = try? TransferLedger(directory) }
        return openLedger
    }
    private let routes = DiskRoutes.shared
    private let log = Logger(subsystem:Bundle.main.bundleIdentifier ?? "ru.atma.phonedisk",category:"Transfers")
    private var sessions: [DiskRoute:URLSession] = [:]
    private var foregroundDownloads: [DiskRoute:URLSession] = [:]
    private var handoffs = Set<TaskKey>()
    private var activeIDs = Set<String>()
    private var completions: [String:() -> Void] = [:]
    private var ended = Set<String>()
    private var work: [String:Int] = [:]
    private var downloadErrors: [String:Error] = [:]
    private var speeds: [String:(Double,Int64,Double)] = [:]
    private var connectingKey: Task<DiskDeviceKey,Error>?

    var cookieRequest: ((URL,String) async throws -> URLRequest)?
    var resume: ((String,Error?) async -> Void)?
    var isRunnable: ((String) -> Bool)?
    var onReading: ((String,TransferReading) -> Void)?
    var onChecking: ((String) -> Void)?

    init(directory: URL) { self.directory = directory }

    func contains(_ id: String) -> Bool { (try? ledger?.read(id)) != nil }
    private func stage(_ id: String) -> URL { directory.appendingPathComponent(id) }
    private func part(_ id: String) -> URL { directory.appendingPathComponent("v2-part-" + id) }
    private func incoming(_ id: String) -> URL { directory.appendingPathComponent("v2-download-" + id) }

    private func background(_ route: DiskRoute) -> URLSession {
        if let session = sessions[route] { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier:route.identifier)
        configuration.proxyConfigurations = route.proxy
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 12 * 3600
        let session = URLSession(configuration:configuration,delegate:self,delegateQueue:.main)
        sessions[route] = session
        var saved = UserDefaults.standard.stringArray(forKey:"phone-disk-transfer-routes") ?? []
        if !saved.contains(route.identifier) {
            saved.append(route.identifier)
            UserDefaults.standard.set(saved,forKey:"phone-disk-transfer-routes")
        }
        return session
    }

    @MainActor private func downloadSession(_ route: DiskRoute) -> URLSession {
        guard UIApplication.shared.applicationState == .active else { return background(route) }
        if let session = foregroundDownloads[route] { return session }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = route.proxy
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration:configuration,delegate:self,delegateQueue:.main)
        foregroundDownloads[route] = session
        return session
    }

    private func route(for session: URLSession) -> DiskRoute? {
        if let identifier = session.configuration.identifier { return DiskRoute.restore(identifier) }
        return foregroundDownloads.first(where:{$0.value === session})?.key
    }

    @MainActor func reconcileDownloadSessions() async {
        let inForeground = UIApplication.shared.applicationState == .active
        let previous = inForeground ? sessions : foregroundDownloads
        for session in previous.values {
            for task in await session.allTasks {
                guard (UIApplication.shared.applicationState == .active) == inForeground else { return }
                guard task is URLSessionDownloadTask, task.state == .running || task.state == .suspended,
                      let slice = Slice(task), isRunnable?(slice.id) != false,
                      handoffs.insert(TaskKey(session,task)).inserted else { continue }
                task.cancel()
            }
        }
    }

    func recover() async -> Set<String> {
        for identifier in UserDefaults.standard.stringArray(forKey:"phone-disk-transfer-routes") ?? [] {
            if let route = DiskRoute.restore(identifier) { _ = background(route) }
        }
        for session in Array(sessions.values) {
            let pending = await withCheckedContinuation { continuation in
                session.getAllTasks { continuation.resume(returning:$0.compactMap { Slice($0)?.id }) }
            }
            activeIDs.formUnion(pending)
        }
        return activeIDs
    }

    func handleEvents(_ identifier: String, _ completion: @escaping () -> Void) -> Bool {
        guard let route = DiskRoute.restore(identifier) else { return false }
        completions[identifier] = completion
        _ = background(route)
        finishEvents(identifier)
        return true
    }

    private func finishEvents(_ identifier: String) {
        if ended.contains(identifier),work[identifier,default:0] == 0,let completion = completions.removeValue(forKey:identifier) {
            ended.remove(identifier)
            completion()
        }
    }

    func switchRoute(to route: DiskRoute) {
        for (previous,session) in Array(sessions) + Array(foregroundDownloads) where previous != route {
            session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        }
    }

    @MainActor func cancel(_ id: String) async {
        for session in Array(sessions.values) + Array(foregroundDownloads.values) {
            for task in await session.allTasks where Slice(task)?.id == id {
                task.cancel()
            }
        }
    }

    func discardDownload(_ id:String) {
        try? ledger?.remove(id)
        try? FileManager.default.removeItem(at:incoming(id))
    }

    @MainActor private func deviceKey(_ route: DiskRoute) async throws -> DiskDeviceKey {
        if let key = DiskDeviceKey.load(), key.expires > Date().timeIntervalSince1970 + 300 { return key }
        if let connectingKey { return try await connectingKey.value }
        let task = Task { @MainActor in
            guard let cookieRequest else { throw DiskFailure.signIn }
            var request = try await cookieRequest(Transfers.address("/api/v2/device"),"POST")
            request.setValue("https://files.rynpro.ru",forHTTPHeaderField:"Origin")
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            let defaults = UserDefaults.standard
            let device = defaults.string(forKey:"phone-disk-device") ?? UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
            defaults.set(device,forKey:"phone-disk-device")
            request.httpBody = try JSONEncoder().encode(["deviceId":device])
            let (body,reply) = try await routes.data(request,route:route)
            guard reply.statusCode == 200 else { throw DiskFailure.response(reply.statusCode) }
            let result = try JSONDecoder().decode(DiskDeviceKey.self,from:body)
            try result.store()
            return result
        }
        connectingKey = task
        defer { connectingKey = nil }
        return try await task.value
    }

    @MainActor private func request(_ url: URL, _ verb: String, route: DiskRoute, body: Data? = nil) async throws -> URLRequest {
        let key = try await deviceKey(route)
        var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:45)
        request.httpMethod = verb
        request.setValue("Bearer " + key.token,forHTTPHeaderField:"Authorization")
        if let body {
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody = body
        }
        return request
    }

    @MainActor private func control(_ path: String, _ verb: String, route: DiskRoute,
                                    body: Data? = nil, query: [String:String] = [:]) async throws -> (Data,HTTPURLResponse) {
        let request = try await self.request(Transfers.address(path,query),verb,route:route,body:body)
        let (data,reply) = try await routes.data(request,route:route)
        if reply.statusCode == 401 { DiskDeviceKey.clear(request.value(forHTTPHeaderField:"Authorization").map { String($0.dropFirst(7)) }) }
        guard (200..<300).contains(reply.statusCode) else { throw DiskFailure.response(reply.statusCode) }
        return (data,reply)
    }

    @MainActor func revoke() async {
        guard let key = DiskDeviceKey.load() else { return }
        DiskDeviceKey.clear(key.token)
        var request = URLRequest(url:Transfers.address("/api/v2/device"),timeoutInterval:5)
        request.httpMethod="DELETE"
        request.setValue("Bearer " + key.token,forHTTPHeaderField:"Authorization")
        for session in Array(sessions.values) + Array(foregroundDownloads.values) {
            session.getAllTasks { $0.forEach { $0.cancel() } }
        }
        _ = try? await routes.data(request)
    }

    @MainActor func backupSettings(_ route: DiskRoute) async throws -> Data {
        let (data,_) = try await control("/api/v2/backup-settings","GET",route:route)
        return data
    }

    private static func readFile(_ input: URL, start: Int64 = 0, length: Int64? = nil, output: URL? = nil) throws -> (Int64,String) {
        let reader = try FileHandle(forReadingFrom:input)
        defer { try? reader.close() }
        try reader.seek(toOffset:UInt64(start))
        let writer: FileHandle?
        if let output {
            if FileManager.default.fileExists(atPath:output.path) { try FileManager.default.removeItem(at:output) }
            guard FileManager.default.createFile(atPath:output.path,contents:nil) else { throw DiskFailure.rejected }
            writer = try FileHandle(forWritingTo:output)
        } else { writer = nil }
        defer { try? writer?.close() }
        var digest = SHA256()
        var read: Int64 = 0
        while read < (length ?? Int64.max) {
            try Task.checkCancellation()
            let count = Int(min(1024 * 1024,(length ?? Int64.max) - read))
            guard let data = try reader.read(upToCount:count), !data.isEmpty else { break }
            digest.update(data:data)
            try writer?.write(contentsOf:data)
            read += Int64(data.count)
        }
        if let length, read != length { throw DiskFailure.rejected }
        try writer?.synchronize()
        return (read,digest.finalize().map { String(format:"%02x",Int($0)) }.joined())
    }

    // True means that no more network tasks are needed for this job.
    @MainActor func advance(_ job: DiskJob, route: DiskRoute) async throws -> Bool {
        guard !activeIDs.contains(job.id) else { return false }
        guard let ledger else { throw DiskFailure.rejected }
        if let destination = job.destination { return try await upload(job,destination,route,ledger) }
        if let url = job.downloadURL { return try await download(job,url,route,ledger) }
        throw DiskFailure.rejected
    }

    @MainActor private func upload(_ job: DiskJob,_ destination: Destination,_ route: DiskRoute,_ ledger: TransferLedger) async throws -> Bool {
        let input = stage(job.id)
        var receipt: TransferReceipt
        if let stored = try ledger.read(job.id) { receipt = stored }
        else {
            let (size,hash) = try await Task.detached(priority:.utility) { try Self.readFile(input) }.value
            let chunk = max(route.isLocal ? 16 * 1024 * 1024 : 4 * 1024 * 1024, (size + 32767) / 32768)
            receipt = TransferReceipt(size:size,sha256:hash,partSize:chunk)
            try ledger.write(job.id,receipt)
        }
        let manifest: UploadManifest
        if let upload = receipt.upload {
            let (data,_) = try await control("/api/v2/uploads/" + upload,"GET",route:route)
            manifest = try JSONDecoder().decode(UploadManifest.self,from:data)
        } else {
            let values: [String:Any] = ["requestId":job.id,"source":destination.source,"folder":destination.path,
                "name":job.name,"size":receipt.size,"sha256":receipt.sha256,"partSize":receipt.partSize,"automatic":job.asset != nil]
            let (data,_) = try await control("/api/v2/uploads","POST",route:route,body:try JSONSerialization.data(withJSONObject:values))
            manifest = try JSONDecoder().decode(UploadManifest.self,from:data)
        }
        guard UUID(uuidString:Self.uuidForm(manifest.id)) != nil, manifest.size == receipt.size,
              manifest.partSize > 0, manifest.received >= 0, manifest.received <= manifest.size else { throw DiskFailure.rejected }
        receipt.upload = manifest.id
        receipt.partSize = manifest.partSize
        receipt.confirmed = manifest.received
        try ledger.write(job.id,receipt)
        report(job.id,receipt,route)
        if manifest.complete { return true }
        let count = (receipt.size + receipt.partSize - 1) / receipt.partSize
        let known = Set(manifest.parts)
        guard let number = (0..<count).first(where:{ !known.contains($0) }) else {
            onChecking?(job.id)
            let (data,_) = try await control("/api/v2/uploads/\(manifest.id)/finish","POST",route:route)
            guard try JSONDecoder().decode(UploadManifest.self,from:data).complete else { throw DiskFailure.rejected }
            return true
        }
        let output = part(job.id)
        let start = number * receipt.partSize, size = min(receipt.partSize,receipt.size - start)
        let (_,hash) = try await Task.detached(priority:.utility) { try Self.readFile(input,start:start,length:size,output:output) }.value
        var request = try await self.request(Transfers.address("/api/v2/uploads/\(manifest.id)/parts/\(number)"),"PUT",route:route)
        request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
        request.setValue(hash,forHTTPHeaderField:"X-Part-SHA256")
        let task = background(route).uploadTask(with:request,fromFile:output)
        startTask(task,job.id,number)
        return false
    }

    private static func uuidForm(_ text: String) -> String {
        guard text.count == 32 else { return "" }
        let c = Array(text)
        return [0..<8,8..<12,12..<16,16..<20,20..<32].map { String(c[$0]) }.joined(separator:"-")
    }

    @MainActor private func download(_ job: DiskJob,_ url: URL,_ route: DiskRoute,_ ledger: TransferLedger) async throws -> Bool {
        guard let location = Transfers.downloadLocation(url) else { throw DiskFailure.rejected }
        let query = ["source":location.source,"path":location.path]
        let progress = incoming(job.id)
        let (_,header) = try await control("/api/v2/file","HEAD",route:route,query:query)
        guard isRunnable?(job.id) != false else { throw CancellationError() }
        guard let etag = header.value(forHTTPHeaderField:"ETag"),let hash = header.value(forHTTPHeaderField:"X-File-SHA256"),
              etag == "\"" + hash + "\"", let value = header.value(forHTTPHeaderField:"X-File-Size"),
              let size = Int64(value),size >= 0 else { throw DiskFailure.rejected }
        let old = try ledger.read(job.id)
        var receipt = TransferReceipt(size:size,sha256:hash,partSize:route.isLocal ? 16 * 1024 * 1024 : 4 * 1024 * 1024,etag:etag)
        if let old, old.etag == etag { receipt = old }
        let published = Transfers.documents.appendingPathComponent(String(job.id.prefix(8)) + "-" + job.name)
        if receipt.confirmed == size && FileManager.default.fileExists(atPath:published.path) {
            let (_,hash) = try await Task.detached(priority:.utility) { try Self.readFile(published) }.value
            guard hash == receipt.sha256 else { throw DiskFailure.rejected }
            return true
        }
        if !FileManager.default.fileExists(atPath:progress.path) {
            guard FileManager.default.createFile(atPath:progress.path,contents:nil) else { throw DiskFailure.rejected }
            receipt.confirmed = 0
        }
        let file = try FileHandle(forWritingTo:progress)
        let physical = try file.seekToEnd()
        receipt.confirmed = min(receipt.confirmed,Int64(physical))
        try file.truncate(atOffset:UInt64(receipt.confirmed))
        try file.close()
        try ledger.write(job.id,receipt)
        report(job.id,receipt,route)
        if receipt.confirmed == size {
            onChecking?(job.id)
            let actual = try await Task.detached(priority:.utility) { try Self.readFile(progress) }.value
            guard actual.0 == size, actual.1 == hash else { throw DiskFailure.rejected }
            try FileManager.default.moveItem(at:progress,to:published)
            return true
        }
        var request = try await self.request(Transfers.address("/api/v2/file",query),"GET",route:route)
        guard isRunnable?(job.id) != false else { throw CancellationError() }
        request.setValue("bytes=\(receipt.confirmed)-\(min(size,receipt.confirmed + receipt.partSize)-1)",forHTTPHeaderField:"Range")
        request.setValue(etag,forHTTPHeaderField:"If-Range")
        startTask(downloadSession(route).downloadTask(with:request),job.id,receipt.confirmed)
        return false
    }

    private func startTask(_ task: URLSessionTask,_ id: String,_ start: Int64) {
        activeIDs.insert(id)
        speeds[id] = (ProcessInfo.processInfo.systemUptime,0,0)
        task.taskDescription = id + ":" + String(start)
        task.resume()
    }

    private func report(_ id: String,_ receipt: TransferReceipt,_ route: DiskRoute, speed: Double = 0) {
        onReading?(id,TransferReading(confirmed:receipt.confirmed,total:receipt.size,bytesPerSecond:speed,
                                     connection:route.isLocal ? "Домашняя сеть" : routes.network))
    }

    private func speed(_ session: URLSession,_ task: URLSessionTask,_ bytes: Int64) {
        guard let slice = Slice(task), isRunnable?(slice.id) != false,
              let value = speeds[slice.id],let receipt = try? ledger?.read(slice.id),
              let route = route(for:session) else { return }
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - value.0
        if elapsed < 0.4 { return }
        let measured = Double(max(0,bytes - value.1)) / elapsed
        let smoothed = value.2 > 0 ? value.2 * 0.65 + measured * 0.35 : measured
        speeds[slice.id] = (now,bytes,smoothed)
        report(slice.id,receipt,route,speed:smoothed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,totalBytesExpectedToSend: Int64) { speed(session,task,totalBytesSent) }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,totalBytesExpectedToWrite: Int64) { speed(session,downloadTask,totalBytesWritten) }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let route = route(for:session),
              let response = task.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return }
        let bytes = max(task.countOfBytesSent,task.countOfBytesReceived)
        routes.record(route,bytes:bytes,duration:metrics.taskInterval.duration)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let slice = Slice(downloadTask), isRunnable?(slice.id) != false else { return }
        do {
            guard let ledger, var receipt = try ledger.read(slice.id), receipt.confirmed == slice.start,
                  let reply = downloadTask.response as? HTTPURLResponse, Transfers.sameHost(reply.url),reply.statusCode == 206,
                  reply.value(forHTTPHeaderField:"ETag") == receipt.etag else { throw DiskFailure.rejected }
            let end = min(receipt.size,receipt.confirmed + receipt.partSize)
            guard reply.value(forHTTPHeaderField:"Content-Range") == "bytes \(receipt.confirmed)-\(end-1)/\(receipt.size)" else { throw DiskFailure.rejected }
            let input = try FileHandle(forReadingFrom:location)
            defer { try? input.close() }
            guard try input.seekToEnd() == UInt64(end - receipt.confirmed) else { throw DiskFailure.rejected }
            try input.seek(toOffset:0)
            let output = try FileHandle(forWritingTo:incoming(slice.id))
            defer { try? output.close() }
            try output.seek(toOffset:UInt64(receipt.confirmed))
            while let bytes = try input.read(upToCount:1024 * 1024), !bytes.isEmpty { try output.write(contentsOf:bytes) }
            try output.synchronize()
            receipt.confirmed = end
            try ledger.write(slice.id,receipt)
        } catch { downloadErrors[slice.id] = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let slice = Slice(task) else { return }
        let identifier = session.configuration.identifier
        let handoff = handoffs.remove(TaskKey(session,task)) != nil
        activeIDs.remove(slice.id)
        speeds.removeValue(forKey:slice.id)
        let savedError = downloadErrors.removeValue(forKey:slice.id)
        var result = error ?? savedError
        if task is URLSessionUploadTask { try? FileManager.default.removeItem(at:part(slice.id)) }
        if let reply = task.response as? HTTPURLResponse, !(200..<300).contains(reply.statusCode) {
            if reply.statusCode == 401 { DiskDeviceKey.clear(task.originalRequest?.value(forHTTPHeaderField:"Authorization").map { String($0.dropFirst(7)) }) }
            result = DiskFailure.response(reply.statusCode)
        }
        if handoff, (error as? URLError)?.code == .cancelled { result = nil }
        if let error = error as? URLError, error.code != .cancelled, isRunnable?(slice.id) != false {
            log.notice("Network transfer ended with code \(error.code.rawValue) and background cancellation \(String(describing:error.backgroundTaskCancelledReason),privacy:.public)")
            if let route = route(for:session) { routes.failed(route) }
        }
        if let identifier { work[identifier,default:0] += 1 }
        Task { @MainActor in
            await resume?(slice.id,result)
            if let identifier {
                work[identifier,default:0] -= 1
                finishEvents(identifier)
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let identifier = session.configuration.identifier { ended.insert(identifier); finishEvents(identifier) }
    }
}
