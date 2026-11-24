import BackgroundTasks
import Foundation
import Photos
import SwiftUI
import UserNotifications
import WebKit

struct Destination: Codable {
    var source: String
    var path: String
}

struct DiskJob: Codable, Identifiable {
    var id: String
    var name: String
    var destination: Destination?
    var downloadURL: URL?
    var asset: String?
    var phase: String = "Ожидает"
    var uploaded = false
    var progress: Double = 0
    var localName: String?
}

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
    static let base = URL(string:"https://files.rynpro.ru/")!
    static let processing = "ru.atma.phonedisk.scan"
    static let identifier = "ru.atma.phonedisk.transfers"
    static let sources = Set(["photos-c","interviews-d","camera-e","backup-c","backup-d","backup-e"])
    private static let support = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        .appendingPathComponent("PhoneDisk",isDirectory:true)
    static let documents = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
    @Published private(set) var jobs: [DiskJob] = []
    @Published var message = ""
    private let queueURL = Transfers.support.appendingPathComponent("queue.json")
    private var active = Set<String>()
    private var completion: (() -> Void)?
    private var eventWork = 0
    private var eventsFinished = false
    private var scanning = false
    private let defaults = UserDefaults.standard

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier:Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpShouldSetCookies = false
        return URLSession(configuration:config,delegate:self,delegateQueue:.main)
    }()

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at:Self.support,withIntermediateDirectories:true)
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
        url?.scheme == "https" && url?.host == base.host && (url?.port == nil || url?.port == 443) && url?.user == nil && url?.password == nil
    }

    func recover() {
        session.getAllTasks { tasks in
            DispatchQueue.main.async {
                self.active.formUnion(tasks.compactMap(\.taskDescription))
                for job in self.jobs where job.phase != "Готово" && !self.active.contains(job.id) {
                    self.start(job.id)
                }
            }
        }
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

    private func save() {
        if let encoded = try? JSONEncoder().encode(jobs) { try? encoded.write(to:queueURL,options:.atomic) }
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

    private func request(_ url:URL, method:String = "GET") async throws -> URLRequest {
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
        let (data, response) = try await URLSession.shared.data(for:request)
        guard let response = response as? HTTPURLResponse, Self.sameHost(response.url) else { throw DiskFailure.rejected }
        guard (200..<300).contains(response.statusCode) else { throw DiskFailure.response(response.statusCode) }
        return data
    }

    private func mkdir(_ destination:Destination) async throws {
        let url = Self.address("/api/resources",["source":destination.source,"path":destination.path,"isDir":"true","override":"false"])
        do { _ = try await checked(request(url,method:"POST")) }
        catch DiskFailure.response(409) { _ = try await checked(request(Self.address("/api/resources",["source":destination.source,"path":destination.path]))) }
    }

    private func stage(_ id:String) -> URL { Self.support.appendingPathComponent(id) }
    private func filename(_ name:String) -> String {
        let legal = name.replacingOccurrences(of:"[<>:\"/\\\\|?*\\x00-\\x1F]",with:"_",options:.regularExpression)
            .trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:".")))
        return legal.isEmpty ? "Файл" : String(legal.prefix(120))
    }

    func enqueueFile(_ url:URL, destination:Destination, name:String? = nil, asset:String? = nil) throws {
        guard Self.valid(destination) else { throw DiskFailure.rejected }
        if let asset, jobs.contains(where:{$0.asset==asset}) { return }
        let id = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at:url,to:stage(id))
        jobs.insert(DiskJob(id:id,name:filename(name ?? url.lastPathComponent),destination:destination,asset:asset),at:0)
        save()
        start(id)
    }

    func enqueueDownload(_ url:URL,_ name:String?) {
        guard Self.sameHost(url), url.path == "/api/resources/download" else { return }
        let query = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        guard let source=query.first(where:{$0.name=="source"})?.value,Self.sources.contains(source) else { return }
        let suggested = query.first(where:{$0.name=="file"})?.value
        let id = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        jobs.insert(DiskJob(id:id,name:filename(name ?? suggested.map { ($0 as NSString).lastPathComponent } ?? "Файл"),downloadURL:url),at:0)
        save()
        start(id)
    }

    func start(_ id:String) {
        guard !active.contains(id),let job=jobs.first(where:{$0.id==id}),job.phase != "Готово" else { return }
        active.insert(id)
        update(id){$0.phase="Подготовка"}
        Task { @MainActor in
            do {
                if let destination=job.destination {
                    if job.uploaded { try await publish(job,destination); done(id); return }
                    let hold=Destination(source:destination.source,path:"/.phone-disk-incoming")
                    try await mkdir(hold)
                    if destination.source.hasPrefix("backup-") && destination.path != "/" { try await mkdir(destination) }
                    var transfer=try await request(Self.address("/api/resources",["source":destination.source,"path":hold.path+"/"+id,"isDir":"false","override":"true"]),method:"POST")
                    transfer.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
                    let task=session.uploadTask(with:transfer,fromFile:stage(id))
                    task.taskDescription=id
                    update(id){$0.phase="Выгрузка"}
                    task.resume()
                } else if let url=job.downloadURL {
                    let task=session.downloadTask(with:try await request(url))
                    task.taskDescription=id
                    update(id){$0.phase="Скачивание"}
                    task.resume()
                }
            } catch { failed(id,error.localizedDescription) }
        }
    }

    private func publish(_ job:DiskJob,_ destination:Destination) async throws {
        let source=destination.source, stage="/.phone-disk-incoming/"+job.id
        let path=(destination.path == "/" ? "" : destination.path)+"/"+job.id.prefix(12)+"-"+job.name
        var move=try await request(Self.address("/api/resources"),method:"PATCH")
        move.setValue("application/json",forHTTPHeaderField:"Content-Type")
        move.httpBody=try JSONSerialization.data(withJSONObject:["action":"move","items":[["fromSource":source,"fromPath":stage,"toSource":source,"toPath":path]],"overwrite":false,"rename":false])
        do {
            let data=try await checked(move)
            let value=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            let success=value?["succeeded"] as? [[String:Any]]
            guard success?.contains(where:{($0["toPath"] as? String)==path}) == true else { throw DiskFailure.rejected }
        } catch {
            let check=try await request(Self.address("/api/resources",["source":source,"path":path]))
            _ = try await checked(check)
        }
    }

    private func done(_ id:String) {
        active.remove(id)
        update(id){$0.phase="Готово";$0.progress=1}
        try? FileManager.default.removeItem(at:stage(id))
        notify(success:true)
    }

    private func failed(_ id:String,_ text:String) {
        active.remove(id)
        update(id){$0.phase=text}
        notify(success:false)
    }

    func urlSession(_ session:URLSession,task:URLSessionTask,didSendBodyData bytesSent:Int64,totalBytesSent:Int64,totalBytesExpectedToSend:Int64) {
        if let id=task.taskDescription,totalBytesExpectedToSend>0 {
            update(id){$0.progress=Double(totalBytesSent)/Double(totalBytesExpectedToSend)}
        }
    }

    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if let id=downloadTask.taskDescription,totalBytesExpectedToWrite>0 {
            update(id){$0.progress=Double(totalBytesWritten)/Double(totalBytesExpectedToWrite)}
        }
    }

    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        guard let id=downloadTask.taskDescription,let job=jobs.first(where:{$0.id==id}),
              let reply=downloadTask.response as? HTTPURLResponse,(200..<300).contains(reply.statusCode),Self.sameHost(reply.url) else { return }
        let name=String(id.prefix(8))+"-"+job.name
        do {
            try FileManager.default.moveItem(at:location,to:Self.documents.appendingPathComponent(name))
            update(id){$0.localName=name}
        } catch { failed(id,error.localizedDescription) }
    }

    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard let id=task.taskDescription,let job=jobs.first(where:{$0.id==id}) else { return }
        if let error { failed(id,error.localizedDescription); return }
        guard let response=task.response as? HTTPURLResponse,(200..<300).contains(response.statusCode),Self.sameHost(response.url) else {
            failed(id,DiskFailure.response((task.response as? HTTPURLResponse)?.statusCode ?? 0).localizedDescription); return
        }
        if let destination=job.destination {
            update(id){$0.uploaded=true;$0.phase="Проверка на ПК"}
            eventWork += 1
            Task { @MainActor in
                do { try await publish(job,destination); done(id) }
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
        guard UserDefaults.standard.bool(forKey:"photo-auto") else { return }
        let request=BGProcessingTaskRequest(identifier:processing)
        request.requiresNetworkConnectivity=true
        request.earliestBeginDate=Date(timeIntervalSinceNow:900)
        try? BGTaskScheduler.shared.submit(request)
    }

    func authorization() async {
        let status=await PHPhotoLibrary.requestAuthorization(for:.readWrite)
        guard status == .authorized || status == .limited else {
            message="Медиатека недоступна. Разрешение можно изменить в настройках iPhone."; return
        }
        if !defaults.bool(forKey:"photo-auto") { defaults.set(Date(),forKey:"photo-cutoff") }
        defaults.set(true,forKey:"photo-auto")
        Self.schedule()
        try? await scan()
    }

    func scan() async throws {
        guard !scanning,defaults.bool(forKey:"photo-auto"),
              let cutoff=defaults.object(forKey:"photo-cutoff") as? Date else { return }
        let access=PHPhotoLibrary.authorizationStatus(for:.readWrite)
        guard access == .authorized || access == .limited else { return }
        scanning=true
        defer { scanning=false }
        let data=try await checked(request(Self.address("/api/resources/download",["source":"settings","file":"/autocopies.json"])))
        guard let settings=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw DiskFailure.rejected }
        let options=PHFetchOptions()
        options.predicate=NSPredicate(format:"creationDate >= %@",cutoff as NSDate)
        options.sortDescriptors=[NSSortDescriptor(key:"creationDate",ascending:true)]
        let assets=PHAsset.fetchAssets(with:options)
        var queued=0
        for index in 0..<assets.count {
            try Task.checkCancellation()
            if queued>=10 { break }
            let item=assets.object(at:index)
            let video=item.mediaType == .video
            guard video || item.mediaType == .image,
                  let preference=settings[video ? "video":"photo"] as? [String:Any],preference["enabled"] as? Bool == true,
                  let disk=(preference["disk"] as? String)?.lowercased(),["c","d","e"].contains(disk),
                  !jobs.contains(where:{$0.asset==item.localIdentifier}),
                  let asset=PHAssetResource.assetResources(for:item).first(where:{video ? $0.type == .video : $0.type == .photo}) else { continue }
            let temporary=Self.support.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:temporary) }
            let settings=PHAssetResourceRequestOptions()
            settings.isNetworkAccessAllowed=true
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                PHAssetResourceManager.default().writeData(for:asset,toFile:temporary,options:settings) { error in
                    if let error { continuation.resume(throwing:error) } else { continuation.resume() }
                }
            }
            try Task.checkCancellation()
            try enqueueFile(temporary,destination:Destination(source:"backup-"+disk,path:video ? "/Видео":"/Фото"),
                            name:asset.originalFilename,asset:item.localIdentifier)
            queued += 1
        }
    }

    func disableAuto() {
        defaults.set(false,forKey:"photo-auto")
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.processing)
    }
}
