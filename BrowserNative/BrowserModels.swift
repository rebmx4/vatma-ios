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
    var webApp: Bool?
    var appControlsCollapsed: Bool?
    var privateBrowsing: Bool?
    var isPrivate: Bool { privateBrowsing == true }

    mutating func finishNavigationForDownload() {
        loading = false
        error = nil
    }

    var json: [String: Any] {
        ["id": id, "profileId": profileId, "url": url, "title": title,
         "siteName": siteName, "iconUrl": iconUrl, "loading": loading, "error": error as Any? ?? NSNull(), "webApp": webApp ?? false, "privateBrowsing": isPrivate]
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
    private var privateStore: WKWebsiteDataStore?
    private let defaults: UserDefaults
    private let sessionKey = "atma.native.session.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let catalogue: [[String: Any]]
        if let url = Bundle.main.url(forResource: "profiles", withExtension: "json", subdirectory: "BrowserUI"),
           let data = try? Data(contentsOf: url),
           let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            catalogue = rows.filter {
                guard let id = $0["id"] as? String, id != Self.actualProfile,
                      $0["name"] is String, $0["userAgent"] is String,
                      $0["mobile"] is Bool else { return false }
                return !id.isEmpty
            }
        } else { catalogue = [] }
        profiles = [["id": Self.actualProfile, "name": UIDevice.current.model,
                     "family": "Apple", "actualDevice": true]] + catalogue
        let first = BrowserTab(profileId: Self.actualProfile)
        if let data = defaults.data(forKey: sessionKey), let saved = try? JSONDecoder().decode(BrowserSession.self, from: data),
           !saved.tabs.isEmpty {
            let ids = Set([Self.actualProfile])
            let restored = saved.tabs.filter { !$0.isPrivate }.map { row in
                var tab = row
                if !ids.contains(tab.profileId) { tab.profileId = Self.actualProfile }
                tab.loading = false; tab.error = nil
                return tab
            }
            tabs = restored.isEmpty ? [first] : restored
            activeTabId = tabs.contains(where: { $0.id == saved.activeTabId }) ? saved.activeTabId : tabs[0].id
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
        let ordinary = tabs.filter { !$0.isPrivate }
        let retained = ordinary.isEmpty ? [BrowserTab(profileId: Self.actualProfile)] : ordinary
        let retainedActive = retained.contains(where: { $0.id == activeTabId }) ? activeTabId : retained[0].id
        if let data = try? JSONEncoder().encode(BrowserSession(tabs: retained, activeTabId: retainedActive, preferences: preferences)) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    func store(for tab: BrowserTab) -> WKWebsiteDataStore {
        guard tab.isPrivate else { return store(for: tab.profileId) }
        if let privateStore { return privateStore }
        let created = WKWebsiteDataStore.nonPersistent()
        privateStore = created
        return created
    }

    func discardUnusedPrivateSession() {
        if !tabs.contains(where: { $0.isPrivate }) { privateStore = nil }
    }

    func store(for _: String) -> WKWebsiteDataStore {
        // All tabs and saved sites share the actual device website session.
        let profileId = Self.actualProfile
        if let existing = stores[profileId] { return existing }
        let key = "atma.native.store." + profileId
        let identifier = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(identifier.uuidString, forKey: key)
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        stores[profileId] = store
        return store
    }
}
