import Foundation
import WebKit

extension BrowserModel {
    func shortcutProfile(for address: String) async throws -> String {
        let url = try AddressResolver.validated(address)
        guard let host = url.host?.lowercased() else { throw BrowserFailure.invalid("Missing shortcut website.") }
        func siteHost(_ value: String) -> String {
            let lower = value.lowercased()
            for prefix in ["www.", "m."] where lower.hasPrefix(prefix) { return String(lower.dropFirst(prefix.count)) }
            return lower
        }
        let matchingTabs = Set(tabs.filter {
            URL(string: $0.url)?.host.map { siteHost($0) == siteHost(host) } == true
        }.map(\.profileId))
        var cookieProfiles = Set<String>()
        // Read only stores that already exist. Never move or delete website data.
        for id in storedProfileIDs {
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                store(for: id).httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            if cookies.contains(where: { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return (host == domain || host.hasSuffix("." + domain)) && (cookie.expiresDate.map { $0 > Date() } ?? true)
            }) { cookieProfiles.insert(id) }
        }
        let current = active.profileId
        if cookieProfiles.contains(current), matchingTabs.contains(current) { return current }
        if cookieProfiles.count == 1, let id = cookieProfiles.first { return id }
        if matchingTabs.count == 1, let id = matchingTabs.first, cookieProfiles.isEmpty || cookieProfiles.contains(id) { return id }
        if cookieProfiles.contains(current) { return current }
        if cookieProfiles.count > 1 {
            throw BrowserFailure.invalid("Для сайта сохранено несколько профилей. Откройте нужный вход в обычном браузере и повторите запуск ярлыка.")
        }
        if matchingTabs.contains(current) { return current }
        return Self.actualProfile
    }
}
