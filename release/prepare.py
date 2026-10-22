"""Apply ATMA display resources to the pinned native iOS source checkout."""

import argparse
import base64
import hashlib
import io
import json
import plistlib
import re
import subprocess
import os
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from branding import rebrand_display_text, rebrand_grit, rebrand_strings, rebrand_swift_values
from runtime_patch import configure_app_target
from glyphs import replace_symbol_outlines
from resource_assets import prepare_resources, prepare_web_logos


ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "release/config.json").read_text(encoding="utf-8"))
IOS_PATH = Path("ios/brave-ios")
LOGO_NAMES = {
    "brave-icon-no-bg", "brave-icon", "brave-logo-no-bg-small", "brave_document",
    "brave.logo", "brave.logo.greyscale", "brave.wordmark", "wallet-brave-icon",
    "bottom-bar-logo-bottom", "welcome-view-ntp-logo", "focus-brave-watermark",
    "focus-icon-brave", "focus-logo-brave",
}
WORDMARK_NAMES = {"brave.wordmark", "focus-logo-brave"}


def read_source(path):
    return path.read_bytes().decode("utf-8")


def write_if_changed(path, content):
    payload = content.encode("utf-8") if isinstance(content, str) else content
    if path.is_file() and path.read_bytes() == payload:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    # Detach dependency-store hardlinks rather than modifying their inode.
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".atma-", delete=False) as temporary:
        temporary.write(payload)
        temporary_path = Path(temporary.name)
    try:
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()
    return True


def set_xcconfig(source, key, value):
    pattern = re.compile(rf"^{re.escape(key)}\s*=.*$", re.MULTILINE)
    if not pattern.search(source):
        raise ValueError(f"Expected upstream setting is missing: {key}")
    return pattern.sub(f"{key} = {value}", source)


