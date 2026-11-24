import BackgroundTasks
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

@main
struct PhoneDiskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var transfers = Transfers.shared
    @StateObject var disk = Browser()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            DiskScreen(disk:disk,transfers:transfers)
                .onChange(of:phase) { _, state in
                    if state == .active { transfers.recover(); Task { try? await transfers.scan() } }
                    if state == .background { Transfers.schedule() }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]? = nil)->Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier:Transfers.processing,using:nil) { job in
            let run = Task { @MainActor in
                Transfers.schedule()
                do { try await Transfers.shared.scan(); job.setTaskCompleted(success:!Task.isCancelled) }
                catch { job.setTaskCompleted(success:false) }
            }
            job.expirationHandler={ run.cancel() }
        }
        _ = Transfers.shared
        return true
    }

    func application(_ application:UIApplication,handleEventsForBackgroundURLSession identifier:String,completionHandler:@escaping ()->Void) {
        guard identifier==Transfers.identifier else { completionHandler(); return }
        Transfers.shared.handleEvents(completionHandler)
    }
}

final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var offline = false
    private let bridge = "phoneDiskNative"
    lazy var view:WKWebView = {
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback=true
        let script = """
        document.addEventListener('click',e=>{
          const el=e.target.closest('button[data-action^="enable:"]');
          if(el?.getAttribute('aria-checked')==='false') window.webkit.messageHandlers.phoneDiskNative.postMessage('enable');
        },true);
        """
        config.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentEnd,forMainFrameOnly:true))
        config.userContentController.add(self,name:bridge)
        let view=WKWebView(frame:.zero,configuration:config)
        view.navigationDelegate=self
        view.uiDelegate=self
        view.allowsBackForwardNavigationGestures=true
        view.load(URLRequest(url:Transfers.base))
        return view
    }()

    func destination() async -> Destination? {
        let script="typeof folder === 'object' && folder ? {source:folder.source,path:folder.path} : null"
        guard let result=try? await view.evaluateJavaScript(script) as? [String:String],
              let source=result["source"],let path=result["path"] else { return nil }
        let destination=Destination(source:source,path:path)
        return Transfers.valid(destination) ? destination : nil
    }

    func openBackup() { view.evaluateJavaScript("typeof switchTab==='function' && switchTab('backup')",completionHandler:nil) }
    func reload() { offline=false; view.load(URLRequest(url:Transfers.base)) }

    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host==Transfers.base.host,
              message.frameInfo.securityOrigin.protocol=="https",message.body as? String == "enable" else { return }
        Task { @MainActor in await Transfers.shared.authorization() }
    }

    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
        guard Transfers.sameHost(action.request.url) else { decisionHandler(.cancel); return }
        if let url=action.request.url,url.path=="/api/resources/download",(action.request.httpMethod ?? "GET") == "GET" {
            Transfers.shared.enqueueDownload(url,nil)
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if action.targetFrame==nil,Transfers.sameHost(action.request.url) { webView.load(action.request) }
        return nil
    }

    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        offline=false
        Task { @MainActor in try? await Transfers.shared.scan() }
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        if (error as NSError).code != NSURLErrorCancelled { offline=true }
    }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { reload() }
}

struct WebSurface: UIViewRepresentable {
    let browser:Browser
    func makeUIView(context:Context)->WKWebView { browser.view }
    func updateUIView(_ view:WKWebView,context:Context) {}
}

struct ImportFile: Transferable {
    let url:URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType:.item) { file in
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let target=folder.appendingPathComponent(file.file.lastPathComponent)
            try FileManager.default.copyItem(at:file.file,to:target)
            return Self(url:target)
        }
    }
}

struct DiskScreen: View {
    @ObservedObject var disk:Browser
    @ObservedObject var transfers:Transfers
    @State private var photos:[PhotosPickerItem]=[]
    @State private var destination:Destination?
    @State private var files=false
    @State private var showPhotos=false
    @State private var showQueue=false
    @State private var showDestinations=false
    @State private var pickPhotos=false

