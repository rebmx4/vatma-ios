import Foundation
import WebKit

@MainActor
enum BrowserUnread {
    private static let source: String? = {
        guard let url = Bundle.main.url(forResource: "site-unread", withExtension: "js", subdirectory: "BrowserUI/assets") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    static var resourceAvailable: Bool { source != nil }

    static func provider(for url: URL?) -> String? {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        if ["vk.com", "vk.ru"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return "vk" }
        if host == "avito.ru" || host.hasSuffix(".avito.ru") { return "avito" }
        return nil
    }

    static func counts(in browser: BrowserController, providers: Set<String>) async -> [String: Int] {
        guard let source, !providers.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        var inspected: [String: Int] = [:]
        for tab in browser.model.tabs.reversed() where !tab.isPrivate {
            guard let view = browser.renderers[tab.id], !view.isLoading, let page = view.url,
                  let provider = provider(for: page), providers.contains(provider),
                  inspected[provider, default: 0] < 4 else { continue }
            inspected[provider, default: 0] += 1
            guard let raw = try? await view.evaluateJavaScript(source, in: nil, contentWorld: .defaultClient),
                  browser.renderers[tab.id] === view, view.url == page,
                  browser.model.tabs.first(where: { $0.id == tab.id })?.isPrivate == false,
                  let value = raw as? [String: Any], value["provider"] as? String == provider,
                  let count = value["count"] as? Int, (0...999).contains(count) else { continue }
            result[provider] = max(result[provider] ?? 0, count)
        }
        return result
    }
}
