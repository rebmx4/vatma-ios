import BackgroundTasks
import Combine
import CoreTransferable
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

private enum DiskPalette {
    static let accent = Color(uiColor: accentUI)
    static let accentUI = UIColor(red: 164.0 / 255, green: 200.0 / 255, blue: 174.0 / 255, alpha: 1)
    static let muted = Color(white: 179.0 / 255)
    static let separator = Color.white.opacity(0.13)
    static let danger = Color(red: 1, green: 150.0 / 255, blue: 150.0 / 255)
}

private struct DiskCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(DiskPalette.separator).allowsHitTesting(false) }
    }
}

@main
struct PhoneDiskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var transfers = Transfers.shared
    @StateObject var disk = Browser()
    @StateObject private var computers = Computers()
    @StateObject private var filesLock = FilesLock()
    @State private var lockSettings = false
    @State private var disconnect = false
    @State private var addComputer = false
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if computers.connected {
                    DiskScreen(disk: disk, transfers: transfers, filesLock: filesLock)
                } else {
                    PairComputerScreen(computers: computers)
                }
            }
                .preferredColorScheme(.dark)
                .tint(DiskPalette.accent)
                .background(Color.black.ignoresSafeArea())
                .overlay {
                    if filesLock.enabled && phase != .active {
                        Color.black.ignoresSafeArea().accessibilityHidden(true)
                    }
                }
                .task {
                    DiskRoutes.shared.start()
                    if let route = DiskRoutes.shared.selected { disk.changeRoute(route) }
                    else if computers.connected && Transfers.base.host != "127.0.0.1" { disk.reload() }
                    transfers.recover()
                }
                .onReceive(DiskRoutes.shared.$selected.dropFirst()) { route in
                    if computers.connected { disk.changeRoute(route) }
                    if route != nil { transfers.routeChanged() }
                }
                .onReceive(computers.$computer.dropFirst()) { computer in
                    disk.resetWebsite()
                    if computer != nil || PairedComputer.hasLegacyComputer { disk.reload() }
                    if computer != nil {
                        if addComputer { addComputer = false }
                        else if !filesLock.enabled { lockSettings = true }
                    }
                }
                .onReceive(disk.openProtection) { lockSettings = true }
                .onReceive(disk.closeComputer) { disconnect = true }
                .onReceive(disk.openPairing) { addComputer = true }
                .onReceive(disk.accessLost) { Task { await computers.disconnect(revoke: false) } }
                .sheet(isPresented: $addComputer, onDismiss: {
                    if PairedComputer.load() != nil && !filesLock.enabled { lockSettings = true }
                }) {
                    NavigationStack {
                        PairComputerScreen(computers: computers)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Закрыть") { addComputer = false }
                                }
                            }
                    }
                }
                .onChange(of:phase) { _, state in
                    if state == .active {
                        DiskRoutes.shared.refresh()
                        if computers.connected { disk.reconnectIfNeeded() }
                        transfers.recover()
                        Task { try? await transfers.scan() }
                    }
                    if state == .background {
                        filesLock.background()
                        if filesLock.enabled { disk.pauseMedia() }
                        Transfers.schedule()
                    }
                }
                .confirmationDialog("Защита «Файлов»", isPresented: $lockSettings, titleVisibility: .visible) {
                    if filesLock.enabled {
                        Button("Отключить защиту", role: .destructive) { Task { await filesLock.setEnabled(false) } }
                    } else {
                        Button("Включить Face ID или код iPhone") { Task { await filesLock.setEnabled(true) } }
                    }
                    Button("Закрыть", role: .cancel) {}
                } message: {
                    Text("Системная проверка открывает «Файлы» после запуска и возврата в приложение.")
                }
                .alert("Отключить компьютер?", isPresented: $disconnect) {
                    Button("Отключить", role: .destructive) { Task { await computers.disconnect(revoke: true) } }
                    Button("Отмена", role: .cancel) {}
                }
                .alert("Защита «Файлов»", isPresented: Binding(get: { !filesLock.message.isEmpty },
                                                              set: { if !$0 { filesLock.message = "" } })) {
                    Button("Закрыть", role: .cancel) { filesLock.message = "" }
                } message: { Text(filesLock.message) }
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
                await Transfers.scheduleIfNeeded()
                do { try await Transfers.shared.processBackgroundWork(); completion.finish(!Task.isCancelled) }
                catch { completion.finish(false) }
            }
            job.expirationHandler={ run.cancel(); DispatchQueue.main.async { completion.finish(false) } }
        }
        _ = Transfers.shared
        return true
    }

    func application(_ application:UIApplication,handleEventsForBackgroundURLSession identifier:String,completionHandler:@escaping ()->Void) {
        if Transfers.shared.handleV2Events(identifier,completionHandler) { return }
        guard identifier==Transfers.identifier else { completionHandler(); return }
        Transfers.shared.handleEvents(completionHandler)
    }
}