    var body: some View {
        VStack(spacing:0) {
            if disk.offline {
                ContentUnavailableView {
                    Label("Домашний ПК недоступен",systemImage:"wifi.slash")
                } actions: { Button("Повторить"){ disk.reload() }.buttonStyle(.borderedProminent) }
            } else { WebSurface(browser:disk) }
            HStack {
                Menu {
                    Button("Выгрузить из Файлов",systemImage:"folder"){ choose(false) }
                    Button("Выгрузить из Фото",systemImage:"photo"){ choose(true) }
                    Button("Автокопии",systemImage:"arrow.triangle.2.circlepath"){ disk.openBackup() }
                    Button("Разрешить медиатеку",systemImage:"photo.on.rectangle"){
                        Task { await transfers.authorization(); disk.openBackup() }
                    }
                    Button("Выключить обнаружение фото на iPhone"){ transfers.disableAuto() }
                    Button("Уведомления о передаче",systemImage:"bell"){ transfers.askNotifications() }
                } label: { Label("Мой диск",systemImage:"externaldrive") }
                Spacer()
                Button { showQueue=true } label: { Label("Передача",systemImage:"arrow.up.arrow.down") }
            }
            .font(.footnote).padding(.horizontal,14).padding(.vertical,7)
            .background(.bar)
        }
        .sheet(isPresented:$showQueue) { queue }
        .confirmationDialog("Папка назначения",isPresented:$showDestinations,titleVisibility:.visible) {
            Button("Фото и видео · C"){ pick(Destination(source:"photos-c",path:"/")) }
            Button("Видео интервью · D"){ pick(Destination(source:"interviews-d",path:"/")) }
            Button("Видео с камеры · E"){ pick(Destination(source:"camera-e",path:"/")) }
        } message:{ Text("Чтобы выбрать вложенную папку, сначала откройте её в «Файлах».") }
        .fileImporter(isPresented:$files,allowedContentTypes:[.item],allowsMultipleSelection:true) { result in
            do { if let destination { for url in try result.get() { try transfers.enqueueFile(url,destination:destination) } } }
            catch { transfers.message=error.localizedDescription }
        }
        .photosPicker(isPresented:$showPhotos,selection:$photos,maxSelectionCount:20,matching:.any(of:[.images,.videos]))
        .onChange(of:photos) { _, selected in
            guard !selected.isEmpty, let destination else { return }
            Task {
                do {
                    for photo in selected {
                        guard let file=try await photo.loadTransferable(type:ImportFile.self) else { continue }
                        defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
                        try transfers.enqueueFile(file.url,destination:destination)
                    }
                } catch { transfers.message=error.localizedDescription }
                photos=[]
            }
        }
        .alert("Мой диск",isPresented:Binding(get:{!transfers.message.isEmpty},set:{if !$0 {transfers.message=""}})) {
            Button("Закрыть",role:.cancel){ transfers.message="" }
        } message:{ Text(transfers.message) }
    }

    private func choose(_ isPhoto:Bool) {
        pickPhotos=isPhoto
        Task { @MainActor in
            if let folder=await disk.destination() { pick(folder) }
            else { showDestinations=true }
        }
    }
    private func pick(_ target:Destination) {
        destination=target
        if pickPhotos { showPhotos=true }
        else { files=true }
    }

    private var queue:some View {
        NavigationStack {
            List(transfers.jobs) { job in
                VStack(alignment:.leading,spacing:5) {
                    Text(job.name).font(.body)
                    Text(job.phase).font(.caption).foregroundStyle(.secondary)
                    if job.phase != "Готово" {
                        ProgressView(value:job.progress)
                        Button("Продолжить"){ transfers.start(job.id) }.buttonStyle(.borderless)
                    } else if let name=job.localName {
                        ShareLink(item:Transfers.documents.appendingPathComponent(name))
                    }
                }
            }
            .navigationTitle("Передача")
            .toolbar { ToolbarItem(placement:.topBarTrailing){ Button("Готово"){showQueue=false} } }
            .overlay { if transfers.jobs.isEmpty { ContentUnavailableView("Передач пока нет",systemImage:"arrow.up.arrow.down") } }
        }
    }
}
