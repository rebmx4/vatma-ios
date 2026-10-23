"""Rebuild checked-in app icons from the canonical BrowserUI logo (Pillow optional)."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "BrowserUI/assets/atma.png"
CATALOGUE = ROOT / "BrowserResources/Assets.xcassets"


def generate():
    from PIL import Image
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
        background = Image.new("RGBA", source.size, "white")
        background.alpha_composite(source)
        generate_set(name, background.convert("RGB"), Image)
    metadata = {"info": {"author": "xcode", "version": 1}}
    (CATALOGUE / "Contents.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    manifest = {"source": SOURCE.relative_to(ROOT).as_posix(),
                "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                "alternate_source": sheet_path.relative_to(ROOT).as_posix(),
                "alternate_sha256": hashlib.sha256(sheet_path.read_bytes()).hexdigest(),
                "alternate_icons": mapping, "background": "white", "mode": "RGB",
                "files": {p.relative_to(CATALOGUE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sorted(CATALOGUE.rglob("*.png"))}}
    (CATALOGUE.parent / "icon-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(manifest['files'])} opaque RGB icons: primary and {len(mapping)} alternatives")


def generate_set(name, source, Image):
    target = CATALOGUE / f"{name}.appiconset"
    target.mkdir(parents=True, exist_ok=True)
    images = []
    variants = [("iphone", 20, (2, 3)), ("iphone", 29, (2, 3)),
                ("iphone", 40, (2, 3)), ("iphone", 60, (2, 3)),
                ("ipad", 20, (1, 2)), ("ipad", 29, (1, 2)),
                ("ipad", 40, (1, 2)), ("ipad", 76, (1, 2)),
                ("ipad", 83.5, (2,)), ("ios-marketing", 1024, (1,))]
    for idiom, points, scales in variants:
        for scale in scales:
            pixels = int(points * scale)
            name = f"icon-{idiom}-{points:g}@{scale}x.png"
            canvas = Image.new("RGB", (pixels, pixels), "white")
            image = source.copy()
            image = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
            canvas.paste(image, ((pixels - image.width) // 2, (pixels - image.height) // 2))
            canvas.save(target / name)
            images.append({"idiom": idiom, "size": f"{points:g}x{points:g}", "scale": f"{scale}x", "filename": name})
    metadata = {"info": {"author": "xcode", "version": 1}}
    (target / "Contents.json").write_text(json.dumps({"images": images, **metadata}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    generate()
