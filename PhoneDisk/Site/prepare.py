"""Create the static files for /disk/ with its existing demo."""

import argparse
import json
import shutil
from pathlib import Path


HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--demo", required=True, type=Path, help="HTML snapshot of the existing demo")
    parser.add_argument("--iphone", help="Compatible TestFlight or App Store URL")
    parser.add_argument("--windows", help="URL of the compatible Windows installer")
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    for asset in ("index.html", "styles.css", "guide.js"):
        shutil.copyfile(HERE / asset, args.output / asset)
    icon = HERE.parent / "Assets.xcassets" / "AppIcon.appiconset" / "icon.png"
    shutil.copyfile(icon, args.output / "icon.png")
    demo = args.output / "demo"
    demo.mkdir(exist_ok=True)
    if args.demo.resolve() != (demo / "index.html").resolve():
        shutil.copyfile(args.demo, demo / "index.html")
    downloads = {"iphone": args.iphone, "windows": args.windows, "demo": "./demo/"}
    (args.output / "downloads.js").write_text("window.phoneDiskDownloads = " +
                                              json.dumps(downloads, ensure_ascii=True, indent=2) + ";\n",
                                              encoding="utf-8")


if __name__ == "__main__":
    main()
