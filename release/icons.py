"""Rebuild checked-in app icons from the canonical BrowserUI logo (Pillow optional)."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "BrowserUI/assets/atma.png"
CATALOGUE = ROOT / "BrowserResources/Assets.xcassets"


def generate():
    from PIL import Image, ImageOps
    sheet_path = ROOT / "BrowserUI/assets/atma-icons-a1.png"
    sheet = Image.open(sheet_path).convert("RGBA")
    assert sheet.size == (1536, 1024), "Unexpected alternate icon sheet dimensions"
    sources = {"AppIcon": Image.open(SOURCE).convert("RGBA")}
    mapping = {}
    for index in range(10):
        x, y = 12 + index % 5 * 304, 164 + index // 5 * 316
        name = f"AppIconA1{index + 1:02d}"
        sources[name] = sheet.crop((x, y, x + 304, y + 304))
        mapping[f"a1-{index + 1:02d}"] = name
    for name, source in sources.items():
        generate_set(name, source, Image, ImageOps)
    metadata = {"info": {"author": "xcode", "version": 1}}
    (CATALOGUE / "Contents.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    manifest = {"source": SOURCE.relative_to(ROOT).as_posix(),
                "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                "alternate_source": sheet_path.relative_to(ROOT).as_posix(),
                "alternate_sha256": hashlib.sha256(sheet_path.read_bytes()).hexdigest(),
                "alternate_icons": mapping, "appearances": ["any", "dark", "tinted"],
                "files": {p.relative_to(CATALOGUE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted(CATALOGUE.rglob("*.png"))}}
    (CATALOGUE.parent / "icon-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(manifest['files'])} icons: primary and {len(mapping)} alternatives")


def generate_set(name, source, Image, ImageOps):
    target = CATALOGUE / f"{name}.appiconset"
    target.mkdir(parents=True, exist_ok=True)
    default = Image.new("RGBA", source.size, "white")
    default.alpha_composite(source)
    dark = source.resize((1024, 1024), Image.Resampling.LANCZOS)
    luminance = ImageOps.grayscale(dark).point(lambda level: 96 + level * 159 // 255)
    tinted = Image.new("L", dark.size, 0)
    tinted.paste(luminance, mask=dark.getchannel("A"))
    variants = {
        "any": default.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS),
        "dark": dark,
        "tinted": tinted,
    }
    images = []
    for appearance, image in variants.items():
        filename = f"icon-{appearance}-1024.png"
        image.save(target / filename)
        row = {"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename}
        if appearance != "any":
            row["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(row)
    metadata = {"info": {"author": "xcode", "version": 1}}
    previous = target / "Contents.json"
    if previous.is_file():
        old_rows = json.loads(previous.read_text(encoding="utf-8"))["images"]
        for row in old_rows:
            filename = row.get("filename", "")
            if row.get("idiom") in {"iphone", "ipad", "ios-marketing"} and Path(filename).name == filename and filename.endswith(".png"):
                (target / filename).unlink(missing_ok=True)
    (target / "Contents.json").write_text(json.dumps({"images": images, **metadata}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    generate()
