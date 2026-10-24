"""Dependency-free checks of explicit standalone inputs, not an iOS runtime test."""
from pathlib import Path
import argparse
import ast
import hashlib
import json
import plistlib
import re
import ssl
import struct
from app_identity import BUNDLE_ID, TEAM_ID
from github_ci import validate_workflow as validate_github_workflow

ROOT = Path(__file__).resolve().parents[1]
APP_PATHS = {"BrowserNative", "BrowserUI", "assets/certificates", "BrowserResources"}
ROOT_PEM_SHA256 = "ea5cef7aa71bb049a2fb599c8776dfa682a6ed969acf309291601f6fc066df9d"
ROOT_DER_SHA256 = "d26d2d0231b7c39f92cc738512ba54103519e4405d68b5bd703e9788ca8ecf31"
ALTERNATES = {f"AppIconA1{i:02d}" for i in range(1, 11)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def validate_project(project):
    require(project["name"] == "ATMA", "Unexpected project name")
    require(project["options"]["deploymentTarget"]["iOS"] == "17.0", "Minimum iOS must be 17.0")
    base = project["settings"]["base"]
    require(base["TARGETED_DEVICE_FAMILY"] == "1,2", "Missing iPad support")
    require(base["DEVELOPMENT_TEAM"] == TEAM_ID, "Wrong Apple team")
    require(not any(project.get(key) for key in ("packages", "include", "projectReferences", "targetTemplates")),
            "External project/package inputs are not allowed")
    require(set(project["targets"]) == {"ATMA", "BrowserNativeTests", "BrowserNativeUITests"}, "Unexpected target")
    app = project["targets"]["ATMA"]
    require(app["type"] == "application" and app["platform"] == "iOS", "Expected native iOS app")
    require({row["path"] for row in app["sources"]} == APP_PATHS, "Unexpected active application input")
    require(not any(app.get(k) for k in ("dependencies", "preBuildScripts", "postBuildScripts", "configFiles")),
            "Application cannot add hidden code dependencies or scripts")
    resources = next(row for row in app["sources"] if row["path"] == "BrowserResources")
    require(set(resources.get("excludes", [])) == {"Info.plist", "icon-manifest.json"}, "Resource metadata must not be copied into app")
    for folder in ("BrowserUI", "assets/certificates"):
        row = next(row for row in app["sources"] if row["path"] == folder)
        require(row.get("type") == "folder" and row.get("buildPhase") == "resources", "Bundle folder must retain its name")
    settings = app["settings"]["base"]
    require(settings["PRODUCT_BUNDLE_IDENTIFIER"] == BUNDLE_ID and settings["PRODUCT_NAME"] == "ATMA", "Wrong application identity")
    require(settings["INFOPLIST_FILE"] == "BrowserResources/Info.plist", "Wrong application plist")
    require(not settings.get("CODE_SIGN_ENTITLEMENTS"), "Unregistered legacy entitlements are not allowed")
    require(set(settings["ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES"].split()) == ALTERNATES, "Alternate icon sets missing")
    for target, kind in (("BrowserNativeTests", "bundle.unit-test"), ("BrowserNativeUITests", "bundle.ui-testing")):
        row = project["targets"][target]
        require(row["type"] == kind and row["sources"] == [target], "Wrong test target")
        require(row["dependencies"] == [{"target": "ATMA"}], "Wrong test application dependency")


def validate_workflows(config):
    workflows = config["workflows"]
    require(set(workflows) == {"atma-testflight", "atma-device-testflight"}, "Unexpected CI workflow")
    for name, workflow in workflows.items():
        require("triggering" not in workflow, "Automatic CI triggers are not allowed")
        require(workflow["instance_type"] == "mac_mini_m2" and workflow["max_build_duration"] == 30, "Expected bounded M2 worker")
        require(workflow["environment"]["xcode"] == "26.4", "Expected verified Xcode 26.4 image")
        require(all(path.startswith("$CM_BUILD_DIR/.cache/") for path in workflow["cache"]["cache_paths"]), "Unexpected cache path")
        scripts = [row["script"] for row in workflow["scripts"]]
        if name == "atma-testflight":
            require(scripts == ["bash release/ci.sh prepare", "bash release/ci.sh smoke"], "Wrong validation workflow")
            require("publishing" not in workflow, "Validation must not publish")
        else:
            require(scripts == ["bash release/ci.sh gate", "bash release/ci.sh prepare", "bash release/ci.sh archive"], "Missing first-step revision gate")
            require(workflow["environment"]["vars"]["ATMA_VERIFIED_COMMIT"] == "${{ inputs.verified_commit }}", "Wrong revision input")
            require("default" not in workflow["inputs"]["verified_commit"], "Verified revision must be explicit")
            require(workflow["integrations"]["app_store_connect"] == "ATMA", "Wrong signing integration")


def validate_certificates(folder):
    manifest = load_json(folder / "manifest.json")
    roots = 0
    for row in manifest["certificates"]:
        require(Path(row["file"]).name == row["file"] and "\\" not in row["file"], "Unsafe certificate filename")
        pem = (folder / row["file"]).read_bytes()
        require(sha(pem) == row["sha256"].lower(), "Certificate PEM hash differs from pin")
        der = ssl.PEM_cert_to_DER_cert(pem.decode("ascii"))
        require(sha(der) == row["fingerprint256"].replace(":", "").lower(), "Certificate DER fingerprint differs from pin")
        if row["type"] == "root":
            roots += 1
            require(sha(pem) == ROOT_PEM_SHA256 and sha(der) == ROOT_DER_SHA256, "Unapproved root certificate")
            require(bytes.fromhex("06092a864886f70d010101") in der, "Pinned anchor must have an RSA key")
    require(roots == 1, "Expected exactly one pinned RSA root")


def png_header(path):
    data = path.read_bytes()
    require(data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR", "Expected PNG image")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    return width, height, depth, color


def validate_icons(root):
    resources = root / "BrowserResources"
    catalogue = resources / "Assets.xcassets"
    manifest = load_json(resources / "icon-manifest.json")
    require(manifest["source"] == "BrowserUI/assets/atma.png", "Icon must use the canonical UI logo")
    require(sha((root / manifest["source"]).read_bytes()) == manifest["source_sha256"], "Primary source logo changed; regenerate icons")
    require(sha((root / manifest["alternate_source"]).read_bytes()) == manifest["alternate_sha256"], "Alternate source sheet changed; regenerate icons")
    expected_mapping = {f"a1-{i:02d}": f"AppIconA1{i:02d}" for i in range(1, 11)}
    require(manifest["alternate_icons"] == expected_mapping, "Wrong alternate icon mapping")
    require(len(manifest["files"]) == 198, "Expected complete primary + 10 alternate icon sets")
    for relative, digest in manifest["files"].items():
        path = catalogue / relative
        require(path.resolve().is_relative_to(catalogue.resolve()), "Unsafe icon path")
        require(sha(path.read_bytes()) == digest, "Generated icon hash mismatch")
    for name in ALTERNATES | {"AppIcon"}:
        folder = catalogue / (name + ".appiconset")
        rows = load_json(folder / "Contents.json")["images"]
        require(len(rows) == 18, "Incomplete iPhone/iPad icon variants")
        for row in rows:
            pixels = int(float(row["size"].split("x")[0]) * int(row["scale"][0]))
            require(Path(row["filename"]).name == row["filename"], "Unsafe icon variant filename")
            require(png_header(folder / row["filename"]) == (pixels, pixels, 8, 2), "Icons must be opaque RGB at declared dimensions")


def validate_plist(info):
    require(info["UIDeviceFamily"] == [1, 2], "Plist must support iPhone and iPad")
    require(info["CFBundleLocalizations"] == ["ru", "en"], "Only Russian and English are supported")
    for key in ("UIApplicationSceneManifest", "WKAppBoundDomains", "CFBundleURLTypes"):
        require(key not in info, "Legacy scene/domain/scheme restriction remains")
    require(info.get("UIBackgroundModes") == ["audio"], "Only background audio is allowed")
    ats = info["NSAppTransportSecurity"]
    require(ats == {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoadsInWebContent": True}, "Unexpected ATS scope")
    require(info.get("NSCameraUsageDescription") and info.get("NSMicrophoneUsageDescription"), "Missing website media permission descriptions")


def validate(root=ROOT):
    project = load_json(root / "project.yml")
    validate_project(project)
    validate_workflows(load_json(root / "codemagic.yaml"))
    for filename in ("atma-ios-check.yml", "atma-testflight.yml"):
        validate_github_workflow(load_json(root / ".github/workflows" / filename),
                                 signing=filename == "atma-testflight.yml")
    info = plistlib.loads((root / "BrowserResources/Info.plist").read_bytes())
    validate_plist(info)
    plistlib.loads((root / "BrowserResources/PrivacyInfo.xcprivacy").read_bytes())
    validate_certificates(root / "assets/certificates")
    validate_icons(root)
    forbidden = re.compile(r"brave|vatma\.ru|chromium\.(?:framework|xcframework)|chromium\.googlesource|(?:from|import|require)\s*\(?\s*['\"]?chromium|\.native/src", re.I)
    scanned = 0
    for relative in APP_PATHS:
        base = root / relative
        require(base.exists() and base.resolve().is_relative_to(root.resolve()), "Application input missing or escapes project")
        for path in ([base] if base.is_file() else sorted(base.rglob("*"))):
            require(not path.is_symlink(), "Product input must not be a symlink")
            if not path.is_file():
                continue
            if path.suffix in (".swift", ".js", ".mjs", ".json", ".html", ".css", ".plist", ".strings", ".xcprivacy"):
                text = path.read_text(encoding="utf-8")
                require(not forbidden.search(text), f"Forbidden product dependency/endpoint in {path.relative_to(root)}")
                if path.suffix == ".json":
                    json.loads(text)
                if path.suffix == ".swift":
                    require("WKContentRuleList" not in text, "This release excludes native content filtering")
                    require("customUserAgent =" not in text, "This release excludes custom device User-Agents")
                    require(len(text.splitlines()) < 400, "Swift source exceeds line limit")
                    imports = set(re.findall(r"\bimport\s+(\w+)", text))
                    require(imports <= {"UIKit", "Foundation", "CoreFoundation", "WebKit", "Network", "CryptoKit", "Security", "UniformTypeIdentifiers", "AVFoundation", "MediaPlayer"}, "Native code may import only approved Apple frameworks")
            require(path.suffix.lower() not in (".dylib", ".a", ".framework", ".xcframework"), "Embedded SDK binary is not an allowed product input")
            scanned += 1
    for excluded in ("BrowserUI/profiles.json", "BrowserUI/content-blocker.json", "BrowserUI/assets/youtube-protection.js"):
        require(not (root / excluded).exists(), "This release must not bundle excluded payloads: " + excluded)
    for folder in ("release", "tests"):
        for path in (root / folder).glob("*.py"):
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            require(len(path.read_text(encoding="utf-8").splitlines()) < 400, "Tool source exceeds line limit")
    for folder in ("BrowserNativeTests", "BrowserNativeUITests"):
        for path in (root / folder).glob("*.swift"):
            require(len(path.read_text(encoding="utf-8").splitlines()) < 400, "Swift test source exceeds line limit")
    require(not (root / "ATMA").exists(), "Legacy application source remains active")
    return {"status": "passed", "scope": "static standalone source/config/resource validation",
            "product_files_checked": scanned, "apple_runtime": "not run by this validator",
            "identity": BUNDLE_ID, "minimum_ios": "17.0", "device_families": [1, 2]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    arguments = parser.parse_args()
    result = validate()
    output = json.dumps(result, indent=2) + "\n"
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(output, encoding="utf-8")
    print(output, end="")
