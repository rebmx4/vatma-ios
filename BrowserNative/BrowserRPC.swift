import UIKit
import WebKit

extension BrowserController: WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard message.webView === ui, message.frameInfo.isMainFrame,
              origin.protocol == "http", origin.host == "127.0.0.1", origin.port == Int(server.port),
              server.port != 0, let request = message.body as? [String: Any],
              let action = request["action"] as? String else {
            replyHandler(nil, "ATMA bridge is restricted to its bundled main-frame UI."); return
        }
        let body = request["body"] as? [String: Any] ?? [:]
        do { try dispatch(action, body: body, reply: replyHandler) }
        catch { replyHandler(nil, error.localizedDescription) }
    }

    private func dispatch(_ action: String, body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
        switch action {
        case "appearance": reply(try applyNativeAppearance(body), nil); return
        case "app-icon": try setApplicationIcon(body, reply: reply); return
        case "state": reply(state(), nil); return
        case "media/state": reply(media.state, nil); return
        case "media/activate": media.activate(currentRenderer, reply: reply); return
        case "media/command": try media.command(body, reply: reply); return
        case "media/background":
            guard let enabled = body["enabled"] as? Bool else { throw BrowserFailure.invalid("Supply enabled:true or false.") }
            media.setBackground(enabled); reply(media.state, nil); return
        case "open": try open(try string("url", body))
        case "home": mode = "home"; panel = nil; changed()
        case "panel":
            guard body["panel"] == nil || body["panel"] is NSNull || body["panel"] is String else { throw BrowserFailure.invalid("Invalid panel.") }
            panel = body["panel"] as? String; changed()
        case "tabs/new": newTab()
        case "tabs/select": try selectTab(try string("tabId", body))
        case "tabs/close": try closeTab(try string("tabId", body))
        case "profile": try changeProfile(try string("profileId", body))
        case "preferences": try preferences(body)
        case "back": currentRenderer?.goBack()
        case "forward": currentRenderer?.goForward()
        case "refresh":
            if let currentRenderer { currentRenderer.reload() }
            else if !model.active.url.isEmpty { try open(model.active.url) }
        case "current-site":
            reply(["url": model.active.url, "title": model.active.title,
                   "siteName": model.active.siteName, "iconUrl": model.active.iconUrl], nil); return
        case "tab-previews": previews(reply); return
        case "cookies", "cookies/delete":
            let profileId = model.active.profileId
            let profile = model.profile(profileId) ?? ["id": profileId, "name": profileId]
            let store = model.store(for: profileId)
            if action == "cookies" { CookieService.list(store: store, profile: profile) { reply($0, nil) } }
            else {
                let all = body["all"] as? Bool == true
                guard all || body["ids"] is [String] else { throw BrowserFailure.invalid("Supply cookie IDs or all:true.") }
                CookieService.delete(store: store, profile: profile, ids: Set(body["ids"] as? [String] ?? []), all: all) { reply($0, nil) }
            }
            return
        case "files": reply(try downloads.list(), nil); return
        case "file": reply(try downloads.preview(id: string("fileId", body)), nil); return
        case "blocker/set":
            guard let host = URL(string: model.active.url)?.host, let enabled = body["enabled"] as? Bool else {
                throw BrowserFailure.invalid("Open a website and supply enabled:true or false.")
            }
            blocker.setEnabled(enabled, host: host)
            currentRenderer?.reload(); changed()
        case "probe": throw BrowserFailure.invalid("A trustworthy fingerprint probe is not implemented on iOS.")
        case "snapshot": throw BrowserFailure.invalid("Use tab-previews for bounded native tab snapshots.")
        default: throw BrowserFailure.invalid("Unsupported native action: " + action)
        }
        reply(state(), nil)
    }

    private func string(_ key: String, _ body: [String: Any]) throws -> String {
        guard let value = body[key] as? String, !value.isEmpty else { throw BrowserFailure.invalid("Missing " + key + ".") }
        return value
    }

    private func preferences(_ body: [String: Any]) throws {
        var preferences = model.preferences
        if let engine = body["searchEngine"] as? String {
            guard AddressResolver.engines.contains(engine) else { throw BrowserFailure.invalid("Unknown search engine.") }
            preferences.searchEngine = engine
        }
        if let locale = body["locale"] as? String {
            guard ["ru-RU", "en-US"].contains(locale) else { throw BrowserFailure.invalid("Only Russian and English are supported.") }
            preferences.locale = locale
        }
        if let timezone = body["timezone"] as? String {
            guard TimeZone(identifier: timezone) != nil else { throw BrowserFailure.invalid("Invalid time zone.") }
            preferences.timezone = timezone
        }
        model.preferences = preferences; changed()
    }

    private func previews(_ reply: @escaping (Any?, String?) -> Void) {
        guard !snapshotBusy else { reply(nil, "A tab snapshot request is already running."); return }
        let candidates = model.tabs.compactMap { tab -> (String, WKWebView)? in
            guard let view = renderers[tab.id], view.bounds.width > 0, view.bounds.height > 0 else { return nil }
            return (tab.id, view)
        }
        guard !candidates.isEmpty else { reply(nil, "No rendered tabs are available for a native snapshot."); return }
        snapshotBusy = true
        var result: [String: String] = [:]
        var failures: [String: String] = [:]
        let group = DispatchGroup()
        for (id, renderer) in candidates.prefix(12) {
            group.enter()
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: 280)
            renderer.takeSnapshot(with: config) { image, error in
                defer { group.leave() }
                if let image {
                    let width = min(280, image.size.width)
                    let size = CGSize(width: width, height: max(1, image.size.height * width / max(1, image.size.width)))
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let bounded = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    guard let data = bounded.jpegData(compressionQuality: 0.65) else {
                        failures[id] = "The snapshot could not be encoded."; return
                    }
                    result[id] = "data:image/jpeg;base64," + data.base64EncodedString()
                } else { failures[id] = error?.localizedDescription ?? "This tab could not be captured by WebKit." }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.snapshotBusy = false
            reply(["previews": result, "errors": failures], nil)
        }
    }
}
