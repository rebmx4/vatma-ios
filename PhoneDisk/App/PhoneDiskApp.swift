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
    static let surface = Color(white: 23.0 / 255)
    static let accent = Color(uiColor: accentUI)
    static let accentUI = UIColor(red: 164.0 / 255, green: 200.0 / 255, blue: 174.0 / 255, alpha: 1)
    static let selection = Color(red: 36.0 / 255, green: 46.0 / 255, blue: 39.0 / 255)
    static let muted = Color(white: 179.0 / 255)
    static let danger = Color(red: 1, green: 150.0 / 255, blue: 150.0 / 255)
}

@main
struct PhoneDiskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var transfers = Transfers.shared
    @StateObject var disk = Browser()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            DiskScreen(disk:disk,transfers:transfers)
                .preferredColorScheme(.dark)
                .tint(DiskPalette.accent)
                .background(Color.black.ignoresSafeArea())
                .task {
                    #if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.environment["PHONE_DISK_FIXTURE"] != "1" { DiskRoutes.shared.start() }
                    #else
                    DiskRoutes.shared.start()
                    #endif
                    transfers.recover()
                }
                .onReceive(DiskRoutes.shared.$selected.dropFirst()) { route in
                    transfers.routeChanged()
                    disk.changeRoute(route)
                }
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

