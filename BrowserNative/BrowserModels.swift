import UIKit
import WebKit

struct BrowserTab: Codable {
    var id = UUID().uuidString
    var profileId: String
    var url = ""
    var title = ""
    var siteName = ""
    var iconUrl = ""
    var loading = false
    var error: String?

    mutating func finishNavigationForDownload() {
        loading = false
        error = nil
    }

    var json: [String: Any] {
        ["id": id, "profileId": profileId, "url": url, "title": title,
         "siteName": siteName, "iconUrl": iconUrl, "loading": loading, "error": error as Any? ?? NSNull()]
    }
}

struct BrowserPreferences: Codable {
    var searchEngine = "google"
    var locale = "ru-RU"
    var timezone = "Europe/Moscow"
}

struct BrowserSession: Codable {
    var tabs: [BrowserTab]
    var activeTabId: String
    var preferences = BrowserPreferences()
}

@MainActor
final class BrowserModel {
    static let actualProfile = "actual-device"
    var tabs: [BrowserTab]
    var activeTabId: String
    var preferences: BrowserPreferences
    let profiles: [[String: Any]]
    private var stores: [String: WKWebsiteDataStore] = [:]
    private let defaults: UserDefaults
    private let sessionKey = "atma.native.session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var catalogue: [[String: Any]] = []
        if let url = Bundle.main.url(forResource: "profiles", withExtension: "json", subdirectory: "BrowserUI"),
           let data = try? Data(contentsOf: url), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            catalogue = rows.filter { ($0["id"] as? String) != Self.actualProfile }
        }
        profiles = [["id": Self.actualProfile, "name": UIDevice.current.model,
                     "family": "Apple", "actualDevice": true]] + catalogue
        let first = BrowserTab(profileId: Self.actualProfile)
        if let data = defaults.data(forKey: sessionKey), let saved = try? JSONDecoder().decode(BrowserSession.self, from: data),
           !saved.tabs.isEmpty {
            let ids = Set(catalogue.compactMap { $0["id"] as? String } + [Self.actualProfile])
            let restored = saved.tabs.map { row in
                var tab = row
                if !ids.contains(tab.profileId) { tab.profileId = Self.actualProfile }
                tab.loading = false; tab.error = nil
                return tab
            }
            tabs = restored
            activeTabId = restored.contains(where: { $0.id == saved.activeTabId }) ? saved.activeTabId : restored[0].id
            preferences = saved.preferences
            if !AddressResolver.engines.contains(preferences.searchEngine) { preferences.searchEngine = "google" }
            if !["ru-RU", "en-US"].contains(preferences.locale) { preferences.locale = "ru-RU" }
            if TimeZone(identifier: preferences.timezone) == nil { preferences.timezone = "Europe/Moscow" }
        } else {
            tabs = [first]; activeTabId = first.id; preferences = BrowserPreferences()
        }
    }

    var activeIndex: Int { tabs.firstIndex { $0.id == activeTabId } ?? 0 }
    var active: BrowserTab { tabs[activeIndex] }
    func profile(_ id: String) -> [String: Any]? { profiles.first { $0["id"] as? String == id } }
    func save() {
        if let data = try? JSONEncoder().encode(BrowserSession(tabs: tabs, activeTabId: activeTabId, preferences: preferences)) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    func store(for profileId: String) -> WKWebsiteDataStore {
        if let existing = stores[profileId] { return existing }
        let key = "atma.native.store." + profileId
        let identifier = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(identifier.uuidString, forKey: key)
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        stores[profileId] = store
        return store
    }
}
