import CryptoKit
import Foundation
import OSLog
import Security
import UIKit

struct TransferReading {
    var confirmed: Int64
    var total: Int64
    var bytesPerSecond: Double = 0
    var inFlight: Int64 = 0
    var visibleBytes: Int64 { min(total, confirmed + inFlight) }
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
        let id: String
        let start: Int64
        let attempt: String?
        let generation: UUID?

        init?(_ task: URLSessionTask) {
            guard let value = task.taskDescription else { return nil }
            let parts = value.split(separator:":")
            guard (2...4).contains(parts.count), parts[0].count == 32,
                  let start = Int64(parts[1]), start >= 0 else { return nil }
            id = String(parts[0])
            self.start = start
            if parts.count >= 3 {
                guard UUID(uuidString:String(parts[2])) != nil else { return nil }
                attempt = String(parts[2])
            } else {
                attempt = nil
            }
            generation = parts.count == 4 ? UUID(uuidString: String(parts[3])) : nil
            if parts.count == 4 && generation == nil { return nil }
        }
    }

    private struct PartFile {
        let number: Int64
        let url: URL
        let checksum: String
    }

    private let directory: URL
    private var openLedger: TransferLedger?
    private var ledger: TransferLedger? {
        if openLedger == nil { openLedger = try? TransferLedger(directory) }
        return openLedger
    }
    private let routes = DiskRoutes.shared
    private let log = Logger(subsystem:Bundle.main.bundleIdentifier ?? "ru.atma.phonedisk",category:"Transfers")
    private var sessions: [String:URLSession] = [:]
    private var tasksByJob: [String:Set<String>] = [:]
    private var batchErrors: [String:Error] = [:]
    private var reconciling = Set<String>()
    private var resumedDescriptions = Set<String>()
    private var restoring: Task<Set<String>,Never>?
    private var bytesInFlight: [String:[String:Int64]] = [:]
    private var stagedDownloads: [String:[Int64:Int64]] = [:]
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
    var onTaskStarted: ((String,Bool) -> Void)?

    init(directory: URL) { self.directory = directory }

    func contains(_ id: String) -> Bool { (try? ledger?.read(id)) != nil }
    private func stage(_ id: String) -> URL { directory.appendingPathComponent(id) }
    private func part(_ id: String) -> URL { directory.appendingPathComponent("v2-part-" + id) }
    private func resumeFile(_ id: String) -> URL { directory.appendingPathComponent("v2-resume-" + id) }
    private func incoming(_ id: String) -> URL { directory.appendingPathComponent("v2-download-" + id) }
    private func rangesFolder(_ id: String) -> URL { directory.appendingPathComponent("v2-ranges-" + id, isDirectory: true) }

    private func background(_ route: DiskRoute, identifier: String? = nil) -> URLSession {
        let key = identifier ?? route.backgroundIdentifier
        if let session = sessions[key] { return session }
        let configuration: URLSessionConfiguration
        #if DEBUG && targetEnvironment(simulator)
        if Transfers.base.host == "127.0.0.1", ProcessInfo.processInfo.environment["PHONE_DISK_PARALLEL_FIXTURE"] != "1" { configuration = .ephemeral }
        else { configuration = .background(withIdentifier:key) }
        #else
        configuration = .background(withIdentifier:key)
        #endif
        if key == route.identifier {
            configuration.proxyConfigurations = route.proxy
        } else {
            configuration.proxyConfigurations = []
            configuration.connectionProxyDictionary = [:]
        }
        configuration.allowsCellularAccess = !route.isLocal
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = DownloadRanges.count
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 12 * 3600
        let session = URLSession(configuration:configuration,delegate:self,delegateQueue:.main)
        sessions[key] = session
        var saved = UserDefaults.standard.stringArray(forKey:"phone-disk-transfer-routes") ?? []
        if !saved.contains(key) {
            saved.append(key)
            UserDefaults.standard.set(saved,forKey:"phone-disk-transfer-routes")
        }
        return session
    }

    private func route(for session: URLSession) -> DiskRoute? {
        let identifier = session.configuration.identifier ?? sessions.first(where:{$0.value === session})?.key
        return identifier.flatMap(DiskRoute.restore)
    }

    private func isObsolete(_ session: URLSession) -> Bool {
        guard let identifier = session.configuration.identifier, let route = DiskRoute.restore(identifier) else { return false }
        return identifier == route.identifier || (route == .internet && Transfers.base.host != "127.0.0.1")
    }

    @MainActor func recover() async -> Set<String> {
        if let restoring { return await restoring.value }
        let snapshot = Task { @MainActor in await self.restoreSystemTasks() }
        restoring = snapshot
        let result = await snapshot.value
        restoring = nil
        return result
    }

    @MainActor private func restoreSystemTasks() async -> Set<String> {
        for identifier in UserDefaults.standard.stringArray(forKey:"phone-disk-transfer-routes") ?? [] {
            guard let route = DiskRoute.restore(identifier) else { continue }
            let session = background(route,identifier:identifier)
            let tasks = await session.allTasks
            if isObsolete(session) {
                // The previous session could keep a retired transfer queued across an app update.
                tasks.forEach { $0.cancel() }
                continue
            }
            let pending = tasks.filter { task in
                guard let slice = Slice(task), isRunnable?(slice.id) != false else {
                    task.cancel()
                    return false
                }
                if task is URLSessionDownloadTask, let receipt = try? ledger?.read(slice.id),
                   receipt.downloadRanges?.generation != slice.generation {
                    task.cancel()
                    return false
                }
                return task.state == .running || task.state == .suspended
            }
            for task in pending {
                guard let slice = Slice(task),let description = task.taskDescription else { continue }
                tasksByJob[slice.id,default:[]].insert(description)
                if task.state == .suspended { task.resume() }
            }
        }
        return Set(tasksByJob.keys).union(reconciling)
    }

    func handleEvents(_ identifier: String, _ completion: @escaping () -> Void) -> Bool {
        guard let route = DiskRoute.restore(identifier) else { return false }
        completions[identifier] = completion
        _ = background(route,identifier:identifier)
        finishEvents(identifier)
        return true
    }

    private func finishEvents(_ identifier: String) {
        if ended.contains(identifier),work[identifier,default:0] == 0,let completion = completions.removeValue(forKey:identifier) {
            ended.remove(identifier)
            completion()
        }
    }

    // In-flight system tasks keep their verified route. Only a failed task
    // uses the newly selected route, so a reachability probe cannot discard bytes.
    @MainActor func cancel(_ id: String) async {
        for session in Array(sessions.values) {
            for task in await session.allTasks where Slice(task)?.id == id {
                if let download = task as? URLSessionDownloadTask {
                    let data: Data? = await withCheckedContinuation { continuation in
                        download.cancel(byProducingResumeData: { continuation.resume(returning:$0) })
                    }
                    if let data, let slice = Slice(task) { saveResume(data,task,slice) }
                } else { task.cancel() }
            }
        }
    }

    func discard(_ id:String) {
        try? ledger?.remove(id)
        clearRanges(id)
        try? FileManager.default.removeItem(at:incoming(id))
        try? FileManager.default.removeItem(at:part(id))
        try? FileManager.default.removeItem(at:resumeFile(id))
    }

    private func clearRanges(_ id: String) {
        stagedDownloads.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: rangesFolder(id))
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
        for session in Array(sessions.values) {
            session.getAllTasks { $0.forEach { $0.cancel() } }
        }
        _ = try? await routes.data(request)
    }

    @MainActor func backupSettings(_ route: DiskRoute) async throws -> Data {
        let (data,_) = try await control("/api/v2/backup-settings","GET",route:route)
        return data
    }

    @MainActor func uploadAlreadyFinished(_ job: DiskJob,route: DiskRoute) async throws -> Bool {
        guard let receipt = try ledger?.read(job.id), let upload = receipt.upload else { return false }
        let (data,_) = try await control("/api/v2/uploads/" + upload,"GET",route:route)
        let manifest = try JSONDecoder().decode(UploadManifest.self,from:data)
        return manifest.id == upload && manifest.size == receipt.size && manifest.received == receipt.size && manifest.complete
    }

    private static func readFile(_ input: URL, start: Int64 = 0, length: Int64? = nil, output: URL? = nil) throws -> (Int64,String) {
        let reader = try FileHandle(forReadingFrom:input)
        defer { try? reader.close() }
        try reader.seek(toOffset:UInt64(start))
        let writer: FileHandle?
        if let output {
            if FileManager.default.fileExists(atPath:output.path) { try FileManager.default.removeItem(at:output) }
            guard FileManager.default.createFile(atPath:output.path,contents:nil,
                attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication]) else { throw DiskFailure.rejected }
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
        guard tasksByJob[job.id] == nil, !reconciling.contains(job.id) else { return false }
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
            var values: [String:Any] = ["requestId":job.id,"source":destination.source,"folder":destination.path,
                "name":job.name,"size":receipt.size,"sha256":receipt.sha256,"partSize":receipt.partSize,"automatic":job.asset != nil]
            if (try? await routes.capabilities(route))?.autoFinishUploads == true {
                values["autoFinish"] = true
            }
            let (data,_) = try await control("/api/v2/uploads","POST",route:route,body:try JSONSerialization.data(withJSONObject:values))
            manifest = try JSONDecoder().decode(UploadManifest.self,from:data)
        }
        guard UUID(uuidString:Self.uuidForm(manifest.id)) != nil, manifest.size == receipt.size,
              (1_048_576...67_108_864).contains(manifest.partSize),
              manifest.received >= 0, manifest.received <= manifest.size
        else { throw DiskFailure.rejected }
        let count = (receipt.size + manifest.partSize - 1) / manifest.partSize
        let known = Set(manifest.parts)
        guard manifest.parts.count == known.count, known.allSatisfy({ (0..<count).contains($0) })
        else { throw DiskFailure.rejected }
        receipt.upload = manifest.id
        receipt.partSize = manifest.partSize
        receipt.confirmed = manifest.received
        try ledger.write(job.id,receipt)
        report(job.id,receipt,route)
        if manifest.complete { return true }
        guard let number = (0..<count).first(where:{ !known.contains($0) }) else {
            onChecking?(job.id)
            let (data,_) = try await control("/api/v2/uploads/\(manifest.id)/finish","POST",route:route)
            guard try JSONDecoder().decode(UploadManifest.self,from:data).complete else { throw DiskFailure.rejected }
            return true
        }
        let probe = try await self.request(Transfers.address("/api/v2/uploads/" + manifest.id),"PUT",route:route)
        let volume = try? directory.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
        let spare = max(0,(volume?.volumeAvailableCapacityForImportantUsage ?? 0) - 32 * 1024 * 1024)
        let batchSize = Int(min(8,max(1,min(64 * 1024 * 1024,spare) / receipt.partSize)))
        let pending = Array((number..<count).lazy.filter { !known.contains($0) }.prefix(batchSize))
        let attempt = UUID().uuidString
        let chunk = receipt.partSize
        let total = receipt.size
        let files = try await Task.detached(priority:.utility) {
            var files: [PartFile] = []
            var prepared: [URL] = []
            do {
                for index in pending {
                    let target = input.deletingLastPathComponent().appendingPathComponent("v2-part-\(job.id)-\(attempt)-\(index)")
                    prepared.append(target)
                    let offset = index * chunk
                    let (_,hash) = try Self.readFile(input,start:offset,length:min(chunk,total-offset),output:target)
                    files.append(PartFile(number:index,url:target,checksum:hash))
                }
                return files
            } catch {
                for url in prepared { try? FileManager.default.removeItem(at:url) }
                throw error
            }
        }.value
        let transferRoute: DiskRoute
        do {
            transferRoute = try await routes.resolve()
            guard isRunnable?(job.id) != false else { throw CancellationError() }
        } catch {
            for file in files { try? FileManager.default.removeItem(at:file.url) }
            throw error
        }
        let session = background(transferRoute)
        for file in files {
            var request = probe
            request.url = transferRoute.backgroundURL(Transfers.address("/api/v2/uploads/\(manifest.id)/parts/\(file.number)"))
            request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
            request.setValue(file.checksum,forHTTPHeaderField:"X-Part-SHA256")
            startTask(session.uploadTask(with:request,fromFile:file.url),job.id,file.number,attempt:attempt)
        }
        return false
    }

    private static func uuidForm(_ text: String) -> String {
        guard text.count == 32 else { return "" }
        let c = Array(text)
        return [0..<8,8..<12,12..<16,16..<20,20..<32].map { String(c[$0]) }.joined(separator:"-")
    }

    @MainActor func finishLocalDownload(_ job: DiskJob) async throws -> Bool {
        guard job.downloadURL != nil, let ledger, var receipt = try ledger.read(job.id),
              receipt.etag != nil else { return false }
        let progress = incoming(job.id)
        if let plan = receipt.downloadRanges, receipt.confirmed < receipt.size {
            let folder = rangesFolder(job.id)
            for range in plan.ranges where range.lowerBound >= receipt.confirmed {
                guard range.lowerBound == receipt.confirmed, plan.staged(range, in: folder),
                      FileManager.default.fileExists(atPath: progress.path) else { break }
                let source = plan.part(at: range.lowerBound, in: folder)
                try await Task.detached(priority: .utility) { try DownloadRanges.append(source, range: range, to: progress) }.value
                guard isRunnable?(job.id) == true,
                      try ledger.read(job.id)?.downloadRanges?.generation == plan.generation else { throw CancellationError() }
                receipt.confirmed = range.upperBound
                try ledger.write(job.id, receipt)
                stagedDownloads[job.id]?.removeValue(forKey: range.lowerBound)
                try? FileManager.default.removeItem(at: source)
            }
        }
        guard receipt.confirmed == receipt.size else { return false }
        let published = Transfers.documents.appendingPathComponent(String(job.id.prefix(8)) + "-" + job.name)
        let alreadyPublished = FileManager.default.fileExists(atPath:published.path)
        let file = alreadyPublished ? published : progress
        guard FileManager.default.fileExists(atPath:file.path) else { return false }
        onChecking?(job.id)
        let actual = try await Task.detached(priority:.utility) { try Self.readFile(file) }.value
        guard isRunnable?(job.id) == true else { throw CancellationError() }
        guard actual.0 == receipt.size, actual.1 == receipt.sha256 else {
            if !alreadyPublished {
                try FileManager.default.removeItem(at:progress)
                receipt.confirmed = 0
                receipt.downloadRanges = nil
                try ledger.write(job.id,receipt)
                clearRanges(job.id)
            }
            throw DiskFailure.rejected
        }
        if !alreadyPublished { try FileManager.default.moveItem(at:progress,to:published) }
        if receipt.downloadRanges != nil { clearRanges(job.id) }
        return true
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
        var receipt = TransferReceipt(size:size,sha256:hash,partSize:route.isTailnet ? 32 * 1024 * 1024 : 16 * 1024 * 1024,etag:etag)
        if let old, old.etag == etag { receipt = old }
        else {
            clearRanges(job.id)
            try? FileManager.default.removeItem(at:resumeFile(job.id))
        }
        if !FileManager.default.fileExists(atPath:progress.path) {
            guard FileManager.default.createFile(atPath:progress.path,contents:nil,
                attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication]) else { throw DiskFailure.rejected }
        }
        let file = try FileHandle(forWritingTo:progress)
        let physical = try file.seekToEnd()
        if Int64(physical) < receipt.confirmed {
            receipt.confirmed = 0
            receipt.downloadRanges = nil
            clearRanges(job.id)
            try? FileManager.default.removeItem(at:resumeFile(job.id))
        }
        try file.truncate(atOffset:UInt64(receipt.confirmed))
        try file.close()
        if receipt.downloadRanges == nil, header.value(forHTTPHeaderField:"Accept-Ranges")?.lowercased() == "bytes",
           !FileManager.default.fileExists(atPath: resumeFile(job.id).path) {
            receipt.downloadRanges = DownloadRanges(prefix: receipt.confirmed, size: size)
        }
        if let plan = receipt.downloadRanges {
            try FileManager.default.createDirectory(at: plan.directory(in: rangesFolder(job.id)),
                withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            stagedDownloads.removeValue(forKey: job.id)
        }
        try ledger.write(job.id,receipt)
        report(job.id,receipt,route)
        if receipt.confirmed == size { return try await finishLocalDownload(job) }
        let fileURL = Transfers.address("/api/v2/file",query)
        var request = try await self.request(fileURL,"GET",route:route)
        let transferRoute = try await routes.resolve()
        guard isRunnable?(job.id) != false else { throw CancellationError() }
        request.url = transferRoute.backgroundURL(fileURL)
        request.setValue(etag, forHTTPHeaderField: "If-Range")
        let session = background(transferRoute)
        if let plan = receipt.downloadRanges {
            let folder = rangesFolder(job.id)
            let missing = plan.ranges.filter { $0.lowerBound >= receipt.confirmed && !plan.staged($0, in: folder) }
            if missing.isEmpty { return try await finishLocalDownload(job) }
            for range in missing {
                request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
                scheduleDownload(request, session: session, id: job.id, start: range.lowerBound, etag: etag,
                                 resumeURL: plan.resumeData(at: range.lowerBound, in: folder), generation: plan.generation)
            }
            report(job.id, receipt, transferRoute)
            return false
        }
        let bounded = transferRoute.isTailnet || receipt.boundedDownload == true
        let end = bounded ? String(min(size,receipt.confirmed + receipt.partSize)-1) : ""
        request.setValue("bytes=\(receipt.confirmed)-\(end)",forHTTPHeaderField:"Range")
        report(job.id,receipt,transferRoute)
        scheduleDownload(request, session: session, id: job.id, start: receipt.confirmed, etag: etag,
                         resumeURL: resumeFile(job.id), allowLegacyResume: !transferRoute.isTailnet)
        return false
    }

    private func scheduleDownload(_ request: URLRequest, session: URLSession, id: String, start: Int64,
                                  etag: String, resumeURL: URL, generation: UUID? = nil, allowLegacyResume: Bool = false) {
        let task: URLSessionDownloadTask
        let isResume: Bool
        if let saved = try? Data(contentsOf:resumeURL),
           let resume = try? PropertyListDecoder().decode(DownloadResume.self,from:saved),
           resume.url == request.url, resume.etag == etag, resume.start == start,
           resume.range == request.value(forHTTPHeaderField:"Range") || (resume.range == nil && allowLegacyResume),
           resume.authorization == request.value(forHTTPHeaderField:"Authorization").map(Self.authorizationFingerprint) {
            task = session.downloadTask(withResumeData:resume.data)
            isResume = true
        } else {
            task = session.downloadTask(with:request)
            isResume = false
        }
        try? FileManager.default.removeItem(at:resumeURL)
        let attempt = UUID().uuidString
        if isResume { resumedDescriptions.insert("\(id):\(start):\(attempt)" + (generation.map { ":" + $0.uuidString } ?? "")) }
        startTask(task,id,start,attempt:attempt,generation:generation)
    }

    private struct DownloadResume: Codable {
        let url: URL
        let etag: String
        let start: Int64
        let range: String?
        let authorization: String?
        let data: Data
    }

    private static func authorizationFingerprint(_ value: String) -> String {
        SHA256.hash(data:Data(value.utf8)).map { String(format:"%02x",Int($0)) }.joined()
    }

    private func startTask(_ task: URLSessionTask,_ id: String,_ start: Int64,attempt: String, generation: UUID? = nil) {
        let description = "\(id):\(start):\(attempt)" + (generation.map { ":" + $0.uuidString } ?? "")
        let firstTask = tasksByJob[id] == nil
        if firstTask {
            let now = ProcessInfo.processInfo.systemUptime
            let previous = speeds[id]
            let initial: Int64
            if generation != nil, let receipt = try? ledger?.read(id) { initial = downloadedBytes(id,receipt) }
            else { initial = 0 }
            speeds[id] = (now,initial,previous.map { now - $0.0 < 8 ? $0.2 : 0 } ?? 0)
        }
        tasksByJob[id,default:[]].insert(description)
        task.taskDescription = description
        task.resume()
        if firstTask { onTaskStarted?(id,task is URLSessionDownloadTask) }
    }

    private func report(_ id: String,_ receipt: TransferReceipt,_ route: DiskRoute) {
        let speed = speeds[id].map { ProcessInfo.processInfo.systemUptime - $0.0 < 8 ? $0.2 : 0 } ?? 0
        onReading?(id,TransferReading(confirmed:downloadedBytes(id,receipt),total:receipt.size,bytesPerSecond:speed,
                                     inFlight:bytesInFlight[id]?.values.reduce(0,+) ?? 0,
                                     connection:route.label))
    }

    private func downloadedBytes(_ id: String, _ receipt: TransferReceipt) -> Int64 {
        guard let plan = receipt.downloadRanges else { return receipt.confirmed }
        if stagedDownloads[id] == nil {
            var staged = [Int64:Int64]()
            for range in plan.ranges where range.lowerBound >= receipt.confirmed && plan.staged(range, in: rangesFolder(id)) {
                staged[range.lowerBound] = range.upperBound - range.lowerBound
            }
            stagedDownloads[id] = staged
        }
        return receipt.confirmed + (stagedDownloads[id]?.values.reduce(0,+) ?? 0)
    }

    private func speed(_ session: URLSession,_ task: URLSessionTask,_ bytes: Int64) {
        guard !isObsolete(session), let slice = Slice(task), let key = task.taskDescription,
              tasksByJob[slice.id]?.contains(key) == true, isRunnable?(slice.id) != false,
              let receipt = try? ledger?.read(slice.id), let route = route(for:session) else { return }
        var reported = max(0, bytes)
        if let generation = slice.generation {
            guard let plan = receipt.downloadRanges, plan.generation == generation,
                  let range = plan.ranges.first(where: { $0.lowerBound == slice.start }) else { return }
            if let reply = task.response as? HTTPURLResponse, (200..<300).contains(reply.statusCode),
               !plan.accepts(reply, for: range, etag: receipt.etag ?? "") {
                downloadErrors[key] = DiskFailure.response(412)
                task.cancel()
                return
            }
            reported = min(reported, range.upperBound - range.lowerBound)
        }
        bytesInFlight[slice.id,default:[:]][key] = reported
        let committed = slice.generation == nil ? 0 : downloadedBytes(slice.id,receipt)
        let total = committed + (bytesInFlight[slice.id]?.values.reduce(0,+) ?? 0)
        let now = ProcessInfo.processInfo.systemUptime
        let value = speeds[slice.id] ?? (now,0,0)
        let elapsed = now - value.0
        if elapsed < 0.4 { return }
        let measured = Double(max(0,total - value.1)) / elapsed
        let smoothed = value.2 > 0 ? value.2 * 0.65 + measured * 0.35 : measured
        speeds[slice.id] = (now,total,smoothed)
        report(slice.id,receipt,route)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,totalBytesExpectedToSend: Int64) { speed(session,task,totalBytesSent) }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,totalBytesExpectedToWrite: Int64) { speed(session,downloadTask,totalBytesWritten) }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard !isObsolete(session), let route = route(for:session) else {
            completionHandler(.cancelAuthenticationChallenge,nil)
            return
        }
        let (disposition, credential) = route.evaluate(challenge)
        completionHandler(disposition,credential)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !isObsolete(session), let route = route(for:session),
              let slice = Slice(downloadTask), let key = downloadTask.taskDescription,
              acceptsCallback(slice,key), isRunnable?(slice.id) != false else { return }
        do {
            guard let ledger, var receipt = try ledger.read(slice.id),
                  let reply = downloadTask.response as? HTTPURLResponse, route.acceptsBackgroundURL(reply.url)
            else { throw DiskFailure.rejected }
            guard reply.value(forHTTPHeaderField:"ETag") == receipt.etag else { throw DiskFailure.response(412) }
            if let plan = receipt.downloadRanges {
                guard plan.generation == slice.generation,
                      let range = plan.ranges.first(where: { $0.lowerBound == slice.start }),
                      plan.accepts(reply, for: range, etag: receipt.etag ?? "") else { throw DiskFailure.response(412) }
                if range.lowerBound >= receipt.confirmed {
                    try plan.stage(location, range: range, in: rangesFolder(slice.id))
                    _ = downloadedBytes(slice.id,receipt)
                    stagedDownloads[slice.id,default:[:]][slice.start] = range.upperBound - range.lowerBound
                }
                bytesInFlight[slice.id]?.removeValue(forKey:key)
                report(slice.id,receipt,route)
                return
            }
            guard slice.generation == nil, receipt.confirmed == slice.start else { throw DiskFailure.rejected }
            let end = slice.attempt == nil || route.isTailnet || receipt.boundedDownload == true
                ? min(receipt.size,receipt.confirmed + receipt.partSize) : receipt.size
            if reply.statusCode == 206 {
                let replyRange = reply.value(forHTTPHeaderField:"Content-Range") ?? ""
                let expected = "bytes \(receipt.confirmed)-\(end-1)/\(receipt.size)"
                if replyRange != expected {
                    // The daemon may report the resumed segment's range while delivering
                    // the entire temporary file. Its original start is still authoritative.
                    let prefix = "bytes "
                    let suffix = "-\(end-1)/\(receipt.size)"
                    guard resumedDescriptions.contains(key), replyRange.hasPrefix(prefix), replyRange.hasSuffix(suffix),
                          let resumedStart = Int64(replyRange.dropFirst(prefix.count).dropLast(suffix.count)),
                          resumedStart >= receipt.confirmed, resumedStart < end else { throw DiskFailure.rejected }
                }
            } else {
                guard reply.statusCode == 200, receipt.confirmed == 0, end == receipt.size
                else { throw DiskFailure.response(412) }
            }
            let input = try FileHandle(forReadingFrom:location)
            defer { try? input.close() }
            guard try input.seekToEnd() == UInt64(end - receipt.confirmed) else { throw DiskFailure.rejected }
            try input.seek(toOffset:0)
            let partial = incoming(slice.id)
            if receipt.confirmed == 0 {
                // Adopt the system temporary file synchronously before the delegate returns.
                try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],
                                                      ofItemAtPath:location.path)
                _ = try FileManager.default.replaceItemAt(partial,withItemAt:location,backupItemName:nil,
                                                          options:.usingNewMetadataOnly)
            } else {
                let output = try FileHandle(forWritingTo:partial)
                defer { try? output.close() }
                try output.seek(toOffset:UInt64(receipt.confirmed))
                while let bytes = try input.read(upToCount:1024 * 1024), !bytes.isEmpty { try output.write(contentsOf:bytes) }
                try output.synchronize()
            }
            receipt.confirmed = end
            try ledger.write(slice.id,receipt)
        } catch { downloadErrors[key] = error }
    }

    private func acceptsCallback(_ slice: Slice,_ key: String) -> Bool {
        if tasksByJob[slice.id]?.contains(key) == true { return true }
        guard isRunnable?(slice.id) == true else { return false }
        if let generation = slice.generation {
            guard let receipt = try? ledger?.read(slice.id), receipt.downloadRanges?.generation == generation,
                  tasksByJob[slice.id]?.contains(where: { $0.hasPrefix("\(slice.id):\(slice.start):") }) != true else { return false }
        } else if tasksByJob[slice.id] != nil { return false }
        // iOS can replay completed system events before the new process calls allTasks.
        tasksByJob[slice.id,default:[]].insert(key)
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isObsolete(session), let route = route(for:session), let slice = Slice(task) else { return }
        guard let key = task.taskDescription else { return }
        let identifier = session.configuration.identifier
        if task is URLSessionUploadTask {
            let uploadPart = slice.attempt.map { directory.appendingPathComponent("v2-part-\(slice.id)-\($0)-\(slice.start)") }
            if let uploadPart { try? FileManager.default.removeItem(at:uploadPart) }
        }
        guard acceptsCallback(slice,key), tasksByJob[slice.id]?.remove(key) != nil else { return }
        let stagedError = downloadErrors.removeValue(forKey:key)
        var result = stagedError ?? error
        let wasResumed = resumedDescriptions.remove(key) != nil
        if task is URLSessionDownloadTask, let error = error as? URLError, isRunnable?(slice.id) == true {
            // A failing resume response must be discarded, even if Foundation returns it again.
            if !wasResumed, stagedError == nil, let blob = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                saveResume(blob,task,slice)
            } else if slice.generation == nil, error.code != .cancelled, let ledger, var receipt = try? ledger.read(slice.id) {
                // On routes where iOS cannot supply resume data, checkpoint smaller ranges.
                receipt.boundedDownload = true
                try? ledger.write(slice.id,receipt)
            }
        }
        if let reply = task.response as? HTTPURLResponse {
            if !route.acceptsBackgroundURL(reply.url) { result = DiskFailure.rejected }
            else if !(200..<300).contains(reply.statusCode) {
                if reply.statusCode == 401 { DiskDeviceKey.clear(task.originalRequest?.value(forHTTPHeaderField:"Authorization").map { String($0.dropFirst(7)) }) }
                result = DiskFailure.response(reply.statusCode)
            } else if task is URLSessionUploadTask && result == nil,
                      let ledger, let receipt = try? ledger.read(slice.id) {
                // Keep this part visible until the next manifest replaces local estimates.
                bytesInFlight[slice.id,default:[:]][key] = min(receipt.partSize,receipt.size-slice.start*receipt.partSize)
                report(slice.id,receipt,route)
            }
        }
        if let error = error as? URLError, error.code != .cancelled, isRunnable?(slice.id) != false {
            log.notice("Network transfer ended with code \(error.code.rawValue) and background cancellation \(String(describing:error.backgroundTaskCancelledReason),privacy:.public)")
        }
        if let result {
            bytesInFlight[slice.id]?.removeValue(forKey:key)
            batchErrors[slice.id] = result
        }
        guard tasksByJob[slice.id]?.isEmpty == true else { return }
        tasksByJob.removeValue(forKey:slice.id)
        guard reconciling.insert(slice.id).inserted else { return }
        if let identifier { work[identifier,default:0] += 1 }
        Task { @MainActor in
            if error is URLError, (error as? URLError)?.code != .cancelled { routes.failed(route) }
            // The first callback after a cold wake may not represent the only task.
            // Reconcile the daemon before asking the server to plan another batch.
            _ = await recover()
            reconciling.remove(slice.id)
            if tasksByJob[slice.id] == nil {
                bytesInFlight.removeValue(forKey:slice.id)
                let outcome = batchErrors.removeValue(forKey:slice.id)
                await resume?(slice.id,outcome)
            }
            if let identifier {
                work[identifier,default:0] -= 1
                finishEvents(identifier)
            }
        }
    }

    private func saveResume(_ blob: Data,_ task: URLSessionTask,_ slice: Slice) {
        guard let request = task.originalRequest, let url = request.url,
              let receipt = try? ledger?.read(slice.id), let etag = receipt.etag else { return }
        let target: URL
        if let plan = receipt.downloadRanges {
            guard slice.generation == plan.generation, slice.start >= receipt.confirmed,
                  let range = plan.ranges.first(where: { $0.lowerBound == slice.start }),
                  !plan.staged(range, in: rangesFolder(slice.id)) else { return }
            target = plan.resumeData(at: slice.start, in: rangesFolder(slice.id))
        } else {
            guard slice.generation == nil, receipt.confirmed == slice.start else { return }
            target = resumeFile(slice.id)
        }
        let value = DownloadResume(url:url,etag:etag,start:slice.start,range:request.value(forHTTPHeaderField:"Range"),
            authorization:request.value(forHTTPHeaderField:"Authorization").map(Self.authorizationFingerprint),data:blob)
        if let data = try? PropertyListEncoder().encode(value) {
            try? data.write(to:target,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let identifier = session.configuration.identifier { ended.insert(identifier); finishEvents(identifier) }
    }
}
