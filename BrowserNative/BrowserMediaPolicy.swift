import Foundation
import CoreFoundation

enum BrowserMediaPolicy {
    static let commands: Set<String> = ["play", "pause", "seek", "skip", "pip"]

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func command(_ body: [String: Any]) throws -> [String: Any] {
        guard let type = body["type"] as? String, commands.contains(type) else { throw BrowserFailure.invalid("Unsupported media command.") }
        if type == "seek" || type == "skip" {
            guard let seconds = number(body["seconds"]), abs(seconds) <= 1_000_000_000 else { throw BrowserFailure.invalid("Invalid playback position.") }
            return ["type": type, "seconds": type == "skip" ? min(600, max(-600, seconds)) : max(0, seconds)]
        }
        return ["type": type]
    }

    static func snapshot(_ body: [String: Any]) throws -> [String: Any] {
        guard body["available"] as? Bool == true else { return ["available": false] }
        guard let time = number(body["currentTime"]), time >= 0, time <= 1_000_000_000,
              let paused = body["paused"] as? Bool else { throw BrowserFailure.invalid("Invalid media state.") }
        let duration = number(body["duration"])
        guard duration == nil || (duration! >= 0 && duration! <= 1_000_000_000) else { throw BrowserFailure.invalid("Invalid media duration.") }
        return ["available": true, "title": String((body["title"] as? String ?? "").prefix(200)),
                "paused": paused, "currentTime": time, "duration": duration as Any? ?? NSNull(),
                "pip": body["pip"] as? Bool == true, "pipAvailable": body["pipAvailable"] as? Bool == true]
    }

    static func matches(page: URL, scheme: String, host: String, port: Int) -> Bool {
        guard ["http", "https"].contains(page.scheme ?? ""), page.scheme == scheme,
              page.host?.lowercased() == host.lowercased() else { return false }
        if let expected = page.port { return expected == port }
        return port == 0 || port == (scheme == "https" ? 443 : 80)
    }
}