struct NativePickerRequest {
    var destination: Destination?
    var type: String
}

private enum DiskTab: String, CaseIterable {
    case files, backup, transfers

    var title: String {
        switch self {
        case .files: return "Файлы"
        case .backup: return "Автокопии"
        case .transfers: return "Передача"
        }
    }

    var icon: String {
        switch self {
        case .files: return "folder"
        case .backup: return "arrow.clockwise"
        case .transfers: return "arrow.up.arrow.down"
        }
    }
}

private enum TransferDirection: String, CaseIterable {
    case upload, download

    var title: String { self == .upload ? "Выгрузки" : "Скачивания" }
    var icon: String { self == .upload ? "tray.and.arrow.up" : "tray.and.arrow.down" }
    var emptyTitle: String { self == .upload ? "Выгрузок пока нет" : "Скачиваний пока нет" }

    func includes(_ job: DiskJob) -> Bool {
        (job.downloadURL != nil) == (self == .download)
    }
}

enum DiskPageState: Equatable {
    case connecting, ready, unavailable
}

final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published private(set) var pageState: DiskPageState = .connecting
    let uploadSelection = PassthroughSubject<NativePickerRequest,Never>()
    let openTransfers = PassthroughSubject<Void,Never>()
    let openProtection = PassthroughSubject<Void, Never>()
    let closeComputer = PassthroughSubject<Void, Never>()
    let openPairing = PassthroughSubject<Void, Never>()
    let accessLost = PassthroughSubject<Void, Never>()
    @Published private(set) var websiteRevision = UUID()
    private let bridge = "phoneDiskNative"
    private var webTab: DiskTab = .files
    private var pageRoute: DiskRoute?
    private var pageNavigation: WKNavigation?
    private var reconnect: Task<Void, Never>?
    private var webView: WKWebView?
    var view: WKWebView {
        if let webView { return webView }
        let config=WKWebViewConfiguration()
        config.websiteDataStore = PairedComputer.load() == nil ? .default() : .nonPersistent()
        config.allowsInlineMediaPlayback=true
        let nativeTabs = """
        window.phoneDiskNativeTabVersion = 1;
        document.addEventListener('DOMContentLoaded', () => {
          if (typeof window.phoneDiskHostSelectTab !== 'function') {
            const tabs = document.querySelector('nav.bottom-tabs');
            if (tabs) tabs.style.display = 'none';
          }
        }, { once: true });
        """
        config.userContentController.addUserScript(WKUserScript(source:nativeTabs,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        let script = """
        const deviceSettings = document.getElementById('device-settings');
        if (deviceSettings) {
          deviceSettings.hidden = false;
          const button = document.createElement('button');
          button.type = 'button';
          button.dataset.nativeSetting = 'face-settings';
          button.textContent = 'Защита «Файлов»';
          deviceSettings.append(button);
          const link = document.createElement('button');
          link.type = 'button';
          link.dataset.nativeSetting = 'pair-computer';
          link.textContent = 'Добавить компьютер';
          deviceSettings.append(link);
        }
        document.addEventListener('click', event => {
          const bridge = window.webkit.messageHandlers.phoneDiskNative;
          if (event.target.closest('#logout')) bridge.postMessage('revoke-device');
          const setting = event.target.closest('#device-settings [data-native-setting]');
          if (setting) {
            bridge.postMessage(setting.dataset.nativeSetting);
            return;
          }
          if (event.target.closest('button[data-tab=transfers]')) bridge.postMessage('queue');
        },true);
        """
        config.userContentController.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentEnd,forMainFrameOnly:true))
        config.userContentController.add(self,name:bridge)
        let view=WKWebView(frame:.zero,configuration:config)
        view.overrideUserInterfaceStyle = .dark
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.underPageBackgroundColor = .black
        view.tintColor = DiskPalette.accentUI
        view.navigationDelegate=self
        view.uiDelegate=self
        view.allowsBackForwardNavigationGestures=true
        if Transfers.base.host == "127.0.0.1" {
            config.websiteDataStore.proxyConfigurations = []
            pageNavigation = view.load(URLRequest(url: Transfers.base))
        }
        webView = view
        return view
    }

    func resetWebsite() {
        reconnect?.cancel()
        reconnect = nil
        pageNavigation = nil
        pageRoute = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: bridge)
        webView = nil
        webTab = .files
        pageState = .connecting
        websiteRevision = UUID()
    }

    func pauseMedia() {
        webView?.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(media => media.pause())", completionHandler: nil)
    }

    private func accepts(_ url: URL?) -> Bool {
        if let route = pageRoute, route.companionID != nil { return route.acceptsBackgroundURL(url) }
        return PairedComputer.load() == nil && Transfers.sameHost(url)
    }

    func reload() {
        reconnect?.cancel()
        pageState = .connecting
        reconnect = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let route = try await DiskRoutes.shared.resolve()
                try Task.checkCancellation()
                if pageNavigation == nil { load(route) }
            } catch is CancellationError {
                return
            } catch {
                pageState = .unavailable
            }
        }
    }

    func reconnectIfNeeded() {
        if pageState == .unavailable { reload() }
    }

    private func load(_ route: DiskRoute) {
        reconnect?.cancel()
        reconnect = nil
        pageRoute = route
        view.configuration.websiteDataStore.proxyConfigurations = route.proxy
        pageState = .connecting
        let origin = route.webOrigin ?? Transfers.base
        var request = URLRequest(url: origin, cachePolicy: .reloadIgnoringLocalCacheData)
        if let id = route.companionID {
            guard let computer = PairedComputer.load(), computer.id == id else { pageState = .unavailable; return }
            request.setValue("Bearer " + computer.credential.token, forHTTPHeaderField: "Authorization")
        }
        pageNavigation = view.load(request)
    }

    fileprivate func selectWebTab(_ tab: DiskTab) {
        guard tab != .transfers else { return }
        webTab = tab
        syncWebTab()
    }

    private func syncWebTab() {
        guard let webView, accepts(webView.url) else { return }
        let tab = webTab
        let script = """
        (() => {
          if (typeof window.phoneDiskHostSelectTab === 'function') {
            window.phoneDiskHostSelectTab('\(tab.rawValue)');
            return;
          }
          const button = document.querySelector('nav.bottom-tabs button[data-tab="\(tab.rawValue)"]');
          if (button && !button.closest('[hidden]')) button.click();
        })();
        """
        view.evaluateJavaScript(script, completionHandler: nil)
    }

    func changeRoute(_ route: DiskRoute?) {
        guard let route else {
            pageRoute = nil
            pageNavigation = nil
            view.stopLoading()
            pageState = .unavailable
            return
        }
        if pageRoute != route || pageState == .unavailable { load(route) }
    }

    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame, accepts(message.frameInfo.request.url) else { return }
        if let action=message.body as? String {
            switch action {
            case "enable":
                Task { @MainActor in await Transfers.shared.authorization() }
            case "queue":
                openTransfers.send()
            case "disable-auto":
                Task { @MainActor in Transfers.shared.disableAuto() }
            case "notifications":
                Transfers.shared.askNotifications()
            case "revoke-device":
                Task { @MainActor in await Transfers.shared.revokeDevice() }
            case "face-settings":
                openProtection.send()
            case "pair-computer" where pageRoute?.companionID == nil:
                openPairing.send()
            case "unpair" where pageRoute?.companionID != nil:
                closeComputer.send()
            case "access-revoked" where pageRoute?.companionID != nil:
                accessLost.send()
            default:
                break
            }
        } else if let update=message.body as? [String:String], update["action"]=="backup-settings" {
            Task { @MainActor in await Transfers.shared.backupSettingsChanged(enabled:update["enabled"]=="true") }
        } else if let download = message.body as? [String: String], download["action"] == "download",
                  pageRoute?.companionID != nil, let source = download["source"], let path = download["path"],
                  Transfers.valid(Destination(source: source, path: path)) {
            let url = Transfers.address("/api/resources/download", ["source": source, "file": path])
            if Transfers.shared.enqueueDownload(url, download["name"]) { openTransfers.send() }
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
        guard webView === self.webView, accepts(action.request.url) else { decisionHandler(.cancel); return }
        if let url=action.request.url,url.path=="/api/resources/download",(action.request.httpMethod ?? "GET") == "GET" {
            if Transfers.shared.enqueueDownload(url,nil) { openTransfers.send() }
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        if action.targetFrame==nil, accepts(action.request.url) { webView.load(action.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard webView === self.webView, let route = pageRoute, route.companionID != nil else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let (result, credential) = route.evaluate(challenge)
        completionHandler(result, credential)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if webView === self.webView, navigationResponse.isForMainFrame, pageRoute?.companionID != nil,
           let response = navigationResponse.response as? HTTPURLResponse, response.statusCode == 401, accepts(response.url) {
            decisionHandler(.cancel)
            accessLost.send()
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        guard webView === self.webView else { return }
        if let pageNavigation, pageNavigation !== navigation { return }
        pageNavigation = nil
        reconnect?.cancel()
        reconnect = nil
        pageState = .ready
        let install="""
        if (typeof pickUpload === 'function' && !window.phoneDiskUploadsInstalled) {
          window.phoneDiskUploadsInstalled=true;
          pickUpload=(target,type) => {
            const message={action:'upload',type:type || 'files'};
            if(target?.source && target?.path) { message.source=target.source; message.path=target.path; }
            window.webkit.messageHandlers.phoneDiskNative.postMessage(message);
          };
        }
        if (typeof saveSettings === 'function' && !window.phoneDiskBackupInstalled) {
          window.phoneDiskBackupInstalled=true;
          const save=saveSettings;
          saveSettings=async (type, patch) => {
            await save(type, patch);
            window.webkit.messageHandlers.phoneDiskNative.postMessage({
              action:'backup-settings', enabled:String(patch.enabled === true)
            });
          };
        }
        """
        webView.evaluateJavaScript(install,completionHandler:nil)
        syncWebTab()
        Task { @MainActor in try? await Transfers.shared.scan() }
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
        guard webView === self.webView else { return }
        navigationFailed(navigation, error: error)
    }

    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {
        guard webView === self.webView else { return }
        navigationFailed(navigation, error: error)
    }

    private func navigationFailed(_ navigation: WKNavigation?, error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        if let pageNavigation, pageNavigation !== navigation { return }
        pageNavigation = nil
        pageState = .unavailable
        reconnect?.cancel()
        reconnect = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.reload()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {
        pageNavigation = nil
        reload()
    }
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
    @ObservedObject var filesLock: FilesLock
    @Environment(\.scenePhase) private var phase
    @State private var photos:[PhotosPickerItem]=[]
    @State private var destination:Destination?
    @State private var files=false
    @State private var showPhotos=false
    @State private var currentTab: DiskTab = .files
    @State private var transferDirection: TransferDirection = .download
    @State private var selectingTransfers = false
    @State private var selectedTransfers = Set<String>()
    @State private var transfersToRemove = Set<String>()
    @State private var savingToPhotos = Set<String>()
    @State private var showDestinations=false
    @State private var pickPhotos=false
    @State private var pickerType="album"
    @State private var offeredUnlock = false

    var body: some View {
        VStack(spacing:0) {
            ZStack {
                webContent
                    .opacity(currentTab == .transfers || filesLock.needsUnlock ? 0 : 1)
                    .allowsHitTesting(currentTab != .transfers && !filesLock.needsUnlock)
                    .accessibilityHidden(currentTab == .transfers || filesLock.needsUnlock)
                if currentTab != .transfers && filesLock.needsUnlock { unlockScreen }
                if currentTab == .transfers { queue }
            }
            if currentTab == .transfers { transferControls }
            transferTabs
        }
        .background(Color.black)
        .onAppear { unlockIfNeeded() }
        .onChange(of: phase) { _, phase in
            if phase == .background { offeredUnlock = false }
            if phase == .active { unlockIfNeeded() }
        }
        .onChange(of: currentTab) { _, tab in
            if tab != .files { offeredUnlock = false }
            unlockIfNeeded()
        }
        .onReceive(disk.openTransfers) { showTransfers(.download) }
        .onReceive(disk.uploadSelection) { selection in
            pickerType=selection.type
            pickPhotos=selection.type != "files"
            if let destination=selection.destination { pick(destination) }
            else { showDestinations=true }
        }
        .confirmationDialog("Папка назначения",isPresented:$showDestinations,titleVisibility:.visible) {
            Button("Фото и видео · C"){ pick(Destination(source:"photos-c",path:"/")) }
            Button("Видео интервью · D"){ pick(Destination(source:"interviews-d",path:"/")) }
            Button("Видео с камеры · E"){ pick(Destination(source:"camera-e",path:"/")) }
        } message:{ Text("Чтобы выбрать вложенную папку, сначала откройте её в «Файлах».") }
        .fileImporter(isPresented:$files,allowedContentTypes:[.item],allowsMultipleSelection:true) { result in
            do {
                guard let destination else { return }
                let urls = try result.get()
                for url in urls { try transfers.enqueueFile(url,destination:destination) }
                if !urls.isEmpty { showTransfers(.upload) }
            } catch { transfers.message=error.localizedDescription }
        }
        .photosPicker(isPresented:$showPhotos,selection:$photos,maxSelectionCount:20,matching:pickerType=="photo" ? .images : pickerType=="video" ? .videos : .any(of:[.images,.videos]))
        .onChange(of:photos) { _, selected in
            guard !selected.isEmpty, let destination else { return }
            Task {
                var enqueued = false
                do {
                    for photo in selected {
                        guard let file=try await photo.loadTransferable(type:ImportFile.self) else { continue }
                        defer { try? FileManager.default.removeItem(at:file.url.deletingLastPathComponent()) }
                        try transfers.enqueueFile(file.url,destination:destination)
                        enqueued = true
                    }
                } catch { transfers.message=error.localizedDescription }
                if enqueued { showTransfers(.upload) }
                photos=[]
            }
        }
        .alert("Мой диск",isPresented:Binding(get:{!transfers.message.isEmpty},set:{if !$0 {transfers.message=""}})) {
            Button("Закрыть",role:.cancel){ transfers.message="" }
        } message:{ Text(transfers.message) }
    }

    private var unlockScreen: some View {
        ContentUnavailableView {
            Label("Файлы защищены", systemImage: "lock")
        } actions: {
            Button("Разблокировать") { Task { await filesLock.unlock() } }
                .buttonStyle(.borderedProminent)
                .disabled(filesLock.authenticating)
        }
    }

    private func unlockIfNeeded() {
        guard phase == .active, currentTab == .files, filesLock.needsUnlock,
              !filesLock.authenticating, !offeredUnlock else { return }
        offeredUnlock = true
        Task { await filesLock.unlock() }
    }

    private var webContent: some View {
        VStack(spacing:0) {
            ZStack {
                WebSurface(browser:disk)
                    .id(disk.websiteRevision)
                    .opacity(disk.pageState == .ready ? 1 : 0)
                    .allowsHitTesting(disk.pageState == .ready)
                    .accessibilityHidden(disk.pageState != .ready)
                if disk.pageState == .connecting {
                    ProgressView("Подключаюсь к ПК…").tint(DiskPalette.accent)
                } else if disk.pageState == .unavailable {
                    ContentUnavailableView {
                        Label("Домашний ПК недоступен",systemImage:"wifi.slash")
                    } actions: {
                        Button("Повторить"){ disk.reload() }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .background(Color.black)
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["PHONE_DISK_FIXTURE"] == "1" {
                Button("Запустить контрольное скачивание") {
                    let persistence = ProcessInfo.processInfo.environment["PHONE_DISK_FIXTURE_PERSISTENCE"] == "1"
                    let file = persistence ? "/ci-download.txt" : "/slow file +.bin"
                    let url = Transfers.address("/api/resources/download", ["source": "photos-c", "file": file])
                    disk.view.load(URLRequest(url: url))
                }
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
    }

    private func selectTab(_ tab: DiskTab) {
        guard currentTab != tab else { return }
        if currentTab == .transfers { clearTransferSelection() }
        currentTab = tab
        if tab != .transfers { disk.selectWebTab(tab) }
    }

    private func showTransfers(_ direction: TransferDirection) {
        selectTransferDirection(direction)
        selectTab(.transfers)
    }

    private func selectTransferDirection(_ direction: TransferDirection) {
        guard transferDirection != direction else { return }
        clearTransferSelection()
        transferDirection = direction
    }

    private func pick(_ target:Destination) {
        destination=target
        if pickPhotos { showPhotos=true }
        else { files=true }
    }

    private var visibleTransfers: [DiskJob] {
        transfers.jobs.filter { Transfers.belongsToCurrentComputer($0) && $0.hiddenFromQueue != true && transferDirection.includes($0) }
    }

    private var queue: some View {
        let removal = visibleTransfers.filter { transfersToRemove.contains($0.id) }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Передача")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            if visibleTransfers.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: transferDirection.icon)
                        .font(.title2)
                        .foregroundStyle(DiskPalette.muted)
                        .accessibilityHidden(true)
                    Text(transferDirection.emptyTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleTransfers) { job in
                    Group {
                        if selectingTransfers {
                            selectableTransfer(job)
                        } else {
                            transferRow(job)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        transfersToRemove = [job.id]
                                    } label: { Label("Удалить", systemImage: "trash") }
                                    .tint(DiskPalette.danger)
                                }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 14))
                    .listRowBackground(Color.black)
                    .listRowSeparatorTint(DiskPalette.separator)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 52)
                .refreshable { await transfers.refreshQueue() }
            }
        }
        .background(Color.black)
        .alert(removal.count == 1 ? "Удалить запись передачи?" : "Удалить выбранные передачи?", isPresented: Binding(
            get: { !transfersToRemove.isEmpty },
            set: { if !$0 { transfersToRemove.removeAll() } }
        ), presenting: removal) { entries in
            Button("Нет", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if transfers.removeTransfers(Set(entries.map(\.id))) { clearTransferSelection() }
            }
        } message: { entries in
            if entries.count == 1, let job = entries.first { Text(job.name) }
        }
    }

    private var transferControls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if selectingTransfers { transferSelectionBar }
            HStack(spacing: 7) {
                HStack(spacing: 0) {
                    ForEach(TransferDirection.allCases, id: \.self) { direction in
                        let selected = direction == transferDirection
                        Button {
                            selectTransferDirection(direction)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: direction.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(selected ? DiskPalette.accent : DiskPalette.muted)
                                    .accessibilityHidden(true)
                                Text(direction.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(DiskPalette.muted)
                            }
                            .padding(.horizontal, 7)
                            .frame(minWidth: 44, minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("queue-direction-\(direction.rawValue)")
                    }
                }
                .padding(.horizontal, 3)
                .modifier(DiskCapsule())

                HStack(spacing: 0) {
                    transferIcon("Обновить передачи", "arrow.clockwise", color: .primary) {
                        Task { await transfers.refreshQueue() }
                    }
                    transferIcon(selectingTransfers ? "Отмена" : "Выбрать",
                                 selectingTransfers ? "xmark" : "checkmark.circle") {
                        if selectingTransfers { clearTransferSelection() }
                        else { selectingTransfers = true }
                    }
                    .disabled(!selectingTransfers && visibleTransfers.isEmpty)
                    .opacity(!selectingTransfers && visibleTransfers.isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, 2)
                .frame(minHeight: 48)
                .modifier(DiskCapsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var transferTabs: some View {
        HStack(spacing: 0) {
            ForEach(DiskTab.allCases, id: \.self) { tab in
                let selected = tab == currentTab
                Button {
                    selectTab(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(selected ? DiskPalette.accent : DiskPalette.muted)
                            .accessibilityHidden(true)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DiskPalette.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("queue-tab-\(tab.rawValue)")
            }
        }
        .padding(2)
        .modifier(DiskCapsule())
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func clearTransferSelection() {
        selectingTransfers = false
        selectedTransfers.removeAll()
        transfersToRemove.removeAll()
    }

    private var transferSelectionBar: some View {
        HStack {
            Text("Выбрано \(selectedTransfers.count)").foregroundStyle(DiskPalette.muted)
            Spacer()
            Button(role: .destructive) {
                transfersToRemove = selectedTransfers
            } label: {
                Label("Удалить", systemImage: "trash")
                    .frame(minHeight: 44)
            }
            .foregroundStyle(DiskPalette.danger)
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить выбранные передачи")
            .disabled(selectedTransfers.isEmpty)
            .opacity(selectedTransfers.isEmpty ? 0.4 : 1)
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
    }

    private func selectableTransfer(_ job:DiskJob) -> some View {
        let selected = selectedTransfers.contains(job.id)
        return Button {
            if selected { selectedTransfers.remove(job.id) }
            else { selectedTransfers.insert(job.id) }
        } label: {
            HStack {
                transferRow(job)
                Spacer()
                Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? DiskPalette.accent : DiskPalette.muted)
                    .frame(width:44,height:44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(job.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func transferRow(_ job:DiskJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(transfers.stopping.contains(job.id) ? "Останавливаю…" : job.phase)
                        .font(.caption)
                        .foregroundStyle(DiskPalette.muted)
                }
                Spacer(minLength: 0)
                if !selectingTransfers {
                    if job.downloadURL != nil {
                        if job.isFinished, let name = job.localName {
                            if filesLock.needsUnlock {
                                transferIcon("Разблокировать скачанный файл", "lock") { Task { await filesLock.unlock() } }
                            } else {
                                completedDownload(job, name: name)
                            }
                        }
                        downloadActions(job)
                    } else if !job.isFinished &&
                        !["Выгрузка", "Подготовка", "Проверка на ПК", "Проверка файла"].contains(job.phase) {
                        transferIcon("Продолжить", "arrow.clockwise") { transfers.start(job.id) }
                    }
                }
            }
            if !job.isFinished {
                transferDetails(job)
            }
        }
    }

    private func completedDownload(_ job: DiskJob, name: String) -> some View {
        let file = Transfers.documents.appendingPathComponent(name)
        return HStack(spacing: 0) {
            ShareLink(item: file) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DiskPalette.accent)
            .accessibilityLabel("Поделиться")
            .accessibilityIdentifier("queue-share")
            if let type = photosResourceType(file, job: job) {
                if savingToPhotos.contains(job.id) {
                    ProgressView().tint(DiskPalette.accent).frame(width: 44, height: 44)
                        .accessibilityLabel("Сохраняю в Фото")
                } else {
                    transferIcon("Сохранить в Фото", "photo.badge.plus") {
                        saveToPhotos(job.id, file: file, type: type)
                    }
                }
            }
        }
    }

    private func photosResourceType(_ file: URL,job: DiskJob) -> PHAssetResourceType? {
        guard job.isFinished, job.downloadURL != nil, let name = job.localName,
              name == file.lastPathComponent, name != ".", name != ".." else { return nil }
        let ext = file.pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension:ext) else { return nil }
        if type.conforms(to:.image) { return .photo }
        if type.conforms(to:.movie) || type.conforms(to:.video) { return .video }
        return nil
    }

    @MainActor private func saveToPhotos(_ id: String,file: URL,type: PHAssetResourceType) {
        guard savingToPhotos.insert(id).inserted else { return }
        Task { @MainActor in
            defer { savingToPhotos.remove(id) }
            let values = try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  FileManager.default.isReadableFile(atPath:file.path) else {
                transfers.message = "Скачанный файл не найден."
                return
            }
            let access = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
            guard access == .authorized || access == .limited else {
                transfers.message = "Разрешите «Моему диску» добавлять файлы в «Фото» в настройках iPhone."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    PHAssetCreationRequest.forAsset().addResource(with:type,fileURL:file,options:options)
                }
                transfers.message = "Сохранено в «Фото»."
            } catch {
                transfers.message = "Не удалось добавить файл в «Фото». Оригинал остался в «Моём диске»."
            }
        }
    }

    private func downloadActions(_ job:DiskJob) -> some View {
        HStack(spacing:0) {
            if transfers.stopping.contains(job.id) {
                ProgressView().tint(DiskPalette.accent).frame(width:44,height:44)
            } else if job.canStopDownload {
                transferIcon("Остановить скачивание", "stop.fill") { transfers.stopDownload(job.id) }
            } else {
                if job.canRetryDownload {
                    transferIcon("Повторить скачивание", "arrow.counterclockwise") { transfers.retryDownload(job.id) }
                }
                if job.canRemoveDownload {
                    transferIcon("Удалить запись передачи", "trash", color: DiskPalette.danger, role: .destructive) {
                        transfersToRemove = [job.id]
                    }
                }
            }
        }
    }

    private func transferIcon(_ label: String, _ icon: String, color: Color = DiskPalette.accent,
                              role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role:role,action:action) {
            Image(systemName:icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width:44,height:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(color)
        .accessibilityLabel(Text(label))
    }

    private func transferDetails(_ job: DiskJob) -> some View {
        let reading = transfers.readings[job.id]
        let total = reading?.total ?? 0
        let count = min(total, reading?.visibleBytes ?? 0)
        let progress = total > 0 ? Double(count) / Double(total) : job.progress
        let size = ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
        let totalSize = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        let speed = reading?.bytesPerSecond ?? 0
        let left = total - count
        var route = reading?.connection ?? "Маршрут · —"
        if speed > 0 && left > 0 {
            let seconds = Int(min(86400 * 7, ceil(Double(left) / speed)))
            let eta = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds],
                                                                 width: .abbreviated, maximumUnitCount: 2))
            route += " · \(eta)"
        }
        let rate = speed > 0 ? (speed / 1_000_000).formatted(.number.precision(.fractionLength(2))) : "—"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(total > 0 ? "\(Int(100 * progress))% · \(size) из \(totalSize)" : "—% · —")
                Spacer(minLength: 3)
                Text("\(rate) МБ/с")
                    .fixedSize(horizontal: true, vertical: false)
            }
            ProgressView(value: progress).tint(DiskPalette.accent)
            Text(route)
        }
        .font(.caption)
        .foregroundStyle(DiskPalette.muted)
        .monospacedDigit()
        .lineLimit(1)
    }
}
