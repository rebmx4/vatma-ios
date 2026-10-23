#!/usr/bin/env bash
set -euo pipefail

task_root="${CM_BUILD_DIR:?Codemagic build directory is required}"
cd "$task_root"
export TMPDIR="$task_root/.cache/tmp"
export PIP_CACHE_DIR="$task_root/.cache/pip"
export PYTHONPYCACHEPREFIX="$task_root/.cache/python"
export PYTHONDONTWRITEBYTECODE=1
export HOMEBREW_CACHE="$task_root/.cache/homebrew"
export HOMEBREW_LOGS="$task_root/.cache/homebrew-logs"
export HOMEBREW_TEMP="$task_root/.cache/tmp"
mkdir -p "$TMPDIR" "$task_root/out"

require_verified_revision() {
  test -n "${ATMA_VERIFIED_COMMIT:-}"
  test "$ATMA_VERIFIED_COMMIT" = "$(git rev-parse HEAD)" || {
    echo 'verified_commit must equal the successfully tested HEAD revision' >&2
    return 1
  }
}

export_screenshots() {
  for device in iphone ipad; do
    result="$task_root/out/ATMA-$device.xcresult"
    if [[ -d "$result" ]]; then
      xcrun xcresulttool export attachments --path "$result" \
        --output-path "$task_root/out/screenshots/$device" || true
    fi
  done
}

case "${1:?Expected gate, prepare, smoke or archive}" in
  gate)
    require_verified_revision
    ;;
  prepare)
    python3 -B -m unittest discover -s tests -v
    node --test tests/*.test.mjs
    python3 -B release/validate.py --report out/source-validation.json
    for script in BrowserUI/*.js BrowserUI/assets/*.js BrowserUI/assets/*.mjs; do
      [[ ! -f "$script" ]] || node --check "$script"
    done
    if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
    xcodegen --version | tee out/xcodegen-version.log
    xcodebuild -version | tee out/xcode-version.log
    xcodegen generate --spec project.yml
    xcodebuild -list -project ATMA.xcodeproj > out/project-targets.log
    plutil -lint BrowserResources/Info.plist BrowserResources/PrivacyInfo.xcprivacy
    plutil -lint BrowserResources/ru.lproj/InfoPlist.strings BrowserResources/en.lproj/InfoPlist.strings
    ;;
  smoke)
    test -d ATMA.xcodeproj
    trap export_screenshots EXIT
    xcrun simctl list devices available -j | python3 -B release/simulators.py > out/simulators.json
    for device in iphone ipad; do
      simulator="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' out/simulators.json "$device")"
      xcrun simctl boot "$simulator" 2>/dev/null || true
      xcrun simctl bootstatus "$simulator" -b
      options=()
      if [[ "$device" = ipad ]]; then options=(-only-testing:BrowserNativeUITests); fi
      xcodebuild test -project ATMA.xcodeproj -scheme ATMA -configuration Debug \
        -destination "platform=iOS Simulator,id=$simulator" \
        -derivedDataPath "$task_root/.cache/derived-simulator" \
        -resultBundlePath "$task_root/out/ATMA-$device.xcresult" \
        -parallel-testing-enabled NO "${options[@]}" CODE_SIGNING_ALLOWED=NO \
        2>&1 | tee "$task_root/out/test-$device.log"
      xcrun simctl io "$simulator" screenshot "$task_root/out/$device-final.png"
      xcrun simctl shutdown "$simulator"
    done
    git rev-parse HEAD > out/verified-commit.txt
    ;;
  archive)
    require_verified_revision
    test -d ATMA.xcodeproj
    python3 -B release/validate.py --report out/prearchive-validation.json
    mkdir -p .cache/signing .cache/export
    cleanup_signing() { rm -f "$task_root/.cache/signing/distribution-key.pem"; }
    trap cleanup_signing EXIT
    python3 - <<'PY'
from pathlib import Path
import base64, os
destination = Path(os.environ['CM_BUILD_DIR']) / '.cache/signing/distribution-key.pem'
destination.write_bytes(base64.b64decode(os.environ['CERT_KEY_B64'], validate=True))
destination.chmod(0o600)
PY
    keychain initialize
    export CERTIFICATE_PRIVATE_KEY
    CERTIFICATE_PRIVATE_KEY="$(cat .cache/signing/distribution-key.pem)"
    app-store-connect fetch-signing-files ru.atma.app --type IOS_APP_STORE --create
    keychain add-certificates
    xcode-project use-profiles --project ATMA.xcodeproj \
      --export-options-plist "$task_root/.cache/signing/export.plist"
    latest_build="$(app-store-connect get-latest-testflight-build-number 6774934498)"
    [[ "$latest_build" =~ ^[0-9]+$ ]]
    next_build="$((latest_build + 1))"
    printf '%s\n' "$next_build" > out/build-number.txt
    xcodebuild archive -project ATMA.xcodeproj -scheme ATMA -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$task_root/out/ATMA.xcarchive" \
      -derivedDataPath "$task_root/.cache/derived-device" CURRENT_PROJECT_VERSION="$next_build" \
      2>&1 | tee out/device-archive.log
    app="$task_root/out/ATMA.xcarchive/Products/Applications/ATMA.app"
    codesign --verify --deep --strict "$app"
    codesign -d --entitlements :- "$app" > out/signed-entitlements.plist 2>out/codesign.log
    python3 -B release/verify_signing.py out/signed-entitlements.plist
    xcodebuild -exportArchive -archivePath "$task_root/out/ATMA.xcarchive" \
      -exportPath "$task_root/.cache/export" -exportOptionsPlist "$task_root/.cache/signing/export.plist" \
      2>&1 | tee out/export.log
    python3 -B release/verify_ipa.py .cache/export/ATMA.ipa --build "$next_build" | tee out/ipa-validation.json
    ditto -x -k .cache/export/ATMA.ipa .cache/export-check
    codesign --verify --deep --strict .cache/export-check/Payload/ATMA.app
    codesign -d --entitlements :- .cache/export-check/Payload/ATMA.app > out/exported-entitlements.plist 2>out/exported-codesign.log
    python3 -B release/verify_signing.py out/exported-entitlements.plist
    # Publishing sees only this directory, populated after every validation passed.
    mkdir -p out/ipa
    cp .cache/export/ATMA.ipa out/ipa/ATMA.ipa
    ;;
  *) echo 'Unknown standalone release stage' >&2; exit 2 ;;
esac
