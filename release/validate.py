"""Source-level checks; a passing result does not replace an iOS runtime test."""

import argparse
import json
import plistlib
from pathlib import Path

from PIL import Image

from branding import rebrand_strings, rebrand_swift_values
from prepare import CONFIG, IOS_PATH, read_source


def validate(source):
    ios = source / IOS_PATH
    failures = []
    config_dir = ios / "App/Configuration"
    checks = {
        "Release.xcconfig": [f"MOZ_BUNDLE_DISPLAY_NAME = {CONFIG['product_name']}", f"MOZ_BUNDLE_ID = {CONFIG['bundle_id']}"],
        "Base.xcconfig": [f"DEVELOPMENT_TEAM = {CONFIG['development_team']}", "BRAVE_URL_SCHEME = atma"],
    }
    for filename, expected in checks.items():
        text = read_source(config_dir / filename)
        for value in expected:
            if value not in text:
                failures.append(f"{filename}: missing {value}")
    strings_count = 0
    swift_count = 0
    for pattern, transform in [("*.strings", rebrand_strings), ("*.swift", rebrand_swift_values)]:
        for path in ios.rglob(pattern):
            text = read_source(path)
            if transform(text) != text:
                failures.append(f"Unconverted display text: {path.relative_to(ios)}")
            if pattern == "*.strings":
                strings_count += 1
            else:
                swift_count += 1
    info_path = ios / "App/iOS/SupportingFiles/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    for key, value in info.items():
        if key.endswith("UsageDescription") and isinstance(value, str) and "Brave" in value:
            failures.append(f"System permission still mentions Brave: {key}")
    entitlements = plistlib.loads((ios / "App/iOS/Entitlements/Release.entitlements").read_bytes())
    if set(entitlements) - {"aps-environment"}:
        failures.append("The app still claims capabilities absent from its Apple provisioning")
    icon_sets = 0
    for catalog in (ios / "App/iOS/AppIcons").glob("*.icon"):
        data = json.loads((catalog / "icon.json").read_text(encoding="utf-8"))
        layers = [layer for group in data["groups"] for layer in group["layers"]]
        if len(layers) != 1 or layers[0].get("image-name") != "atma.png":
            failures.append(f"Old icon-composer layers: {catalog.name}")
        with Image.open(catalog / "Assets/atma.png") as image:
            if image.size != (1024, 1024) or image.mode != "RGB":
                failures.append(f"Invalid app icon size/opacity: {catalog.name}")
        icon_sets += 1
    result = {"display_name": CONFIG["product_name"], "bundle_id": CONFIG["bundle_id"], "localized_files_checked": strings_count, "swift_files_checked": swift_count, "composer_icons_checked": icon_sets, "failures": failures}
    if failures:
        raise ValueError(json.dumps(result, ensure_ascii=False))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.source), ensure_ascii=False))
