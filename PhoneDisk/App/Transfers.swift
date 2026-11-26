import BackgroundTasks
import Foundation
import OSLog
import Photos
import SwiftUI
import UIKit
import UserNotifications
import WebKit

enum DiskFailure: LocalizedError {
    case signIn, response(Int), rejected
    var errorDescription: String? {
        switch self {
        case .signIn: return "Войдите на домашний диск."
        case .response(404): return "Папка недоступна. Проверьте подключение диска."
        case .response(let code): return "Домашний ПК вернул ошибку \(code)."
        case .rejected: return "ПК не подтвердил сохранение файла."
        }
    }
}

final class Transfers: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Transfers()
    static let base: URL = {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["PHONE_DISK_FIXTURE"] == "1" {
            return URL(string:"https://127.0.0.1:18878/")!
        }
        #endif
        return URL(string:"https://files.rynpro.ru/")!
    }()
    private static let bundleID = Bundle.main.bundleIdentifier ?? "ru.atma.phonedisk"
    static let processing = "\(bundleID).scan"
    static let identifier = "\(bundleID).transfers"
    static let sources = Set(["photos-c","interviews-d","camera-e","backup-c","backup-d","backup-e"])
    private static let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        .appendingPathComponent("PhoneDisk",isDirectory:true)
    static let documents = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
    @Published private(set) var jobs: [DiskJob] = []
    @Published private(set) var readings: [String:TransferReading] = [:]
    @Published private(set) var stopping = Set<String>()
    @Published var message = ""
    private let queueURL = Transfers.support.appendingPathComponent("queue.json")
    private var active = Set<String>()
    private var cancelling = Set<String>()
    private var completion: (() -> Void)?
    private var eventWork = 0
    private var eventsFinished = false
    private var scanning = false
    private var scanAgain = false
    private var backupSettingsRevision = 0
    private var retrying: [String:Task<Void,Never>] = [:]
    private var retries: [String:Int] = [:]
    private var recentDownload: (source:String,path:String,at:TimeInterval)?
    private let defaults = UserDefaults.standard
    private static let automaticTransferLimit = 2
    private static let backupLog = Logger(subsystem: bundleID, category: "Autocopies")
    @MainActor private static var checkingSchedule = false

    private lazy var session: URLSession = {
        #if DEBUG && targetEnvironment(simulator)
        if Transfers.base.host == "127.0.0.1" {
            // The loopback fixture exercises the queue without the simulator's background daemon.
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            return URLSession(configuration:config,delegate:self,delegateQueue:.main)
        }
        #endif
        let config = URLSessionConfiguration.background(withIdentifier:Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpShouldSetCookies = false
        return URLSession(configuration:config,delegate:self,delegateQueue:.main)
    }()

    private lazy var resumable: ResumableTransfers = {
        let engine = ResumableTransfers(directory:Self.support)
        engine.cookieRequest = { [weak self] url, method in
            guard let self else { throw DiskFailure.rejected }
            return try await self.request(url,method:method)
        }
        engine.resume = { [weak self] id, error in await self?.resumePart(id,error) }
        engine.isRunnable = { [weak self] id in self?.isRunnable(id) == true }
        engine.onReading = { [weak self] id, data in self?.readings[id] = data }
        engine.onChecking = { [weak self] id in self?.update(id){$0.phase="Проверка файла"} }
        return engine
    }()

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at:Self.support,withIntermediateDirectories:true)
        try? FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:Self.support.path)
        var support = Self.support
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? support.setResourceValues(values)
        if let data = try? Data(contentsOf:queueURL), let saved = try? JSONDecoder().decode([DiskJob].self,from:data) {
            jobs = saved
        }
    }

    static func valid(_ destination: Destination) -> Bool {
        guard sources.contains(destination.source), destination.path.hasPrefix("/") else { return false }
        if destination.path == "/" { return true }
        return destination.path.dropFirst().split(separator:"/",omittingEmptySubsequences:false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.hasPrefix(".phone-disk-")
        }
    }

    static func sameHost(_ url: URL?) -> Bool {
        url?.scheme == base.scheme && url?.host == base.host && (url?.port ?? 443) == (base.port ?? 443) && url?.user == nil && url?.password == nil
    }

    static func downloadLocation(_ url: URL) -> Destination? {
        guard sameHost(url), url.path == "/api/resources/download",
              var components = URLComponents(url:url,resolvingAgainstBaseURL:false) else { return nil }
        // Links from older pages used form-encoded spaces. An actual plus sign is encoded as %2B.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%20")
        let query = components.queryItems ?? []
        guard let source = query.first(where:{$0.name == "source"})?.value,
              let path = query.first(where:{$0.name == "file"})?.value else { return nil }
        let location = Destination(source:source,path:path)
        return valid(location) ? location : nil
    }

    private func isRunnable(_ id:String) -> Bool {
        jobs.contains { $0.id == id && !$0.isStopped && !$0.isFinished }
    }

    func recover() {
        Task { @MainActor in
            await restoreTasks()
            for job in jobs where job.asset == nil && !job.isFinished && !job.isStopped && !active.contains(job.id) {
                start(job.id)
            }
        }
    }

    @MainActor func refreshQueue() async {
        await restoreTasks()
        for job in jobs where job.asset == nil && !job.isStopped && !job.isFinished && !active.contains(job.id) && retrying[job.id] == nil {
            start(job.id)
        }
        try? await scan(prepareOriginals:false)
    }

    @MainActor private func restoreTasks() async {
        let restored: [String] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning:$0.compactMap(\.taskDescription)) }
        }
        active.formUnion(restored)
        let pending = await resumable.recover()
        active.formUnion(pending)
        for job in jobs where job.isStopped && active.contains(job.id) {
            cancelDownloadTasks(job.id)
        }
    }

    func routeChanged() { recover() }
    @MainActor func revokeDevice() async { await resumable.revoke() }

    func handleV2Events(_ identifier: String,_ callback: @escaping () -> Void) -> Bool {
        resumable.handleEvents(identifier,callback)
    }

    func handleEvents(_ callback: @escaping () -> Void) {
        completion = callback
        _ = session
        finishEvents()
    }

    private func finishEvents() {
        if eventsFinished && eventWork == 0, let completion {
            self.completion = nil
            eventsFinished = false
            completion()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        eventsFinished = true
        finishEvents()
    }

    private func writeQueue(_ queue:[DiskJob]) throws {
        try JSONEncoder().encode(queue).write(to:queueURL,options:.atomic)
    }

    private func save() {
        try? writeQueue(jobs)
    }

    private func applyQueueChange(_ queue:[DiskJob]) -> Bool {
        do {
            try writeQueue(queue)
            jobs = queue
            return true
        } catch {
            message = "Не удалось сохранить очередь передач."
            return false
        }
    }

    private func update(_ id: String, _ change: (inout DiskJob) -> Void) {
        if let index = jobs.firstIndex(where:{$0.id==id}) { change(&jobs[index]); save() }
    }

    static func address(_ path: String, _ query: [String:String] = [:]) -> URL {
        var url = URLComponents(url:base,resolvingAgainstBaseURL:false)!
        url.path = path
        url.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name:$0.key,value:$0.value) }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B")
        return url.url!
    }

    @MainActor private func request(_ url:URL, method:String = "GET") async throws -> URLRequest {
        guard Self.sameHost(url) else { throw DiskFailure.rejected }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                continuation.resume(returning:$0.filter { $0.domain.trimmingCharacters(in:CharacterSet(charactersIn:".")) == Self.base.host && ($0.expiresDate ?? .distantFuture) > Date() })
            }
        }
        guard !cookies.isEmpty else { throw DiskFailure.signIn }
        var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:45)
        request.httpMethod = method
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with:cookies)
        return request
    }

    private func checked(_ request:URLRequest) async throws -> Data {
        let (data, response) = try await DiskRoutes.shared.data(request)
        guard (200..<300).contains(response.statusCode) else { throw DiskFailure.response(response.statusCode) }
        return data
    }

    private func requireDrive(_ source:String) async throws {
        let data=try await checked(request(Self.address("/api/resources/download",["source":"settings","file":"/drives.json"])))
        guard let catalogue=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              catalogue["schema"] as? Int==1,
              let drives=catalogue["drives"] as? [[String:Any]] else { throw DiskFailure.rejected }
        let backup=source.hasPrefix("backup-")
        guard let drive=drives.first(where:{ (($0[backup ? "backup":"root"] as? [String:Any])?["source"] as? String)==source }),
              let letter=drive["id"] as? String,["C","D","E"].contains(letter),
              let route=drive[backup ? "backup":"root"] as? [String:Any],
              route["trashed"]==nil || route["trashed"] is NSNull,
              (backup ? (drive["registered"] as? Bool==true) : (drive["available"] as? Bool==true)) else {
            throw DiskFailure.response(404)
        }
        if letter != "C" {
            let marker=Self.address("/api/resources",["source":"registered-"+letter.lowercased(),"path":"/"])
            _ = try await checked(request(marker))
        }
    }

    private func mkdir(_ destination:Destination) async throws {
        let url = Self.address("/api/resources",["source":destination.source,"path":destination.path,"isDir":"true","override":"false"])
        do { _ = try await checked(request(url,method:"POST")) }
        catch DiskFailure.response(409) { _ = try await checked(request(Self.address("/api/resources",["source":destination.source,"path":destination.path]))) }
    }

    private func stage(_ id:String) -> URL { Self.support.appendingPathComponent(id) }
    private func resumeFile(_ id:String) -> URL { Self.support.appendingPathComponent("resume-"+id) }
    private func filename(_ name:String) -> String {
        let legal = name.replacingOccurrences(of:"[<>:\"/\\\\|?*\\x00-\\x1F]",with:"_",options:.regularExpression)
            .trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:".")))
        return legal.isEmpty ? "Файл" : String(legal.prefix(120))
    }

    func enqueueFile(_ url:URL, destination:Destination, name:String? = nil) throws {
        let id = try storeUpload(url, destination:destination, name:name)
        start(id)
    }

    private func storeUpload(_ url:URL, destination:Destination, name:String?, asset:String? = nil) throws -> String {
        guard Self.valid(destination) else { throw DiskFailure.rejected }
        let id = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        if asset != nil {
            try FileManager.default.moveItem(at:url,to:stage(id))
        } else {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at:url,to:stage(id))
        }
        do {
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],
                                                  ofItemAtPath:stage(id).path)
            var queue = jobs
            queue.insert(DiskJob(id:id,name:filename(name ?? url.lastPathComponent),destination:destination,asset:asset),at:0)
            try writeQueue(queue)
            jobs = queue
        } catch {
            try? FileManager.default.removeItem(at:stage(id))
            throw error
        }
        return id
    }

    func enqueueDownload(_ url:URL,_ name:String?) {
        guard let location = Self.downloadLocation(url) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let recentDownload, recentDownload.source == location.source, recentDownload.path == location.path,
           now - recentDownload.at < 1.2 { return }
        let suggested = (location.path as NSString).lastPathComponent
        let id = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        var queue = jobs
        queue.insert(DiskJob(id:id,name:filename(name ?? suggested),downloadURL:url),at:0)
        guard applyQueueChange(queue) else { return }
        recentDownload = (location.source,location.path,now)
        start(id)
    }

    @MainActor func stopDownload(_ id:String) {
        guard let index = jobs.firstIndex(where:{$0.id == id}), jobs[index].canStopDownload else { return }
        var queue = jobs
        queue[index].phase = DiskJob.stopped
        guard applyQueueChange(queue) else { return }
        retrying.removeValue(forKey:id)?.cancel()
        retries.removeValue(forKey:id)
        readings[id]?.bytesPerSecond = 0
        cancelDownloadTasks(id)
    }

    @MainActor func retryDownload(_ id:String) {
        guard let index = jobs.firstIndex(where:{$0.id == id}), jobs[index].canRetryDownload,
              !active.contains(id), !stopping.contains(id) else { return }
        var queue = jobs
        queue[index].phase = DiskJob.waiting
        guard applyQueueChange(queue) else { return }
        retries.removeValue(forKey:id)
        start(id)
    }

    @MainActor func removeTransfers(_ ids: Set<String>) -> Bool {
        let removed = jobs.filter { ids.contains($0.id) && $0.hiddenFromQueue != true }
        guard !removed.isEmpty else { return true }
        let remaining = jobs.compactMap { job -> DiskJob? in
            guard ids.contains(job.id) else { return job }
            guard job.asset != nil else { return nil }
            var record = job
            record.hiddenFromQueue = true
            if !record.isFinished { record.phase = DiskJob.stopped }
            return record
        }
        guard applyQueueChange(remaining) else { return false }
        for job in removed {
            let id = job.id
            retrying.removeValue(forKey:id)?.cancel()
            retries.removeValue(forKey:id)
            readings.removeValue(forKey:id)
            Task { @MainActor in
                for task in await session.allTasks where task.taskDescription == id { task.cancel() }
                await resumable.cancel(id)
                try? FileManager.default.removeItem(at:resumeFile(id))
                try? FileManager.default.removeItem(at:stage(id))
                resumable.discard(id)
                markInactive(id)
            }
        }
        return true
    }

    @MainActor private func cancelDownloadTasks(_ id:String) {
        guard stopping.insert(id).inserted else { return }
        cancelling.insert(id)
        Task { @MainActor in
            for task in await session.allTasks where task.taskDescription == id {
                guard let download = task as? URLSessionDownloadTask else { continue }
                let data: Data? = await withCheckedContinuation { continuation in
                    download.cancel(byProducingResumeData: { continuation.resume(returning:$0) })
                }
                if let data { try? data.write(to:resumeFile(id),options:.atomic) }
            }
            await resumable.cancel(id)
            cancelling.remove(id)
            finishStopping(id)
        }
    }

    private func finishStopping(_ id:String) {
        if !active.contains(id) && !cancelling.contains(id) { stopping.remove(id) }
    }

    private func markInactive(_ id:String) {
        active.remove(id)
        finishStopping(id)
    }

    func start(_ id:String) {
        Task { @MainActor in
            retrying.removeValue(forKey:id)?.cancel()
            await beginTransfer(id)
        }
    }

    @MainActor private func beginTransfer(_ id:String) async {
        guard !active.contains(id),let job=jobs.first(where:{$0.id==id}),!job.isFinished,!job.isStopped else { return }
        active.insert(id)
        update(id){$0.phase="Подготовка"}
        let route = DiskRoutes.shared.transferRoute
        do {
            try Task.checkCancellation()
            if !job.uploaded {
                let usesV2 = resumable.contains(id)
                let capability = try await DiskRoutes.shared.capabilities(route)
                guard isRunnable(id) else { throw CancellationError() }
                if usesV2 || capability != nil {
                    guard capability != nil else { throw DiskFailure.response(503) }
                    update(id){$0.phase=job.destination == nil ? "Скачивание" : "Выгрузка"}
                    if try await resumable.advance(job,route:route) {
                        guard isRunnable(id) else { throw CancellationError() }
                        if job.downloadURL != nil { update(id){$0.localName=String(id.prefix(8))+"-"+job.name} }
                        done(id)
                    }
                    return
                }
            }
            if let destination=job.destination {
                try await requireDrive(destination.source)
                if job.uploaded { try await publish(job,destination); done(id); return }
                let hold=Destination(source:destination.source,path:"/.phone-disk-incoming")
                try await mkdir(hold)
                if destination.source.hasPrefix("backup-") && destination.path != "/" { try await mkdir(destination) }
                var transfer=try await request(Self.address("/api/resources",["source":destination.source,"path":hold.path+"/"+id,"isDir":"false","override":"true"]),method:"POST")
                try Task.checkCancellation()
                transfer.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
                let task=session.uploadTask(with:transfer,fromFile:stage(id))
                task.taskDescription=id
                update(id){$0.phase="Выгрузка"}
                task.resume()
            } else if let url=job.downloadURL {
                guard let location = Self.downloadLocation(url) else { throw DiskFailure.rejected }
                try await requireDrive(location.source)
                let download=try await request(url)
                try Task.checkCancellation()
                guard isRunnable(id) else { throw CancellationError() }
                let task: URLSessionDownloadTask
                if let resume=try? Data(contentsOf:resumeFile(id)) {
                    task=session.downloadTask(withResumeData:resume)
                } else { task=session.downloadTask(with:download) }
                task.taskDescription=id
                update(id){$0.phase="Скачивание"}
                task.resume()
            }
        } catch is CancellationError {
            markInactive(id)
            if isRunnable(id) { update(id){$0.phase=DiskJob.waiting} }
        } catch {
            if isRunnable(id), error is URLError { DiskRoutes.shared.failed(route) }
            waitForTransfer(id,error)
        }
    }

    @MainActor private func publish(_ job:DiskJob,_ destination:Destination) async throws {
        let source=destination.source, stage="/.phone-disk-incoming/"+job.id
        try await requireDrive(source)
        let directory = destination.path == "/" ? "" : destination.path
        func exists(_ path: String) async throws -> Bool {
            do {
                _ = try await checked(request(Self.address("/api/resources",["source":source,"path":path])))
                return true
            } catch DiskFailure.response(404) { return false }
        }
        let path:String
        if let saved=jobs.first(where:{$0.id==job.id})?.remotePath { path=saved }
        else {
            let original=directory+"/"+job.name
            if try await exists(original) { path=directory+"/"+job.id.prefix(12)+"-"+job.name }
            else { path=original }
            update(job.id){$0.remotePath=path}
        }
        var move=try await request(Self.address("/api/resources"),method:"PATCH")
        move.setValue("application/json",forHTTPHeaderField:"Content-Type")
        move.httpBody=try JSONSerialization.data(withJSONObject:["action":"move","items":[["fromSource":source,"fromPath":stage,"toSource":source,"toPath":path]],"overwrite":false,"rename":false])
        do {
            let data=try await checked(move)
            let value=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let success=value?["succeeded"] as? [[String:Any]]
            guard success?.contains(where:{($0["toPath"] as? String)==path}) == true else { throw DiskFailure.rejected }
        } catch {
            guard !(try await exists(stage)), try await exists(path) else { throw error }
        }
    }

    private func done(_ id:String) {
        markInactive(id)
        guard let index = jobs.firstIndex(where:{$0.id == id}), !jobs[index].isFinished else { return }
        var queue = jobs
        queue[index].phase = "Готово"
        queue[index].progress = 1
        guard applyQueueChange(queue) else { return }
        let automatic = queue[index].asset != nil
        retrying.removeValue(forKey:id)?.cancel()
        retries.removeValue(forKey:id)
        if var reading = readings[id] {
            reading.confirmed = reading.total
            reading.inFlight = 0
            reading.bytesPerSecond = 0
            readings[id] = reading
        }
        try? FileManager.default.removeItem(at:stage(id))
        try? FileManager.default.removeItem(at:resumeFile(id))
        notify(success:true)
        if automatic { Self.schedule() }
    }

    private func failed(_ id:String,_ text:String) {
        markInactive(id)
        guard isRunnable(id) else { return }
        update(id){$0.phase=text}
        notify(success:false)
    }

    @MainActor private func resumePart(_ id: String, _ error: Error?) async {
        markInactive(id)
        guard let job = jobs.first(where:{ $0.id == id }),!job.isFinished,!job.isStopped else { return }
        if job.asset != nil && !defaults.bool(forKey:"photo-auto") {
            update(id){$0.phase="Автокопии приостановлены"}
            return
        }
        if let error { waitForTransfer(id,error); return }
        retries.removeValue(forKey:id)
        await beginTransfer(id)
        if job.asset != nil && jobs.contains(where:{ $0.id == id && $0.isFinished }) {
            try? await scan(prepareOriginals:false)
        }
    }

    @MainActor private func waitForTransfer(_ id: String, _ error: Error) {
        markInactive(id)
        guard isRunnable(id) else { return }
        if var reading = readings[id] { reading.bytesPerSecond = 0; reading.inFlight = 0; readings[id] = reading }
        let number = retries[id,default:0]
        let errorCode: Int?
        if case DiskFailure.response(let code) = error { errorCode = code } else { errorCode = nil }
        let transient = error is URLError || errorCode.map { [401,408,412,416,429,502,503,504].contains($0) } == true
        let automaticDiskWait = errorCode == 404 && jobs.contains { $0.id == id && $0.asset != nil }
        guard (transient || automaticDiskWait), number < 6 else { failed(id,error.localizedDescription); return }
        retries[id] = number + 1
        update(id){$0.phase=automaticDiskWait ? "Ожидание выбранного диска" : "Ожидание сети"}
        Self.schedule()
        retrying[id]?.cancel()
        retrying[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for:.seconds(min(30,1 << number))) } catch { return }
            guard let self else { return }
            self.retrying.removeValue(forKey:id)
            guard self.jobs.first(where:{ $0.id == id })?.asset == nil || self.defaults.bool(forKey:"photo-auto") else { return }
            await self.beginTransfer(id)
        }
    }

    func urlSession(_ session:URLSession,task:URLSessionTask,didSendBodyData bytesSent:Int64,totalBytesSent:Int64,totalBytesExpectedToSend:Int64) {
        if let id=task.taskDescription,totalBytesExpectedToSend>0 {
            update(id){$0.progress=Double(totalBytesSent)/Double(totalBytesExpectedToSend)}
        }
    }

    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if let id=downloadTask.taskDescription,isRunnable(id),totalBytesExpectedToWrite>0 {
            update(id){$0.progress=Double(totalBytesWritten)/Double(totalBytesExpectedToWrite)}
        }
    }

    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        guard let id=downloadTask.taskDescription,let job=jobs.first(where:{$0.id==id}),
              !job.isStopped,!job.isFinished,
              let reply=downloadTask.response as? HTTPURLResponse,(200..<300).contains(reply.statusCode),Self.sameHost(reply.url) else { return }
        let name=String(id.prefix(8))+"-"+job.name
        do {
            try FileManager.default.moveItem(at:location,to:Self.documents.appendingPathComponent(name))
            update(id){$0.localName=name}
        } catch { failed(id,error.localizedDescription) }
    }

    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard let id=task.taskDescription,let job=jobs.first(where:{$0.id==id}) else { return }
        if job.isStopped {
            markInactive(id)
            return
        }
        if let error {
            if job.downloadURL != nil {
                if let data=(error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    try? data.write(to:resumeFile(id),options:.atomic)
                } else { try? FileManager.default.removeItem(at:resumeFile(id)) }
            }
            failed(id,error.localizedDescription); return
        }
        guard let response=task.response as? HTTPURLResponse,(200..<300).contains(response.statusCode),Self.sameHost(response.url) else {
            if job.downloadURL != nil { try? FileManager.default.removeItem(at:resumeFile(id)) }
            failed(id,DiskFailure.response((task.response as? HTTPURLResponse)?.statusCode ?? 0).localizedDescription); return
        }
        if let destination=job.destination {
            update(id){$0.uploaded=true;$0.phase="Проверка на ПК"}
            eventWork += 1
            Task { @MainActor in
                do {
                    try await publish(job,destination)
                    done(id)
                    if job.asset != nil { try? await scan(prepareOriginals:false) }
                }
                catch { failed(id,error.localizedDescription) }
                eventWork -= 1
                finishEvents()
            }
        } else if job.localName != nil { done(id) }
        else { failed(id,DiskFailure.rejected.localizedDescription) }
    }

    func askNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) { allowed,_ in
            DispatchQueue.main.async { self.defaults.set(allowed,forKey:"transfer-notifications") }
        }
    }

    private func notify(success:Bool) {
        guard defaults.bool(forKey:"transfer-notifications") else { return }
        let content=UNMutableNotificationContent()
        content.title="Мой диск"
        content.body=success ? "Передача завершена." : "Передача приостановлена. Проверьте очередь."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:UUID().uuidString,content:content,trigger:nil))
    }

    static func schedule() {
        Task { @MainActor in await scheduleIfNeeded() }
    }

    @MainActor static func scheduleIfNeeded() async {
        guard UserDefaults.standard.bool(forKey:"photo-auto"), !checkingSchedule else { return }
        checkingSchedule=true
        defer { checkingSchedule=false }
        let pending=await BGTaskScheduler.shared.pendingTaskRequests()
        guard UserDefaults.standard.bool(forKey:"photo-auto"), !Task.isCancelled,
              !pending.contains(where:{ $0.identifier == processing && $0.earliestBeginDate == nil })
        else { return }
        let request=BGProcessingTaskRequest(identifier:processing)
        request.requiresNetworkConnectivity=true
        do { try BGTaskScheduler.shared.submit(request) }
        catch { backupLog.error("Could not schedule automatic backup: \((error as NSError).code)") }
    }

    @MainActor func backupSettingsChanged(enabled:Bool) async {
        backupSettingsRevision += 1
        if enabled { await authorization() }
        else { try? await scan() }
    }

    @MainActor func authorization() async {
        let status=await PHPhotoLibrary.requestAuthorization(for:.readWrite)
        guard status == .authorized || status == .limited else {
            message="Медиатека недоступна. Разрешение можно изменить в настройках iPhone."; return
        }
        if !defaults.bool(forKey:"photo-auto") { defaults.set(Date(),forKey:"photo-cutoff") }
        defaults.set(true,forKey:"photo-auto")
        Self.schedule()
        try? await scan()
    }

    @MainActor func scan(prepareOriginals:Bool = true) async throws {
        guard defaults.bool(forKey:"photo-auto") else { return }
        let access=PHPhotoLibrary.authorizationStatus(for:.readWrite)
        guard access == .authorized || access == .limited else { return }
        if scanning {
            scanAgain = scanAgain || prepareOriginals
            return
        }
        scanning=true
        defer {
            scanning=false
            if scanAgain {
                scanAgain=false
                Task { @MainActor in try? await scan() }
            }
        }
        let revision=backupSettingsRevision
        await restoreTasks()
        let route = DiskRoutes.shared.transferRoute
        let data: Data
        if try await DiskRoutes.shared.capabilities(route) != nil {
            data = try await resumable.backupSettings(route)
        } else {
            data = try await checked(request(Self.address("/api/resources/download",["source":"settings","file":"/autocopies.json"])))
        }
        guard let settings=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw DiskFailure.rejected }

        func destination(for type:String, folder:String) -> Destination? {
            guard let preference=settings[type] as? [String:Any], preference["enabled"] as? Bool == true,
                  let disk=(preference["disk"] as? String)?.lowercased(), ["c","d","e"].contains(disk)
            else { return nil }
            return Destination(source:"backup-"+disk,path:folder)
        }

        let video=destination(for:"video",folder:"/Видео")
        let cutoff=defaults.object(forKey:"photo-cutoff") as? Date
        let photo=cutoff == nil ? nil : destination(for:"photo",folder:"/Фото")
        let destinations=[video, photo].compactMap { $0 }
        guard !destinations.isEmpty else { return }
        Self.schedule()

        let taskIDs: [String] = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning:$0.compactMap(\.taskDescription)) }
        }
        active.formUnion(taskIDs)
        var remaining=Self.automaticTransferLimit - jobs.filter {
            $0.asset != nil && $0.phase != "Готово" && active.contains($0.id)
        }.count
        func current() -> Bool {
            defaults.bool(forKey:"photo-auto") && backupSettingsRevision == revision
        }

        let previous = jobs.reversed().filter { job in
            guard job.asset != nil, !job.isFinished, !job.isStopped,
                  !active.contains(job.id), retrying[job.id] == nil, let target=job.destination
            else { return false }
            return destinations.contains { $0.source == target.source && $0.path == target.path }
        }
        for job in previous {
            if remaining <= 0 { break }
            try Task.checkCancellation()
            guard current() else { return }
            await beginTransfer(job.id)
            if active.contains(job.id) { remaining -= 1 }
        }
        guard prepareOriginals else { return }
        // Keep one successor staged so the transfer daemon's callback can queue
        // it without first fetching a potentially large iCloud original.
        let capacity = (try? Self.support.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
                        .volumeAvailableCapacityForImportantUsage) ?? 0
        let standby = previous.contains { job in !active.contains(job.id) && jobs.contains { $0.id == job.id && !$0.isFinished } }
        var toPrepare = max(0,remaining) + (capacity >= 512 * 1024 * 1024 && !standby ? 1 : 0)
        guard toPrepare > 0 else { return }

        var history=BackupHistory(jobs:jobs)
        let options=PHFetchOptions()
        if video != nil {
            options.includeHiddenAssets=true
            options.includeAssetSourceTypes=[.typeUserLibrary,.typeCloudShared,.typeiTunesSynced]
        }
        options.predicate=backupAssetPredicate(includeVideo:video != nil,photoCutoff:photo == nil ? nil : cutoff)
        options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:false)]
        let assets=PHAsset.fetchAssets(with:options)
        var preparationError: Error?
        var prepared=0
        for index in 0..<assets.count {
            try Task.checkCancellation()
            guard current() else { return }
            if toPrepare <= 0 { break }
            let item=assets.object(at:index)
            let isVideo=item.mediaType == .video
            guard let target=isVideo ? video : photo,
                  isVideo || (!item.isHidden && item.sourceType.contains(.typeUserLibrary)),
                  !history.contains(item.localIdentifier,on:target.source)
            else { continue }
            let resources=PHAssetResource.assetResources(for:item)
            let original=resources.first { isVideo ? $0.type == .video : $0.type == .photo }
            guard let asset=original ?? (isVideo ? resources.first { $0.type == .fullSizeVideo } : nil)
            else { continue }
            let temporary=Self.support.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:temporary) }
            let downloadOptions=PHAssetResourceRequestOptions()
            downloadOptions.isNetworkAccessAllowed=true
            do {
                try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                    PHAssetResourceManager.default().writeData(for:asset,toFile:temporary,options:downloadOptions) { error in
                        if let error { continuation.resume(throwing:error) } else { continuation.resume() }
                    }
                }
                try Task.checkCancellation()
                guard current() else { return }
                let id=try storeUpload(temporary,destination:target,name:asset.originalFilename,asset:item.localIdentifier)
                history.record(item.localIdentifier,on:target.source)
                if remaining > 0 {
                    await beginTransfer(id)
                    remaining -= 1
                }
                toPrepare -= 1
                prepared += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An unavailable original must not prevent later videos from reaching the queue.
                preparationError=error
                Self.backupLog.error("Could not prepare a library asset: \((error as NSError).code)")
            }
        }
        if let preparationError, prepared == 0 { throw preparationError }
    }

    @MainActor func disableAuto() {
        backupSettingsRevision += 1
        defaults.set(false,forKey:"photo-auto")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.processing)
    }
}
