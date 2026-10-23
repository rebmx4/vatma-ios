import UIKit

enum BrowserAppearancePolicy {
    static let alternateIDs = (1...10).map { String(format: "a1-%02d", $0) }
    static let themes = ["auto", "light", "dark"]

    static func assetName(for icon: String) throws -> String? {
        if icon == "default" { return nil }
        guard let index = alternateIDs.firstIndex(of: icon) else {
            throw BrowserFailure.invalid("Unknown application icon.")
        }
        return String(format: "AppIconA1%02d", index + 1)
    }
}

extension BrowserController {
    var nativeStatusBarStyle: UIStatusBarStyle {
        switch nativeTheme {
        case "dark": return .lightContent
        case "light": return .darkContent
        default: return .default
        }
    }

    func applyNativeAppearance(_ body: [String: Any]) throws -> [String: String] {
        guard let theme = body["theme"] as? String, BrowserAppearancePolicy.themes.contains(theme) else {
            throw BrowserFailure.invalid("Theme must be auto, light or dark.")
        }
        nativeTheme = theme
        overrideUserInterfaceStyle = theme == "dark" ? .dark : theme == "light" ? .light : .unspecified
        let background = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 16.0 / 255.0, green: 16.0 / 255.0, blue: 16.0 / 255.0, alpha: 1)
                : UIColor(red: 241.0 / 255.0, green: 240.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)
        }
        view.backgroundColor = background
        ui.backgroundColor = background
        ui.scrollView.backgroundColor = background
        view.window?.backgroundColor = background
        setNeedsStatusBarAppearanceUpdate()
        return ["theme": theme]
    }

    func setApplicationIcon(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
        guard let icon = body["icon"] as? String else { throw BrowserFailure.invalid("Missing application icon.") }
        let assetName = try BrowserAppearancePolicy.assetName(for: icon)
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else {
            throw BrowserFailure.invalid("This device does not support alternate application icons.")
        }
        application.setAlternateIconName(assetName) { error in
            DispatchQueue.main.async {
                if let error { reply(nil, error.localizedDescription) }
                else { reply(["icon": icon], nil) }
            }
        }
    }
}
