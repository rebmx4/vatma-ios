import Foundation
import WebKit
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class BrowserMediaController: NSObject, WKScriptMessageHandler {
    private final class Binding {
        weak var view: WKWebView?
        let tabID: String
        var revision = 0
        init(_ view: WKWebView, _ tabID: String) { self.view = view; self.tabID = tabID }
    }
    private var bindings: [ObjectIdentifier: Binding] = [:]
    private weak var owner: WKWebView?
    private var snapshot: [String: Any] = ["available": false]
    private var generation = 0
    var didChange: (() -> Void)?
    var isActive: ((WKWebView) -> Bool)?
    var blockingEnabled: ((WKWebView) -> Bool)?
    private var observers: [NSObjectProtocol] = []
    var state: [String: Any] {
        var value = snapshot
        value["backgroundEnabled"] = BrowserPageScripts.backgroundEnabled
        value["ownerTabId"] = owner.flatMap { bindings[ObjectIdentifier($0)]?.tabID } as Any? ?? NSNull()
        return value
    }

    override init() {
        super.init()
        // Configure before any site starts playing. WebKit owns activation and
        // interruptions of its player; passive state reports must not take over.
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
        catch { snapshot["error"] = error.localizedDescription }
        installRemoteControls(); observeAudioLifecycle()
    }

    func register(_ view: WKWebView, tabID: String) {
        bindings[ObjectIdentifier(view)] = Binding(view, tabID)
        view.configuration.userContentController.add(self, contentWorld: .page, name: "atmaMedia")
    }

    func unregister(_ view: WKWebView) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.closeAllMediaPresentations(completionHandler: nil)
        invalidate(view)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "atmaMedia", contentWorld: .page)
        bindings.removeValue(forKey: ObjectIdentifier(view)); BrowserPageScripts.forget(view)
    }

    func invalidate(_ view: WKWebView) {
        bindings[ObjectIdentifier(view)]?.revision += 1
        guard owner === view else { return }
        generation += 1; owner = nil; snapshot = ["available": false]
        updateRemote(); didChange?()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let view = message.webView,
              bindings[ObjectIdentifier(view)]?.view === view, let page = view.url,
              BrowserMediaPolicy.matches(page: page, scheme: message.frameInfo.securityOrigin.protocol,
                                         host: message.frameInfo.securityOrigin.host, port: message.frameInfo.securityOrigin.port),
              let body = message.body as? [String: Any], body["version"] as? Int == 1,
              let value = try? BrowserMediaPolicy.snapshot(body) else { return }
        guard owner === view || (isActive?(view) == true && value["available"] as? Bool == true && value["paused"] as? Bool == false) else { return }
        accept(value, from: view)
    }

    func activate(_ view: WKWebView?, reply: @escaping (Any?, String?) -> Void) {
        guard let view, let binding = bindings[ObjectIdentifier(view)], let page = view.url else { reply(state, nil); return }
        let revision = binding.revision
        view.evaluateJavaScript("window.__atmaMediaPage?.state()") { [weak self, weak view] result, error in
            guard let self, let view, self.bindings[ObjectIdentifier(view)] === binding,
                  binding.revision == revision, view.url == page, self.isActive?(view) == true else {
                reply(nil, "Media page is no longer open."); return
            }
            guard let body = result as? [String: Any], let value = try? BrowserMediaPolicy.snapshot(body), value["available"] as? Bool == true else {
                if let error, self.owner == nil { reply(nil, error.localizedDescription) }
                else { reply(self.state, nil) }; return
            }
            self.accept(value, from: view); reply(self.state, nil)
        }
    }

    func command(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
        let command = try BrowserMediaPolicy.command(body)
        guard let view = owner else { throw BrowserFailure.invalid("Open a video and activate the player first.") }
        let version = generation
        view.callAsyncJavaScript("return await window.__atmaMediaPage.command(command);", arguments: ["command": command], in: nil, in: .page) { [weak self, weak view] result in
            guard let self, let view, self.owner === view, self.generation == version else { reply(nil, "Media page changed during the command."); return }
            switch result {
            case .success(let body):
                guard let body = body as? [String: Any], let value = try? BrowserMediaPolicy.snapshot(body) else { reply(nil, "Invalid media state."); return }
                self.accept(value, from: view); reply(self.state, nil)
            case .failure(let error): reply(nil, error.localizedDescription)
            }
        }
    }

    func setBackground(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: BrowserPageScripts.backgroundKey)
        for entry in bindings.values {
            if let view = entry.view { BrowserPageScripts.configure(view, blocking: blockingEnabled?(view) ?? true) }
        }
        didChange?()
    }

    private func observeAudioLifecycle() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, !BrowserPageScripts.backgroundEnabled, self.snapshot["pip"] as? Bool != true else { return }
                try? self.command(["type": "pause"]) { _, _ in }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let disconnected = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            guard disconnected else { return }
            Task { @MainActor in try? self?.command(["type": "pause"]) { _, _ in } }
        })
    }

    private func accept(_ value: [String: Any], from view: WKWebView) {
        if owner !== view {
            owner?.pauseAllMediaPlayback(completionHandler: nil)
            owner?.closeAllMediaPresentations(completionHandler: nil)
            generation += 1; owner = view
        }
        snapshot = value
        updateRemote(); didChange?()
    }

    private func updateRemote() {
        let center = MPRemoteCommandCenter.shared(), available = snapshot["available"] as? Bool == true
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand, center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand] { command.isEnabled = available }
        guard available else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [MPMediaItemPropertyTitle: snapshot["title"] as? String ?? "ATMA",
                                  MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot["currentTime"] as? Double ?? 0,
                                  MPNowPlayingInfoPropertyPlaybackRate: snapshot["paused"] as? Bool == true ? 0.0 : 1.0]
        if let duration = snapshot["duration"] as? Double { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func installRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, type: String, seconds: Double? = nil) {
            command.addTarget { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    var body: [String: Any] = ["type": type]
                    if let seconds { body["seconds"] = seconds }
                    if let position = event as? MPChangePlaybackPositionCommandEvent { body["seconds"] = position.positionTime }
                    if type == "toggle" { body["type"] = self.snapshot["paused"] as? Bool == true ? "play" : "pause" }
                    try? self.command(body) { _, _ in }
                }
                return .success
            }
        }
        center.skipForwardCommand.preferredIntervals = [10]; center.skipBackwardCommand.preferredIntervals = [10]
        add(center.playCommand, type: "play"); add(center.pauseCommand, type: "pause")
        add(center.togglePlayPauseCommand, type: "toggle"); add(center.skipForwardCommand, type: "skip", seconds: 10)
        add(center.skipBackwardCommand, type: "skip", seconds: -10); add(center.changePlaybackPositionCommand, type: "seek")
    }
}
