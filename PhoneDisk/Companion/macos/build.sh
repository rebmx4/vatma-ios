#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
destination=$1
video=$2
architecture=$(uname -m)
case "$architecture" in
    arm64) model=Apple-Silicon ;;
    x86_64) model=Intel ;;
    *) echo "Unsupported Mac architecture" >&2; exit 1 ;;
esac

mkdir -p "$destination"
destination=$(cd "$destination" && pwd)
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
icon="$root/../Assets.xcassets/AppIcon.appiconset/icon.png"

mkdir "$stage/PhoneDisk.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon" --out "$stage/PhoneDisk.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$icon" --out "$stage/PhoneDisk.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/PhoneDisk.iconset" -o "$stage/PhoneDisk.icns"
xcrun swiftc -O -target "$architecture-apple-macos13.0" "$root/macos/Thumbnail.swift" -o "$stage/phonedisk-thumbnail"

python - "$stage" <<'PY'
from pathlib import Path
import sysconfig
import shutil
import sys

license_file = Path(sysconfig.get_path("stdlib")) / "LICENSE.txt"
if license_file.is_file():
    shutil.copyfile(license_file, Path(sys.argv[1]) / "Python-LICENSE.txt")
PY
if test ! -f "$stage/Python-LICENSE.txt"; then
    curl --fail --silent --show-error --location \
        https://raw.githubusercontent.com/python/cpython/v3.13.17/LICENSE -o "$stage/Python-LICENSE.txt"
fi

python -m PyInstaller --noconfirm --clean --windowed --onedir --name PhoneDisk \
    --osx-bundle-identifier ru.rynpro.phonedisk.companion --target-arch "$architecture" \
    --distpath "$stage/out" --workpath "$stage/work" --specpath "$stage" \
    --icon "$stage/PhoneDisk.icns" --add-data "$root/web:web" --add-data "$icon:." \
    --add-data "$stage/Python-LICENSE.txt:licenses" --add-binary "$stage/phonedisk-thumbnail:media" \
    --copy-metadata cffi --copy-metadata cryptography --copy-metadata ifaddr --copy-metadata pycparser \
    --copy-metadata qrcode --copy-metadata zeroconf "$root/desktop.py"

mkdir "$stage/image"
mv "$stage/out/PhoneDisk.app" "$stage/image/Мой диск.app"
app="$stage/image/Мой диск.app"
python - "$app/Contents/Info.plist" <<'PY'
from pathlib import Path
import plistlib
import sys

path = Path(sys.argv[1])
with path.open("rb") as stream:
    info = plistlib.load(stream)
info.update({
    "CFBundleDisplayName": "Мой диск",
    "CFBundleName": "Мой диск",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "13.0",
    "NSLocalNetworkUsageDescription": "Мой диск подключается к iPhone в домашней сети.",
    "NSBonjourServices": ["_phonedisk._tcp"],
})
with path.open("wb") as stream:
    plistlib.dump(info, stream)
PY
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
test "$(lipo -archs "$app/Contents/MacOS/PhoneDisk")" = "$architecture"
"$app/Contents/MacOS/PhoneDisk" --verify --verify-video "$video"

ln -s /Applications "$stage/image/Applications"
output="$destination/PhoneDisk-macOS-$model-test.dmg"
hdiutil create -volname "Мой диск" -srcfolder "$stage/image" -format UDZO "$output"
hdiutil verify "$output"
