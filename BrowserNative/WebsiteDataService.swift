import Foundation
import WebKit

@MainActor
enum WebsiteDataService {
    private static let protectedNames: Set<String> = ["127.0.0.1", "localhost"]

    static func list(store: WKWebsiteDataStore, completion: @escaping ([String: Any]) -> Void) {
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let rows: [[String: Any]] = records
                .filter { !protectedNames.contains($0.displayName.lowercased()) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                .map { ["name": $0.displayName, "types": Array($0.dataTypes).sorted()] }
            completion(["records": rows])
        }
    }

    static func delete(store: WKWebsiteDataStore, names: Set<String>, all: Bool,
                       completion: @escaping ([String: Any]) -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let selected = records.filter {
                !protectedNames.contains($0.displayName.lowercased()) && (all || names.contains($0.displayName))
            }
            store.removeData(ofTypes: types, for: selected) {
                list(store: store, completion: completion)
            }
        }
    }
}
