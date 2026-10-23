import Foundation
import WebKit

@MainActor
enum CookieService {
    static func list(store: WKWebsiteDataStore, profile: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        store.httpCookieStore.getAllCookies { cookies in
            let id = profile["id"] as? String ?? ""
            let rows: [[String: Any]] = cookies.sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }.map {
                ["id": CookieIdentity.id(profile: id, cookie: $0), "domain": $0.domain,
                 "path": $0.path, "name": $0.name, "value": $0.value,
                 "secure": $0.isSecure, "httpOnly": $0.isHTTPOnly, "session": $0.isSessionOnly,
                 "expires": $0.expiresDate?.timeIntervalSince1970 ?? 0]
            }
            completion(["cookies": rows, "profile": ["id": id, "name": profile["name"] as? String ?? id]])
        }
    }

    static func delete(store: WKWebsiteDataStore, profile: [String: Any], ids: Set<String>, all: Bool,
                       completion: @escaping ([String: Any]) -> Void) {
        let profileId = profile["id"] as? String ?? ""
        store.httpCookieStore.getAllCookies { cookies in
            let selected = all ? cookies : CookieIdentity.select(cookies, profile: profileId, ids: ids)
            let group = DispatchGroup()
            for cookie in selected {
                group.enter()
                store.httpCookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) { list(store: store, profile: profile, completion: completion) }
        }
    }
}
