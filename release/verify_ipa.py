"""Read-only package checks; codesign verification is a separate macOS CI step."""
from pathlib import Path
import argparse
import json
import plistlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ALTERNATES = {f"AppIconA1{i:02d}" for i in range(1, 11)}


def validate_info(info, expected_build):
    expected = {"CFBundleIdentifier": "ru.atma.app", "CFBundleName": "ATMA",
                "CFBundleDisplayName": "ATMA", "CFBundleExecutable": "ATMA",
                "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": str(expected_build)}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f"Unexpected application {key}")
    if tuple(int(p) for p in info.get("MinimumOSVersion", "0").split(".")) < (17, 0):
        raise ValueError("Application minimum OS must be iOS 17 or later")
    if sorted(info.get("UIDeviceFamily", [])) != [1, 2]:
        raise ValueError("Application must support iPhone and iPad")
    for key in ("WKAppBoundDomains", "UIApplicationSceneManifest", "CFBundleURLTypes"):
        if key in info:
            raise ValueError(f"Legacy application key: {key}")
    if info.get("UIBackgroundModes") != ["audio"]:
        raise ValueError("Only background audio is allowed")
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icons = info.get(key, {})
        if icons.get("CFBundlePrimaryIcon", {}).get("CFBundleIconName") != "AppIcon":
            raise ValueError(f"Missing primary app icon in {key}")
        if set(icons.get("CFBundleAlternateIcons", {})) != ALTERNATES:
            raise ValueError(f"Missing alternate app icons in {key}")
    ats = info.get("NSAppTransportSecurity", {})
    if ats.get("NSAllowsArbitraryLoadsInWebContent") is not True or ats.get("NSAllowsLocalNetworking") is not True:
        raise ValueError("Browser HTTP content or loopback settings are missing")


def verify(path, expected_build, root=ROOT):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        info_names = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        expected_info = "Payload/ATMA.app/Info.plist"
        if info_names != [expected_info]:
            raise ValueError("Expected exactly Payload/ATMA.app")
        info = plistlib.loads(archive.read(expected_info))
        validate_info(info, expected_build)
        prefix = "Payload/ATMA.app/"
        for name in names:
            lower = name.lower()
            if any(token in lower for token in ("brave", "chromium", "vatma", ".appex/", ".framework/")):
                raise ValueError("Unexpected embedded browser code or extension")
            if name.startswith(prefix + "Frameworks/") and not name.endswith("/"):
                if not Path(name).name.startswith("libswift") or not name.endswith(".dylib"):
                    raise ValueError("Only the Apple Swift runtime may be embedded")
        executable = archive.read(prefix + "ATMA")
        if executable[:4] not in (bytes.fromhex("cffaedfe"), bytes.fromhex("feedfacf"), bytes.fromhex("cafebabe")):
            raise ValueError("Application executable is not a Mach-O binary")
        for name in ("Assets.car", "PrivacyInfo.xcprivacy"):
            if not archive.read(prefix + name):
                raise ValueError(f"Required application resource missing: {name}")
        count = 0
        for source, destination in ((root / "BrowserUI", "BrowserUI"),
                                    (root / "assets/certificates", "certificates")):
            for file in sorted(source.rglob("*")):
                if file.is_file():
                    target = prefix + destination + "/" + file.relative_to(source).as_posix()
                    if archive.read(target) != file.read_bytes():
                        raise ValueError("Packaged browser resource differs from verified source")
                    count += 1
        return {"status": "passed", "scope": "IPA structure, identity, icons and bundled source resources",
                "app": "ATMA.app", "build": str(expected_build), "verified_resource_count": count,
                "codesign": "verified separately by macOS CI"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--build", required=True)
    arguments = parser.parse_args()
    print(json.dumps(verify(arguments.ipa, arguments.build), indent=2))