def make_images(source):
    icon_path = ROOT / CONFIG["icon_path"]
    assert hashlib.sha256(icon_path.read_bytes()).hexdigest() == CONFIG["icon_sha256"], "Icon changed"
    image = Image.open(icon_path).convert("RGBA")
    opaque = Image.new("RGB", image.size, "white")
    opaque.paste(image, mask=image.getchannel("A"))
    opaque = ImageOps.contain(opaque, (1024, 1024), Image.Resampling.LANCZOS)
    square = Image.new("RGB", (1024, 1024), "white")
    square.paste(opaque, ((1024 - opaque.width) // 2, (1024 - opaque.height) // 2))
    mark = Image.new("RGBA", image.size)
    # The UI glyph uses the red artwork, leaving out the icon's white tile.
    alpha = image.getchannel("A")
    pixels = image.load()
    mask = Image.new("L", image.size)
    values = []
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, _ = pixels[x, y]
            values.append(alpha.getpixel((x, y)) if red > 1.3 * max(green, blue) else 0)
    mask.putdata(values)
    mark.paste(image, mask=mask)
    bounds = mark.getbbox()
    assert bounds, "The selected icon contains no visible red mark"
    mark = mark.crop(bounds)
    font_path = source / IOS_PATH / "Sources/Brave/Assets/Fonts/FiraSans-Bold.ttf"
    font = ImageFont.truetype(str(font_path), 144)
    wordmark = Image.new("RGBA", (500, 180))
    ImageDraw.Draw(wordmark).text((0, -3), CONFIG["product_name"], font=font, fill="#202024")
    return square, mark, wordmark.crop(wordmark.getbbox())


def prepare(source):
    source = source.resolve()
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if commit != CONFIG["upstream_commit"]:
        raise ValueError(f"Source revision differs from the pinned release: {commit}")
    ios = source / IOS_PATH
    report = {"upstream_commit": commit, "product_name": CONFIG["product_name"], "changed": {}}

    def update(path, content, kind):
        if write_if_changed(path, content):
            report["changed"][kind] = report["changed"].get(kind, 0) + 1

    for path in ios.rglob("*.strings"):
        update(path, rebrand_strings(read_source(path)), "localized_text")
    for path in ios.rglob("*.swift"):
        update(path, rebrand_swift_values(read_source(path)), "swift_fallbacks")
    for extension in ("*.grd", "*.grdp", "*.xtb"):
        for path in source.rglob(extension):
            if ".git" not in path.parts:
                update(path, rebrand_grit(read_source(path)), "core_text")
    for path in (source / "app/theme").rglob("BRANDING"):
        text = read_source(path)
        for key in ("PRODUCT_FULLNAME", "PRODUCT_SHORTNAME", "INSTALLER_FULLNAME"):
            text = re.sub(rf"^{key}=.*$", f"{key}={CONFIG['product_name']}", text, flags=re.MULTILINE)
        update(path, text, "product_identity")

    config_dir = ios / "App/Configuration"
    replacements = {
        "Base.xcconfig": {
            "DEVELOPMENT_TEAM": CONFIG["development_team"],
            "BRAVE_URL_SCHEME": CONFIG["url_scheme"],
        },
        "Release.xcconfig": {
            "MOZ_BUNDLE_DISPLAY_NAME": CONFIG["product_name"],
            "MOZ_BUNDLE_ID": CONFIG["bundle_id"],
        },
        "Release-AppStore.xcconfig": {"CODE_SIGN_IDENTITY": "Apple Distribution"},
    }
    for filename, settings in replacements.items():
        path = config_dir / filename
        text = read_source(path)
        for key, value in settings.items():
            text = set_xcconfig(text, key, value)
        update(path, text, "xcode_identity")

    for path in (ios / "App").rglob("*.plist"):
        data = plistlib.loads(path.read_bytes())
        if not isinstance(data, dict):
            continue
        original = dict(data)
        for key, value in list(data.items()):
            if isinstance(value, str) and (key.endswith("UsageDescription") or key == "CFBundleDisplayName"):
                data[key] = rebrand_display_text(value)
        if data != original:
            update(path, plistlib.dumps(data, sort_keys=False), "system_text")

    square, mark, wordmark = make_images(source)
    prepare_resources(ios, square, update)
    prepare_web_logos(source, mark, update)
    wallet_script = ios / "Sources/Brave/Frontend/UserContent/UserScripts/Scripts_Dynamic/Scripts/Paged/WalletEthereumProviderScript.js"
    wallet_text = read_source(wallet_script)
    wallet_icon = io.BytesIO()
    square.resize((96, 96), Image.Resampling.LANCZOS).save(wallet_icon, format="PNG")
    wallet_icon_url = "data:image/png;base64," + base64.b64encode(wallet_icon.getvalue()).decode("ascii")
    wallet_text, name_count = re.subn(r'name: "(?:Brave|ATMA) Wallet"', 'name: "ATMA Wallet"', wallet_text)
    wallet_text, icon_count = re.subn(r'icon: "data:image/png;base64,[^"]+"', f'icon: "{wallet_icon_url}"', wallet_text)
    if (name_count, icon_count) != (1, 1):
        raise ValueError("The pinned wallet provider metadata has changed")
    update(wallet_script, wallet_text, "wallet_metadata")
    report["native_symbols_checked"] = replace_symbol_outlines(source, mark, update)
    for catalog in ios.rglob("*.appiconset"):
        info_path = catalog / "Contents.json"
        data = json.loads(info_path.read_text(encoding="utf-8"))
        for index, item in enumerate(data.get("images", [])):
            width = float(item.get("size", "1024x1024").split("x")[0])
            scale = float(item.get("scale", "1x").rstrip("x"))
            size = round(width * scale)
            filename = f"atma-{index}-{size}.png"
            square.resize((size, size), Image.Resampling.LANCZOS).save(catalog / filename)
            item["filename"] = filename
        update(info_path, json.dumps(data, indent=2) + "\n", "app_icons")
    for catalog in (ios / "App/iOS/AppIcons").glob("*.icon"):
        info_path = catalog / "icon.json"
        data = json.loads(info_path.read_text(encoding="utf-8"))
        square.save(catalog / "Assets/atma.png")
        data["groups"] = [{"name": "ATMA", "layers": [{"name": "ATMA", "image-name": "atma.png", "position": {"scale": 1, "translation-in-points": [0, 0]}}]}]
        update(info_path, json.dumps(data, indent=2) + "\n", "composer_icons")
    for catalog in ios.rglob("*.imageset"):
        if catalog.stem not in LOGO_NAMES:
            continue
        graphic = wordmark if catalog.stem in WORDMARK_NAMES else mark
        output = ImageOps.contain(graphic, (512, 512), Image.Resampling.LANCZOS)
        output.save(catalog / "atma.png")
        info = {"images": [{"filename": "atma.png", "idiom": "universal", "scale": "1x"}], "info": {"author": "xcode", "version": 1}}
        update(catalog / "Contents.json", json.dumps(info, indent=2) + "\n", "ui_logos")
    configure_app_target(ios, CONFIG, update)
    video_path = ROOT / CONFIG["onboarding_video_path"]
    video = video_path.read_bytes()
    if hashlib.sha256(video).hexdigest() != CONFIG["onboarding_video_sha256"]:
        raise ValueError("The ATMA tutorial video differs from its pinned asset")
    video_dir = ios / "Sources/Onboarding/WelcomeFocus/Resources/Videos"
    for filename in ("set-default-pip-dark.mp4", "set-default-pip-light.mp4"):
        if not (video_dir / filename).is_file():
            raise ValueError(f"The pinned tutorial asset is missing: {filename}")
        update(video_dir / filename, video, "tutorial_videos")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = prepare(args.source)
    write_if_changed(args.report, json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False))
