import Foundation

struct DownloadNavigationTransition {
    let tabID: String
    let url: String
    var navigationID: String?
    var transferred = false

    func isExpectedInterruption(_ error: NSError, navigationID: String?, failingURL: String?) -> Bool {
        let matches: Bool
        if let expectedID = self.navigationID { matches = navigationID == expectedID }
        else { matches = failingURL == url }
        let cancellation = error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
        let policyChange = error.domain == "WebKitErrorDomain" && error.code == 102
        return matches && (cancellation || policyChange)
    }
}

enum DownloadFilename {
    // Below the filesystem's component limit, with room reserved even before a collision occurs.
    static let maximumBytes = 240
    private static let uuidReserve = 37

    static func make(_ suggested: String, suffix: String? = nil) -> String {
        let component = suggested.replacingOccurrences(of: "\\", with: "_").components(separatedBy: "/").last ?? ""
        let clean = component.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        guard !clean.isEmpty, !clean.hasPrefix(".") else { return "download" + collisionSuffix(suffix) }
        let rawExtension = (clean as NSString).pathExtension
        let ext = prefixUTF8(rawExtension, limit: 32)
        let ending = ext.isEmpty ? "" : "." + ext
        let rawStem = rawExtension.isEmpty ? clean : (clean as NSString).deletingPathExtension
        let stem = prefixUTF8(rawStem, limit: maximumBytes - uuidReserve - ending.utf8.count)
        return (stem.isEmpty ? "download" : stem) + collisionSuffix(suffix) + ending
    }

    private static func collisionSuffix(_ suffix: String?) -> String {
        guard let suffix else { return "" }
        let safe = suffix.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return "-" + String(safe.prefix(36))
    }

    private static func prefixUTF8(_ text: String, limit: Int) -> String {
        var result = ""
        var bytes = 0
        for character in text {
            let size = String(character).utf8.count
            guard bytes + size <= limit else { break }
            result.append(character); bytes += size
        }
        return result
    }
}

enum HostBlockerPolicy {
    static func enabled(host: String?, disabledHosts: Set<String>) -> Bool {
        guard let host else { return true }
        return !disabledHosts.contains(host.lowercased())
    }
}
