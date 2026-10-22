"""Configure a standalone ATMA app using the existing Apple app identity."""

import plistlib
import re

from branding import rebrand_display_text


MAIN_TARGET = "F84B21BD1A090F8100AAB793"


def configure_app_target(ios, config, update):
    path = ios / "App/Client.xcodeproj/project.pbxproj"
    text = path.read_bytes().decode("utf-8")
    pattern = re.compile(rf"^\t\t{MAIN_TARGET} /\* Client \*/ = \{{.*?^\t\t\}};", re.MULTILINE | re.DOTALL)
    match = pattern.search(text)
    if not match:
        raise ValueError("The pinned Client target is missing")
    block = match.group(0)
    # This first TestFlight build contains the browser app. Service extensions
    # need their own registered Apple identifiers and provisioning profiles.
    block = re.sub(r"^.*F84B22531A0920C600AAB793 /\* Embed App Extensions \*/.*\r?\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"\bdependencies = \(.*?\);", "dependencies = (\n\t\t\t);", block, flags=re.DOTALL)
    update(path, text[:match.start()] + block + text[match.end():], "app_target")

    for filename in ("Release.entitlements", "Release (AppStore).entitlements"):
        path = ios / "App/iOS/Entitlements" / filename
        original = plistlib.loads(path.read_bytes())
        # The existing app has Push Notifications. Do not claim the original
        # vendor's VPN, default-browser or app-group permissions.
        selected = {key: value for key, value in original.items() if key == "aps-environment"}
        update(path, plistlib.dumps(selected, sort_keys=False), "app_entitlements")

    path = ios / "App/iOS/SupportingFiles/Info.plist"
    info = plistlib.loads(path.read_bytes())
    info["CFBundleName"] = config["product_name"]
    for item in info.get("CFBundleURLTypes", []):
        item["CFBundleURLName"] = config["bundle_id"]
    update(path, plistlib.dumps(info, sort_keys=False), "bundle_metadata")

    user_agent = ios / "Sources/UserAgent"
    for path in user_agent.glob("*.swift"):
        text = path.read_bytes().decode("utf-8")
        text = re.sub(r'"(?:\\.|[^"\\])*"', lambda match: rebrand_display_text(match.group(0)), text)
        update(path, text, "user_agent_identity")

    labels = {
        "Sources/BraveVPN/BraveVPN.swift": {'"Brave VPN"': '"ATMA VPN"'},
        "Sources/BraveTalk/BraveTalkConferencingOptions.swift": {'"Brave Talk"': '"ATMA Talk"'},
        "Sources/Brave/Frontend/Settings/SettingsViewController.swift": {
            '"Brave Talk Logs"': '"ATMA Talk Logs"',
            '"View Brave News Debug Menu"': '"View ATMA News Debug Menu"',
            '"View Brave Search Debug Menu"': '"View ATMA Search Debug Menu"',
            '"View Brave Wallet Debug Menu"': '"View ATMA Wallet Debug Menu"',
        },
        "Sources/Brave/Frontend/Browser/Favorites/Data/FavoritesPreloadedData.swift": {"What's new in Brave": "What's new in ATMA"},
        "Sources/Brave/Utility/AppDebugComposer.swift": {r"Brave \(appVersion)": r"ATMA \(appVersion)"},
        "Sources/BraveStore/Subscription/SDK/BraveStoreSDK.swift": {'"Brave VPN"': '"ATMA VPN"', '"Brave Leo"': '"ATMA Leo"', '"Brave Origin"': '"ATMA Origin"'},
        "Sources/Origin/OriginStrings.swift": {'"Brave Origin"': '"ATMA Origin"'},
        "Sources/Brave/Frontend/Browser/UserScripts/Debug/UserScriptsDebugView.swift": {'"Brave Translate"': '"ATMA Translate"'},
        "Sources/Brave/Frontend/Settings/Debug/BraveCoreDebugSwitchesView.swift": {'"Brave Services Environment"': '"ATMA Services Environment"'},
        "Sources/Brave/Frontend/Settings/Debug/BraveWallet/BraveWalletDebugMenu.swift": {'"Brave Wallet Debug"': '"ATMA Wallet Debug"'},
        "Sources/BraveNews/Settings/BraveNewsDebugSettingsView.swift": {'"Brave News QA Settings"': '"ATMA News QA Settings"'},
        "Sources/Brave/Frontend/Settings/Debug/RewardsInternals/QA/RewardsDebugSettingsViewController.swift": {
            "Changing the environment automatically resets Brave Rewards.": "Changing the environment automatically resets ATMA Rewards.",
            "Brave must be restarted to ensure expected Rewards behavior": "ATMA must be restarted to ensure expected Rewards behavior",
        },
    }
    for relative, replacements in labels.items():
        path = ios / relative
        text = path.read_bytes().decode("utf-8")
        for before, after in replacements.items():
            if before not in text and after not in text:
                raise ValueError(f"Expected display label is missing from {relative}")
            text = text.replace(before, after)
        update(path, text, "other_display_labels")

    path = ios / "Sources/Brave/Frontend/Browser/Search/SearchEngines.swift"
    text = path.read_bytes().decode("utf-8")
    before = "let engines = isOnboarding ? se.onboardingEngines : se.engines"
    after = 'let engines = (isOnboarding ? se.onboardingEngines : se.engines).filter { !($0.customId ?? $0.id.rawValue).lowercased().hasPrefix("brave") }'
    if before not in text and after not in text:
        raise ValueError("The search-provider selection has changed")
    update(path, text.replace(before, after), "search_providers")

    path = ios / "Sources/Brave/Frontend/Browser/Search/SearchSuggestionDataSource.swift"
    text = path.read_bytes().decode("utf-8")
    replacement = "  var braveSearchPromotionAvailable: Bool { false }"
    if replacement not in text:
        pattern = re.compile(r"^  var braveSearchPromotionAvailable: Bool \{.*?^  \}", re.MULTILINE | re.DOTALL)
        text, count = pattern.subn(replacement, text)
        if count != 1:
            raise ValueError("The search promotion availability check has changed")
    update(path, text, "search_promotions")
