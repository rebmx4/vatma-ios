from pathlib import Path
import copy
import json
import os
import plistlib
import shutil
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "release"))
import validate
import verify_ipa
import verify_signing
from simulators import select

TEMP_ROOT = ROOT / "out/test-tmp"
TEMP_ROOT.mkdir(parents=True, exist_ok=True)


def packaged_info():
    icons = {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"},
             "CFBundleAlternateIcons": {name: {"CFBundleIconName": name} for name in verify_ipa.ALTERNATES}}
    return {"CFBundleIdentifier": "ru.atma.browser", "CFBundleName": "ATMA", "CFBundleDisplayName": "ATMA",
            "CFBundleExecutable": "ATMA", "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7",
            "MinimumOSVersion": "17.0", "UIDeviceFamily": [1, 2],
            "UIBackgroundModes": ["audio"],
            "CFBundleIcons": icons, "CFBundleIcons~ipad": copy.deepcopy(icons),
            "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoadsInWebContent": True}}


class StandaloneConfigTests(unittest.TestCase):
    def test_current_project_and_manual_workflows_pass(self):
        validate.validate_project(validate.load_json(ROOT / "project.yml"))
        validate.validate_workflows(validate.load_json(ROOT / "codemagic.yaml"))

    def test_legacy_application_source_or_sdk_cannot_enter_target(self):
        for change in (lambda p: p["targets"]["ATMA"]["sources"].append({"path": ".native/src/brave"}),
                       lambda p: p["targets"]["ATMA"].update(dependencies=[{"framework": "BraveCore.framework"}])):
            project = validate.load_json(ROOT / "project.yml")
            change(project)
            with self.assertRaises(ValueError):
                validate.validate_project(project)

    def test_automatic_trigger_or_missing_revision_gate_is_rejected(self):
        for change in (lambda w: w["atma-testflight"].update(triggering={"events": ["push"]}),
                       lambda w: w["atma-device-testflight"]["scripts"].pop(0)):
            config = validate.load_json(ROOT / "codemagic.yaml")
            change(config["workflows"])
            with self.assertRaises(ValueError):
                validate.validate_workflows(config)

    def test_browser_plist_and_all_opaque_icon_variants_pass(self):
        validate.validate_plist(plistlib.loads((ROOT / "BrowserResources/Info.plist").read_bytes()))
        validate.validate_icons(ROOT)

    def test_background_audio_is_required_and_other_background_modes_rejected(self):
        source = plistlib.loads((ROOT / "BrowserResources/Info.plist").read_bytes())
        validate.validate_plist(source)
        for modes in ([], ["audio", "location"], ["voip"]):
            with self.assertRaises(ValueError):
                validate.validate_plist({**source, "UIBackgroundModes": modes})
            with self.assertRaises(ValueError):
                verify_ipa.validate_info({**packaged_info(), "UIBackgroundModes": modes}, "7")

    def test_real_bundled_certificate_pins_and_tampering(self):
        validate.validate_certificates(ROOT / "assets/certificates")
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as temporary:
            folder = Path(temporary) / "certificates"
            shutil.copytree(ROOT / "assets/certificates", folder)
            manifest = validate.load_json(folder / "manifest.json")
            entry = next(row for row in manifest["certificates"] if row["type"] == "root")
            target = folder / entry["file"]
            target.write_bytes(target.read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "PEM hash"):
                validate.validate_certificates(folder)
            entry["sha256"] = validate.sha(target.read_bytes())
            (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Unapproved root"):
                validate.validate_certificates(folder)


class PackageTests(unittest.TestCase):
    def test_identity_build_number_ipad_and_generated_alternate_icons(self):
        verify_ipa.validate_info(packaged_info(), "7")
        for change in (lambda i: i.update(CFBundleVersion="6"),
                       lambda i: i.update(MinimumOSVersion="16.0"),
                       lambda i: i.update(UIDeviceFamily=[1]),
                       lambda i: i.pop("CFBundleIcons~ipad")):
            info = packaged_info()
            change(info)
            with self.assertRaises(ValueError):
                verify_ipa.validate_info(info, "7")

    def test_previous_app_identity_is_rejected(self):
        old_info = {**packaged_info(), "CFBundleIdentifier": "ru.atma.app"}
        with self.assertRaises(ValueError):
            verify_ipa.validate_info(old_info, "7")
        old_signing = {"application-identifier": "GR3WB4Z646.ru.atma.app",
                       "com.apple.developer.team-identifier": "GR3WB4Z646"}
        with self.assertRaises(ValueError):
            verify_signing.verify(plistlib.dumps(old_signing))

    def test_ipa_resource_matching_and_vendor_framework_rejection(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as temporary:
            fixture = Path(temporary)
            (fixture / "BrowserUI").mkdir()
            (fixture / "assets/certificates").mkdir(parents=True)
            (fixture / "BrowserUI/index.html").write_text("ATMA fixture", encoding="utf-8")
            (fixture / "assets/certificates/manifest.json").write_text("{}", encoding="utf-8")
            package = fixture / "ATMA.ipa"
            with zipfile.ZipFile(package, "w") as archive:
                archive.writestr("Payload/ATMA.app/Info.plist", plistlib.dumps(packaged_info()))
                archive.writestr("Payload/ATMA.app/ATMA", bytes.fromhex("cffaedfe") + b"test-fixture")
                archive.writestr("Payload/ATMA.app/Assets.car", b"test-fixture")
                archive.writestr("Payload/ATMA.app/PrivacyInfo.xcprivacy", b"test-fixture")
                archive.writestr("Payload/ATMA.app/BrowserUI/index.html", b"ATMA fixture")
                archive.writestr("Payload/ATMA.app/certificates/manifest.json", b"{}")
            self.assertEqual(verify_ipa.verify(package, "7", root=fixture)["app"], "ATMA.app")
            injected = fixture / "with-device-catalogue.ipa"
            shutil.copyfile(package, injected)
            with zipfile.ZipFile(injected, "a") as archive:
                archive.writestr("Payload/ATMA.app/BrowserUI/profiles.json", b"[]")
            with self.assertRaisesRegex(ValueError, "excluded payload"):
                verify_ipa.verify(injected, "7", root=fixture)
            with zipfile.ZipFile(package, "a") as archive:
                archive.writestr("Payload/ATMA.app/Frameworks/BraveCore.framework/BraveCore", b"forbidden")
            with self.assertRaisesRegex(ValueError, "embedded browser"):
                verify_ipa.verify(package, "7", root=fixture)

    def test_signing_rejects_shared_groups_push_debug_or_wrong_team(self):
        clean = {"application-identifier": "GR3WB4Z646.ru.atma.browser", "com.apple.developer.team-identifier": "GR3WB4Z646"}
        verify_signing.verify(plistlib.dumps(clean))
        for change in ({"aps-environment": "production"}, {"get-task-allow": True},
                       {"com.apple.security.application-groups": ["group.old"]},
                       {"com.apple.developer.team-identifier": "OTHER"}):
            with self.assertRaises(ValueError):
                verify_signing.verify(plistlib.dumps({**clean, **change}))


class SimulatorSelectionTests(unittest.TestCase):
    def test_prefers_store_screenshot_sizes_on_the_matching_runtime(self):
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
            {"name": "iPhone 17 Pro", "udid": "small-phone", "isAvailable": True},
            {"name": "iPad Pro 11-inch (M5)", "udid": "small-tablet", "isAvailable": True},
            {"name": "iPhone 17 Pro Max", "udid": "store-phone", "isAvailable": True},
            {"name": "iPad Pro 13-inch (M5)", "udid": "store-tablet", "isAvailable": True}]}}
        selected = select(payload, ios_version="26.4")
        self.assertEqual(selected["iphone"], "store-phone")
        self.assertEqual(selected["ipad"], "store-tablet")

    def test_latest_available_runtime_requires_phone_and_ipad(self):
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
            {"name": "iPhone 17", "udid": "phone", "isAvailable": True},
            {"name": "iPad (A16)", "udid": "tablet", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"name": "iPhone 18", "udid": "unavailable", "isAvailable": False}]}}
        self.assertEqual(select(payload)["ipad"], "tablet")
        payload["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-26-4"].pop()
        with self.assertRaises(ValueError):
            select(payload)

    def test_sdk_runtime_is_selected_over_a_newer_installed_runtime(self):
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-" + version: [
            {"name": "iPhone 17", "udid": "phone-" + version, "isAvailable": True},
            {"name": "iPad Pro", "udid": "tablet-" + version, "isAvailable": True}]
            for version in ("26-4", "26-5")}}
        self.assertEqual(select(payload, ios_version="26.4")["ipad"], "tablet-26-4")

    def test_sdk_patch_version_uses_the_same_major_minor_runtime(self):
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
            {"name": "iPhone 17", "udid": "phone", "isAvailable": True},
            {"name": "iPad Pro", "udid": "tablet", "isAvailable": True}]}}
        self.assertEqual(select(payload, ios_version="26.4.1")["runtime"],
                         "com.apple.CoreSimulator.SimRuntime.iOS-26-4")

    def test_missing_sdk_runtime_does_not_silently_select_a_newer_one(self):
        payload = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
            {"name": "iPhone 17", "udid": "phone", "isAvailable": True},
            {"name": "iPad Pro", "udid": "tablet", "isAvailable": True}]}}
        with self.assertRaisesRegex(ValueError, "26.4"):
            select(payload, ios_version="26.4")


if __name__ == "__main__":
    unittest.main()
