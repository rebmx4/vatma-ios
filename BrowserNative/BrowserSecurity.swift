import Foundation
import CryptoKit

enum BrowserFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum AddressResolver {
    static let engines = ["google", "yandex", "bing", "duckduckgo"]

    static func resolve(_ input: String, engine: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw BrowserFailure.invalid("Enter an address or search query.")
        }
        if let colon = text.firstIndex(of: ":"), !text[..<colon].contains(".") {
            let scheme = String(text[..<colon]).lowercased()
            guard scheme == "https" || scheme == "http" else {
                throw BrowserFailure.invalid("Only HTTP and HTTPS addresses are supported.")
            }
            return try validated(text)
        }
        if !text.contains(where: { $0.isWhitespace }), text.contains(".") || text.hasPrefix("localhost") {
            return try validated("https://" + text)
        }
        let endpoint: String
        let key: String
        switch engine {
        case "yandex": endpoint = "https://yandex.ru/search/"; key = "text"
        case "bing": endpoint = "https://www.bing.com/search"; key = "q"
        case "duckduckgo": endpoint = "https://duckduckgo.com/"; key = "q"
        default: endpoint = "https://www.google.com/search"; key = "q"
        }
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: key, value: text)]
        guard let url = components.url else { throw BrowserFailure.invalid("Invalid search query.") }
        return url
    }

    static func validated(_ text: String) throws -> URL {
        guard let components = URLComponents(string: text),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else {
            throw BrowserFailure.invalid("Invalid HTTP(S) address or embedded credentials.")
        }
        return url
    }
}

enum CookieIdentity {
    static func id(profile: String, cookie: HTTPCookie) -> String {
        id(profile: profile, domain: cookie.domain, path: cookie.path, name: cookie.name)
    }

    static func id(profile: String, domain: String, path: String, name: String) -> String {
        let input = [profile, domain, path, name].map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func select(_ cookies: [HTTPCookie], profile: String, ids: Set<String>) -> [HTTPCookie] {
        cookies.filter { ids.contains(id(profile: profile, cookie: $0)) }
    }
}

enum UIResourcePath {
    static func relative(_ target: String) -> String? {
        let raw = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard raw.hasPrefix("/"), !raw.hasPrefix("//"), !raw.contains("%"),
              !raw.contains("\\"), !raw.contains("\0") else { return nil }
        let parts = raw.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(".."), !parts.contains(".") else { return nil }
        return raw == "/" ? "index.html" : String(raw.dropFirst())
    }
}
