import BackgroundTasks
import Combine
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
    private final class ProcessingCompletion {
        let job:BGTask
        private var finished=false
        init(_ job:BGTask) { self.job=job }
        func finish(_ success:Bool) {
            guard !finished else { return }
            finished=true
            job.setTaskCompleted(success:success)
        }
    }
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]? = nil)->Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier:Transfers.processing,using:nil) { job in
            let completion=ProcessingCompletion(job)
            let run = Task { @MainActor in
                Transfers.schedule()
                do { try await Transfers.shared.scan(); completion.finish(!Task.isCancelled) }
                catch { completion.finish(false) }
            }
            job.expirationHandler={ run.cancel(); DispatchQueue.main.async { completion.finish(false) } }
        }
        _ = Transfers.shared
        return true
    }

    func application(_ application:UIApplication,handleEventsForBackgroundURLSession identifier:String,completionHandler:@escaping ()->Void) {
        guard identifier==Transfers.identifier else { completionHandler(); return }
        Transfers.shared.handleEvents(completionHandler)
    }
}

struct NativePickerRequest {
    var destination: Destination?
    var type: String
}

final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var offline = false
    let uploadSelection = PassthroughSubject<NativePickerRequest,Never>()
    let openTransfers = PassthroughSubject<Void,Never>()
    private let bridge = "phoneDiskNative"
    lazy var view:WKWebView = {
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback=true
        let script = """
        const deviceSettings = document.getElementById('device-settings');
        if (deviceSettings) deviceSettings.hidden = false;
        document.addEventListener('click', event => {
          const bridge = window.webkit.messageHandlers.phoneDiskNative;
          const setting = event.target.closest('#device-settings [data-native-setting]');
          if (setting) {
            bridge.postMessage(setting.dataset.nativeSetting);
            return;
          }
          if (event.target.closest('button[data-tab=transfers]')) bridge.postMessage('queue');
          const toggle = event.target.closest('button[data-action^="enable:"]');
          if (toggle?.getAttribute('aria-checked') === 'false') bridge.postMessage('enable');
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

    func reload() { offline=false; view.load(URLRequest(url:Transfers.base)) }

    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host==Transfers.base.host,
              message.frameInfo.securityOrigin.protocol==Transfers.base.scheme else { return }
        if let action=message.body as? String {
            switch action {
            case "enable":
                Task { @MainActor in await Transfers.shared.authorization() }
            case "queue":
                openTransfers.send(())
            case "disable-auto":
                Transfers.shared.disableAuto()
            case "notifications":
                Transfers.shared.askNotifications()
            default:
                break
            }
        } else if let selection=message.body as? [String:String], selection["action"]=="upload" {
            let type=selection["type"] ?? "files"
            guard ["files","album","photo","video"].contains(type) else { return }
            if let source=selection["source"],let path=selection["path"] {
                let target=Destination(source:source,path:path)
                guard Transfers.valid(target) else { return }
                uploadSelection.send(NativePickerRequest(destination:target,type:type))
            } else { uploadSelection.send(NativePickerRequest(destination:nil,type:type)) }
        }
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
        let install="""
        if (typeof pickUpload === 'function' && !window.phoneDiskUploadsInstalled) {
          window.phoneDiskUploadsInstalled=true;
          pickUpload=(target,type) => {
            const message={action:'upload',type:type || 'files'};
            if(target?.source && target?.path) { message.source=target.source; message.path=target.path; }
            window.webkit.messageHandlers.phoneDiskNative.postMessage(message);
          };
        }
        """
        webView.evaluateJavaScript(install,completionHandler:nil)
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
    @State private var pickerType="album"

    var body: some View {
        VStack(spacing:0) {
            if disk.offline {
                ContentUnavailableView {
                    Label("Домашний ПК недоступен",systemImage:"wifi.slash")
                } actions: { Button("Повторить"){ disk.reload() }.buttonStyle(.borderedProminent) }
            } else { WebSurface(browser:disk) }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["PHONE_DISK_FIXTURE"] == "1" {
                Button("Выбрать пробный файл") {
                    let url=FileManager.default.temporaryDirectory.appendingPathComponent("fixture-source.txt")
                    do {
                        try Data("PhoneDisk fixture bytes\n".utf8).write(to:url)
                        try transfers.enqueueFile(url,destination:Destination(source:"photos-c",path:"/"),name:"fixture-data.txt")
                    } catch { transfers.message=error.localizedDescription }
                }
            }
            #endif
        }
        .onReceive(disk.openTransfers) { _ in
            showQueue=true
        }
        .onReceive(disk.uploadSelection) { selection in
            pickerType=selection.type
            pickPhotos=selection.type != "files"
            if let destination=selection.destination { pick(destination) }
            else { showDestinations=true }
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
        .photosPicker(isPresented:$showPhotos,selection:$photos,maxSelectionCount:20,matching:pickerType=="photo" ? .images : pickerType=="video" ? .videos : .any(of:[.images,.videos]))
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