final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var offline = false
    let uploadSelection = PassthroughSubject<NativePickerRequest,Never>()
    let openTransfers = PassthroughSubject<Void,Never>()
    private let bridge = "phoneDiskNative"
    private var webTab: DiskTab = .files
    lazy var view:WKWebView = {
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.websiteDataStore.proxyConfigurations = DiskRoutes.shared.selected.proxy
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
        if (deviceSettings) deviceSettings.hidden = false;
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
        view.load(URLRequest(url:Transfers.base))
        return view
    }()

    func reload() { offline=false; view.load(URLRequest(url:Transfers.base)) }

    fileprivate func selectWebTab(_ tab: DiskTab) {
        guard tab != .transfers else { return }
        webTab = tab
        syncWebTab()
    }

    private func syncWebTab() {
        guard Transfers.sameHost(view.url) else { return }
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

    func changeRoute(_ route: DiskRoute) {
        WKWebsiteDataStore.default().proxyConfigurations = route.proxy
        if offline { reload() }
    }

    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host==Transfers.base.host,
              message.frameInfo.securityOrigin.protocol==Transfers.base.scheme,
              [0,Transfers.base.port ?? 443].contains(message.frameInfo.securityOrigin.port) else { return }
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
            default:
                break
            }
        } else if let update=message.body as? [String:String], update["action"]=="backup-settings" {
            Task { @MainActor in await Transfers.shared.backupSettingsChanged(enabled:update["enabled"]=="true") }
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
            if Transfers.shared.enqueueDownload(url,nil) { openTransfers.send() }
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
        if (error as NSError).code != NSURLErrorCancelled { offline=true }
        if let error = error as? URLError, error.code != .cancelled { DiskRoutes.shared.failed(DiskRoutes.shared.selected) }
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
    @State private var currentTab: DiskTab = .files
    @State private var selectingTransfers = false
    @State private var selectedTransfers = Set<String>()
    @State private var transfersToRemove = Set<String>()
    @State private var savingToPhotos = Set<String>()
    @State private var showDestinations=false
    @State private var pickPhotos=false
    @State private var pickerType="album"

    var body: some View {
        VStack(spacing:0) {
            ZStack {
                webContent
                    .opacity(currentTab == .transfers ? 0 : 1)
                    .allowsHitTesting(currentTab != .transfers)
                    .accessibilityHidden(currentTab == .transfers)
                if currentTab == .transfers { queue }
            }
            if currentTab == .transfers && selectingTransfers { transferSelectionBar }
            Divider()
            transferTabs.background(DiskPalette.surface)
        }
        .onReceive(disk.openTransfers) { selectTab(.transfers) }
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

    private var webContent: some View {
        VStack(spacing:0) {
            if disk.offline {
                ContentUnavailableView {
                    Label("Домашний ПК недоступен",systemImage:"wifi.slash")
                } actions: { Button("Повторить"){ disk.reload() }.buttonStyle(.borderedProminent) }
            } else { WebSurface(browser:disk) }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["PHONE_DISK_FIXTURE"] == "1" {
                Button("Запустить контрольное скачивание") {
                    let path = "/api/resources/download?source=photos-c&file=%2Fslow%20file%20%2B.bin"
                    if let url = URL(string: path, relativeTo: Transfers.base)?.absoluteURL {
                        disk.view.load(URLRequest(url: url))
                    }
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

    private func pick(_ target:Destination) {
        destination=target
        if pickPhotos { showPhotos=true }
        else { files=true }
    }

    private var queue:some View {
        let jobs = transfers.jobs.filter { $0.hiddenFromQueue != true }
        let removal = jobs.filter { transfersToRemove.contains($0.id) }
        return NavigationStack {
            List(jobs) { job in
                if selectingTransfers {
                    selectableTransfer(job)
                        .listRowBackground(DiskPalette.surface)
                } else {
                    transferRow(job)
                        .listRowBackground(DiskPalette.surface)
                        .swipeActions(edge:.trailing,allowsFullSwipe:false) {
                            Button(role:.destructive) {
                                transfersToRemove = [job.id]
                            } label: { Label("Удалить",systemImage:"trash") }
                            .tint(DiskPalette.danger)
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Передача")
            .toolbarBackground(Color.black,for:.navigationBar)
            .toolbarBackground(.visible,for:.navigationBar)
            .refreshable { await transfers.refreshQueue() }
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button {
                        Task { await transfers.refreshQueue() }
                    } label: {
                        Image(systemName:"arrow.clockwise")
                    }
                    .accessibilityLabel("Обновить передачи")
                }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    if selectingTransfers {
                        Button("Отмена",action:clearTransferSelection)
                    } else {
                        Button("Выбрать") { selectingTransfers = true }.disabled(jobs.isEmpty)
                    }
                }
            }
            .overlay { if jobs.isEmpty { ContentUnavailableView("Передач пока нет",systemImage:"arrow.up.arrow.down") } }
            .alert(removal.count == 1 ? "Удалить запись передачи?" : "Удалить выбранные передачи?",isPresented:Binding(
                get:{ !transfersToRemove.isEmpty },
                set:{ if !$0 { transfersToRemove.removeAll() } }
            ),presenting:removal) { entries in
                Button("Нет",role:.cancel) {}
                Button("Удалить",role:.destructive) {
                    if transfers.removeTransfers(Set(entries.map(\.id))) { clearTransferSelection() }
                }
            } message: { entries in
                if entries.count == 1, let job = entries.first { Text(job.name) }
            }
        }
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
                            .accessibilityHidden(true)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? DiskPalette.accent : DiskPalette.muted)
                .background(selected ? DiskPalette.selection : Color.clear,in:RoundedRectangle(cornerRadius:12))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("queue-tab-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8)
    }

    private func clearTransferSelection() {
        selectingTransfers = false
        selectedTransfers.removeAll()
        transfersToRemove.removeAll()
    }

    private var transferSelectionBar:some View {
        HStack {
            Text("Выбрано \(selectedTransfers.count)").foregroundStyle(.secondary)
            Spacer()
            Button(role:.destructive) {
                transfersToRemove = selectedTransfers
            } label: { Label("Удалить",systemImage:"trash") }
            .accessibilityLabel("Удалить выбранные передачи")
            .disabled(selectedTransfers.isEmpty)
        }
        .padding()
        .background(DiskPalette.surface)
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
        VStack(alignment:.leading,spacing:5) {
            HStack(alignment:.top,spacing:4) {
                VStack(alignment:.leading,spacing:4) {
                    Text(job.name).font(.body)
                    Text(transfers.stopping.contains(job.id) ? "Останавливаю…" : job.phase)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:4)
                if !selectingTransfers && job.downloadURL != nil { downloadActions(job) }
            }
            if !job.isFinished {
                let reading = transfers.readings[job.id]
                transferDetails(reading)
                let progress = reading.map { $0.total > 0 ? min(1,Double($0.visibleBytes)/Double($0.total)) : 0 } ?? job.progress
                ProgressView(value:progress).tint(DiskPalette.accent)
                if !selectingTransfers && job.downloadURL == nil &&
                    !["Выгрузка","Подготовка","Проверка на ПК","Проверка файла"].contains(job.phase) {
                    Button("Продолжить") { transfers.start(job.id) }.buttonStyle(.borderless)
                }
            } else if !selectingTransfers, let name = job.localName {
                let file = Transfers.documents.appendingPathComponent(name)
                HStack {
                    ShareLink(item:file)
                        .buttonStyle(.borderless)
                    if let type = photosResourceType(file,job:job) {
                        let saving = savingToPhotos.contains(job.id)
                        Button {
                            saveToPhotos(job.id,file:file,type:type)
                        } label: {
                            Label(saving ? "Сохраняю…" : "Сохранить в Фото",systemImage:"photo.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(saving)
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
                downloadButton("Остановить скачивание","stop.fill") { transfers.stopDownload(job.id) }
            } else {
                if job.canRetryDownload {
                    downloadButton("Повторить скачивание","arrow.counterclockwise") { transfers.retryDownload(job.id) }
                }
                if job.canRemoveDownload {
                    downloadButton("Удалить запись передачи","trash",role:.destructive) { transfersToRemove = [job.id] }
                }
            }
        }
    }

    private func downloadButton(_ label:String,_ icon:String,role:ButtonRole?=nil,action:@escaping () -> Void) -> some View {
        Button(role:role,action:action) {
            Image(systemName:icon)
                .font(.body.weight(.medium))
                .frame(width:44,height:44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(role == .destructive ? DiskPalette.danger : DiskPalette.accent)
        .accessibilityLabel(Text(label))
    }

    private func transferDetails(_ reading: TransferReading?) -> some View {
        let count = reading?.visibleBytes ?? 0
        let total = reading?.total ?? 0
        let left = max(0,total-count)
        let percent = total > 0 ? Int(100 * Double(count)/Double(total)) : 0
        let size = ByteCountFormatter.string(fromByteCount:count,countStyle:.file)
        let totalSize = ByteCountFormatter.string(fromByteCount:total,countStyle:.file)
        let speed = reading?.bytesPerSecond ?? 0
        return VStack(alignment:.leading,spacing:4) {
            Text(total > 0 ? "\(percent)% · \(size) из \(totalSize)" : "—% · —")
            Text(reading?.connection ?? "Маршрут · —")
            if speed > 0 && left > 0 {
                let seconds = Int(min(86400 * 7,ceil(Double(left) / speed)))
                let eta = Duration.seconds(seconds).formatted(.units(allowed:[.hours,.minutes,.seconds],width:.abbreviated,maximumUnitCount:2))
                Text("\((speed / 1_000_000).formatted(.number.precision(.fractionLength(2)))) МБ/с · \(eta)")
            } else { Text("— МБ/с · —") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
}
