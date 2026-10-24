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
        if ["home", "panel", "tabs/new", "tabs/select", "tabs/close", "profile"].contains(action), mode == "browse", panel == nil {
            captureCurrentPreview { [weak self] in
                guard let self else { reply(nil, "Browser closed."); return }
                do { try self.perform(action, body: body, reply: reply) }
                catch { reply(nil, error.localizedDescription) }
            }
            return
        }
        try perform(action, body: body, reply: reply)
    }

    private func perform(_ action: String, body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
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
        case "shortcut-profile":
            let address = try string("url", body)
            _ = try AddressResolver.validated(address)
            Task { @MainActor [weak self] in
                guard let self else { reply(nil, "Browser closed."); return }
                do { reply(["profileId": try await self.model.shortcutProfile(for: address)], nil) }
                catch { reply(nil, error.localizedDescription) }
            }
            return
        case "open":
            guard body["profileId"] == nil || body["profileId"] is String,
                  body["webApp"] == nil || body["webApp"] is Bool else { throw BrowserFailure.invalid("Invalid site presentation or profile.") }
            try open(try string("url", body), profileID: body["profileId"] as? String, webApp: body["webApp"] as? Bool)
        case "chrome":
            guard mode == "browse", let collapsed = body["collapsed"] as? Bool else { throw BrowserFailure.invalid("Open a site and supply collapsed:true or false.") }
            view.endEditing(true)
            if !webApp { deviceRowCollapsed = collapsed }
            changed()
        case "home": view.endEditing(true); mode = "home"; panel = nil; changed()
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
        case "site-resource":
            let address = try string("url", body), kind = try string("kind", body)
            _ = try AddressResolver.validated(address)
            Task {
                do { reply(try await BrowserSiteResource.load(address, kind: kind), nil) }
                catch { reply(nil, error.localizedDescription) }
            }
            return
        case "current-site":
            let tab = model.active
            var result: [String: Any] = ["url": tab.url, "profileId": tab.profileId, "title": tab.title,
                                         "siteName": tab.siteName, "iconUrl": tab.iconUrl]
            guard let page = currentRenderer else { reply(result, nil); return }
            BrowserSiteResource.metadata(in: page) { metadata in
                result.merge(metadata) { _, fresh in fresh }
                reply(result, nil)
            }
            return
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
        // The UI may request previews before its panel RPC arrives. Join the
        // current visible capture so the first overview receives the new image.
        captureCurrentPreview { [weak self] in
            guard let self else { reply(nil, "Browser closed."); return }
            let result = self.model.tabs.reduce(into: [String: String]()) { result, tab in
                guard let preview = self.tabPreviews[tab.id], preview.url.absoluteString == tab.url,
                      let renderer = self.renderers[tab.id], preview.renderer == ObjectIdentifier(renderer) else { return }
                result[tab.id] = preview.source
            }
            reply(["previews": result, "errors": [String: String]()], nil)
        }
    }
}
