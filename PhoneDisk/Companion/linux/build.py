"""Build the native Linux installer using distribution packages for the runtime."""

import argparse
import shutil
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[1]
CONTROL = """Package: phonedisk
Version: 0.1.1~test1
Section: utils
Priority: optional
Architecture: all
Maintainer: PhoneDisk
Depends: python3 (>= 3.10), python3-tk, python3-gi, python3-cryptography, python3-ifaddr, python3-qrcode, python3-zeroconf, ffmpeg
Description: My Disk companion for iPhone
 Select folders on this computer and connect an iPhone over the local network.
"""
DESKTOP = """[Desktop Entry]
Type=Application
Name=Мой диск
Exec=/opt/phonedisk/desktop
Icon=phonedisk
Terminal=false
Categories=Utility;FileTools;
"""


def build(output):
    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix="phonedisk-deb-") as temporary:
        package = Path(temporary) / "package"
        control = package / "DEBIAN"
        control.mkdir(parents=True)
        (control / "control").write_text(CONTROL, encoding="utf-8")
        app = package / "opt" / "phonedisk"
        app.mkdir(parents=True)
        shutil.copytree(ROOT / "phonedisk", app / "phonedisk", ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copytree(ROOT / "web", app / "web")
        shutil.copyfile(ROOT / "desktop_theme.py", app / "desktop_theme.py")
        launcher = app / "desktop"
        launcher.write_text("#!/usr/bin/python3\n" + (ROOT / "desktop.py").read_text(encoding="utf-8"),
                            encoding="utf-8")
        launcher.chmod(0o755)
        icon = ROOT.parent / "Assets.xcassets" / "AppIcon.appiconset" / "icon.png"
        shutil.copyfile(icon, app / "icon.png")
        icon_path = package / "usr" / "share" / "pixmaps" / "phonedisk.png"
        icon_path.parent.mkdir(parents=True)
        shutil.copyfile(icon, icon_path)
        desktop_entry = package / "usr" / "share" / "applications" / "phonedisk.desktop"
        desktop_entry.parent.mkdir(parents=True)
        desktop_entry.write_text(DESKTOP, encoding="utf-8")
        subprocess.run(["dpkg-deb", "--build", "--root-owner-group", str(package), str(output)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    build(parser.parse_args().output.resolve())
