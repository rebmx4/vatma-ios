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
        if LocalUIServer.diagnosticsEnabled, ["home", "panel", "tabs/new", "tabs/select", "tabs/close", "open"].contains(action) {
            lastUIAction = action == "panel" ? "panel:\(body["panel"] as? String ?? "closed")" : action
        }
        do { try dispatch(action, body: body, reply: replyHandler) }
        catch { replyHandler(nil, error.localizedDescription) }
    }

    private func dispatch(_ action: String, body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
        if ["home", "panel", "tabs/new", "tabs/select", "tabs/close", "tabs/close-many", "tabs/duplicate", "private-device"].contains(action),
           mode == "browse", panel == nil {
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
        case "vault/biometry/status": reply(VaultBiometrics.status(), nil); return
        case "vault/biometry/enroll": try VaultBiometrics.enroll(body, reply: reply); return
        case "vault/biometry/unlock": try VaultBiometrics.unlock(body, reply: reply); return
        case "appearance": reply(try applyNativeAppearance(body), nil); return
        case "app-icon": try setApplicationIcon(body, reply: reply); return
        case "state": reply(state(), nil); return
        case "address/editing":
            guard let editing = body["editing"] as? Bool else { throw BrowserFailure.invalid("Invalid address editing state.") }
            let id = try string("tabID", body)
            if editing, id == model.activeTabId { addressEditingTabID = id }
            else if !editing, id == addressEditingTabID { addressEditingTabID = nil }
            view.setNeedsLayout()
            reply(true, nil)
            return
        case "ui/ready":
            let attemptID = try string("attemptID", body)
            guard let stylesReady = body["stylesReady"] as? Bool else { throw BrowserFailure.invalid("Invalid UI readiness.") }
            reply(true, nil)
            uiStartup.receiveReady(attemptID: attemptID, stylesReady: stylesReady)
            return
        case "message-badges":
            guard let requested = body["providers"] as? [String], requested.count <= 2,
                  requested.allSatisfy({ ["vk", "avito"].contains($0) }) else {
                throw BrowserFailure.invalid("Unsupported message badge request.")
            }
            Task { [weak self] in
                guard let self else { reply(nil, "Browser closed."); return }
                let counts = await BrowserUnread.counts(in: self, providers: Set(requested))
                reply(["counts": counts], nil)
            }
            return
        case "media/state": reply(media.state, nil); return
        case "media/activate": media.activate(currentRenderer, reply: reply); return
        case "media/command": try media.command(body, reply: reply); return
        case "media/background":
            guard let enabled = body["enabled"] as? Bool else { throw BrowserFailure.invalid("Supply enabled:true or false.") }
            media.setBackground(enabled); reply(media.state, nil); return
        case "open":
            guard body["profileId"] == nil,
                  body["webApp"] == nil || body["webApp"] is Bool else { throw BrowserFailure.invalid("Device switching is not supported.") }
            guard body["privateDesktop"] == nil || body["privateDesktop"] is Bool else {
                throw BrowserFailure.invalid("Invalid private desktop scope.")
            }
            try open(try string("url", body), webApp: body["webApp"] as? Bool,
                     privateDesktop: body["privateDesktop"] as? Bool == true)
        case "shortcut/open":
            try openShortcut(try string("url", body), shortcutId: try string("shortcutId", body))
        case "home": returnHome()
        case "translation/language":
            let language = try string("language", body)
            guard BrowserPageTranslation.interfaceLanguages.contains(language) else {
                throw BrowserFailure.invalid("Unsupported interface language.")
            }
            pageTranslation.setTarget(language)
        case "translation/toggle":
            guard BrowserPageTranslation.available, mode == "browse" else {
                throw BrowserFailure.invalid("Перевод страницы сейчас недоступен.")
            }
            panel = nil
            pageTranslation.toggle()
            changed()
        case "panel":
            guard body["panel"] == nil || body["panel"] is NSNull || body["panel"] is String else { throw BrowserFailure.invalid("Invalid panel.") }
            panel = body["panel"] as? String; changed()
        case "tabs/new":
            guard body["privateBrowsing"] == nil || body["privateBrowsing"] is Bool else { throw BrowserFailure.invalid("Invalid private mode.") }
            let privateBrowsing = body["privateBrowsing"] as? Bool == true
            let sessionID: UUID?
            if body["sourceTabId"] != nil {
                let id = try string("sourceTabId", body)
                guard privateBrowsing, let source = model.tabs.first(where: { $0.id == id && $0.isPrivate }) else {
                    throw BrowserFailure.invalid("Unknown private tab.")
                }
                sessionID = model.privateSessionID(for: source)
            } else { sessionID = nil }
            newTab(privateBrowsing: privateBrowsing, sessionID: sessionID)
        case "tabs/private/close": closePrivateTabs()
        case "private-device":
            guard body["separateSession"] == nil || body["separateSession"] is Bool else {
                throw BrowserFailure.invalid("Invalid private session choice.")
            }
            try changePrivateDevice(try string("profileId", body), separateSession: body["separateSession"] as? Bool == true)
        case "tabs/select": try selectTab(try string("tabId", body))
        case "tabs/close": try closeTab(try string("tabId", body))
        case "tabs/close-many":
            guard let ids = body["tabIds"] as? [String], !ids.isEmpty,
                  Set(ids).isSubset(of: Set(model.tabs.map(\.id))) else {
                throw BrowserFailure.invalid("Unknown tabs.")
            }
            try closeTabs(Set(ids))
        case "tabs/duplicate": try duplicateOverviewTab(try string("tabId", body))
        case "tabs/history":
            reply(["entries": overviewHistory().map(\.json)], nil)
            return
        case "tabs/history/open":
            try openOverviewHistory(tabID: try string("tabId", body), url: try string("url", body))
        case "preferences": try preferences(body)
        case "back": currentRenderer?.goBack()
        case "forward": currentRenderer?.goForward()
        case "share-page":
            guard mode == "browse", presentedViewController == nil,
                  let page = currentRenderer, let url = page.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw BrowserFailure.invalid("Не удалось поделиться ссылкой")
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = ui
                popover.sourceRect = CGRect(x: ui.bounds.midX, y: ui.bounds.maxY - 1, width: 1, height: 1)
            }
            present(activity, animated: true)
            reply(true, nil)
            return
        case "refresh":
            if let currentRenderer { currentRenderer.reload() }
            else if !model.active.url.isEmpty { try selectTab(model.activeTabId) }
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
            guard mode == "browse", !tab.loading, let page = currentRenderer else {
                throw BrowserFailure.invalid("Дождитесь загрузки сайта перед добавлением на рабочий стол.")
            }
            BrowserSiteResource.metadata(in: page) { [weak self, weak page] metadata in
                guard let self, let page, self.currentRenderer === page, self.mode == "browse",
                      self.model.activeTabId == tab.id, !self.model.active.loading,
                      self.model.active.url == tab.url, metadata["url"] as? String == tab.url else {
                    reply(nil, "Страница изменилась. Дождитесь загрузки и повторите добавление."); return
                }
                var result = metadata
                result["url"] = tab.url; result["profileId"] = tab.profileId
                reply(result, nil)
            }
            return
        case "tab-previews": previews(reply); return
        case "cookies", "cookies/delete":
            let profileId = model.active.profileId
            let profile = model.profile(profileId) ?? ["id": profileId, "name": profileId]
            let store = model.store(for: model.active)
            if action == "cookies" { CookieService.list(store: store, profile: profile) { reply($0, nil) } }
            else {
                let all = body["all"] as? Bool == true
                guard all || body["ids"] is [String] else { throw BrowserFailure.invalid("Supply cookie IDs or all:true.") }
                CookieService.delete(store: store, profile: profile, ids: Set(body["ids"] as? [String] ?? []), all: all) { reply($0, nil) }
            }
            return
        case "site-data", "site-data/delete":
            let store = model.store(for: model.active)
            if action == "site-data" { WebsiteDataService.list(store: store) { reply($0, nil) } }
            else {
                let all = body["all"] as? Bool == true
                let names = body["names"] as? [String] ?? []
                guard all || (body["names"] is [String] && names.count <= 500 && names.allSatisfy({ !$0.isEmpty && $0.count <= 255 })) else {
                    throw BrowserFailure.invalid("Supply website names or all:true.")
                }
                WebsiteDataService.delete(store: store, names: Set(names), all: all) { reply($0, nil) }
            }
            return
        case "files": reply(try downloads.list(), nil); return
        case "file": reply(try downloads.preview(id: string("fileId", body)), nil); return
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
                guard !tab.isPrivate, !tab.isPrivateDesktop,
                      let preview = self.tabPreviews[tab.id], preview.url.absoluteString == tab.url,
                      let renderer = self.renderers[tab.id], preview.renderer == ObjectIdentifier(renderer) else { return }
                result[tab.id] = preview.source
            }
            reply(["previews": result, "errors": [String: String]()], nil)
        }
    }
}
