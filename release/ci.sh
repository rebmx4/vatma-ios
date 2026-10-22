#!/usr/bin/env bash
set -euo pipefail

task_root="${CM_BUILD_DIR:?Codemagic build directory is required}"
native="$task_root/.native/src/brave"
project="$native/ios/brave-ios/App/Client.xcodeproj"
export npm_config_cache="$task_root/.cache/npm"
export npm_config_store_dir="$task_root/.cache/pnpm"
export PIP_CACHE_DIR="$task_root/.cache/pip"
export TMPDIR="$task_root/.cache/tmp"
export PYTHONDONTWRITEBYTECODE=1
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=4096"
export PYTHONPATH="$task_root/.cache/python:${PYTHONPATH:-}"
export PATH="$task_root/.cache/tools/node_modules/.bin:$PATH"
mkdir -p "$task_root/.cache/tmp" "$task_root/out"

config_value() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$task_root/release/config.json" "$1"
}
bundle_id="$(config_value bundle_id)"
app_id="$(config_value apple_app_id)"
version="$(config_value marketing_version)"
jobs=8
if (( $(sysctl -n hw.memsize) < 12884901888 )); then jobs=6; fi

case "${1:?Expected prepare, smoke or archive}" in
  prepare)
    cd "$task_root"
    python3 -m pip install --target "$task_root/.cache/python" -r release/requirements.txt
    python3 -m unittest discover -s tests -v
    npm install --prefix "$task_root/.cache/tools" --ignore-scripts --no-audit --no-fund pnpm@11.11.0
    git clone --depth 1 --branch "$(config_value upstream_tag)" https://github.com/brave/brave-core.git "$native"
    test "$(git -C "$native" rev-parse HEAD)" = "$(config_value upstream_commit)"
    python3 release/prepare_build.py --source "$native"
    node tests/check_patch_concurrency.mjs "$native/build/commands/lib/gitPatcher.js"
    cat > "$native/.env" <<'CONFIG'
projects_chrome_custom_vars_checkout_clangd=false
projects_chrome_custom_vars_checkout_clang_coverage_tools=false
use_remoteexec=false
concurrent_links=1
gn_args={"symbol_level":0,"enable_dsyms":false,"use_thin_lto":false,"is_official_build":false,"action_pool_depth":1}
CONFIG
    cd "$native"
    pnpm install --frozen-lockfile
    node build/commands/scripts/sync.ts --init --target_os=ios --target_arch=arm64 --no-history
    pnpm run ios_bootstrap
    "$native/../third_party/node/mac_arm64/node-darwin-arm64/bin/node" -e 'const heap = require("node:v8").getHeapStatistics().heap_size_limit; if (heap < 4000000000) throw new Error("Node heap override was not applied"); console.log(JSON.stringify({native_node_heap_limit: heap}))'
    cd "$task_root"
    python3 release/prepare.py --source "$native" --report out/branding-preparation.json
    python3 release/validate.py --source "$native" | tee out/source-validation.json
    ruby release/add_smoke_target.rb "$native" "$task_root/release/ATMASmokeTests.swift" "$task_root/release/config.json"
    ;;
  core-simulator|core-device)
    cd "$native"
    target_environment="${1#core-}"
    pnpm run build Release --target_os=ios --target_arch=arm64 --target_environment="$target_environment" --ninja "j:$jobs" 2>&1 | tee "$task_root/out/core-$target_environment.log"
    ;;
  smoke)
    cd "$native"
    export_smoke_images() {
      if [[ -d "$task_root/out/ATMA-smoke.xcresult" ]]; then
        xcrun xcresulttool export attachments --path "$task_root/out/ATMA-smoke.xcresult" --output-path "$task_root/out/screenshots" || true
      fi
    }
    trap export_smoke_images EXIT
    xcodebuild test -project "$project" -scheme ATMA -configuration Release \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -derivedDataPath "$task_root/.cache/derived-simulator" \
      -resultBundlePath "$task_root/out/ATMA-smoke.xcresult" \
      -only-testing:ATMASmokeTests CODE_SIGNING_ALLOWED=NO \
      brave_ios_marketing_version="$version" brave_version_build=1 \
      2>&1 | tee "$task_root/out/simulator-test.log"
    ;;
  archive)
    cd "$task_root"
    mkdir -p "$task_root/.cache/signing"
    keychain initialize
    printf '%s' "$CERT_KEY_B64" | base64 --decode > "$task_root/.cache/signing/distribution-key.pem"
    export CERTIFICATE_PRIVATE_KEY
    CERTIFICATE_PRIVATE_KEY="$(cat "$task_root/.cache/signing/distribution-key.pem")"
    app-store-connect fetch-signing-files "$bundle_id" --type IOS_APP_STORE --create
    keychain add-certificates
    xcode-project use-profiles --project "$project" --export-options-plist "$task_root/.cache/signing/export.plist"
    next_build="$(app-store-connect get-latest-testflight-build-number "$app_id")"
    next_build="$((next_build + 1))"
    printf '%s\n' "$next_build" > "$task_root/out/build-number.txt"
    cd "$native"
    xcodebuild archive -project "$project" -scheme ATMA -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$task_root/out/ATMA.xcarchive" \
      -derivedDataPath "$task_root/.cache/derived-device" \
      brave_ios_marketing_version="$version" brave_version_build="$next_build" \
      2>&1 | tee "$task_root/out/device-archive.log"
    codesign --verify --deep --strict "$task_root/out/ATMA.xcarchive/Products/Applications/Client.app"
    xcodebuild -exportArchive -archivePath "$task_root/out/ATMA.xcarchive" \
      -exportPath "$task_root/out/ipa" -exportOptionsPlist "$task_root/.cache/signing/export.plist" \
      2>&1 | tee "$task_root/out/export.log"
    cd "$task_root"
    python3 release/verify_ipa.py "$task_root/out/ipa/Client.ipa" --build "$next_build" | tee out/ipa-validation.json
    ;;
  *) echo 'Unknown release stage' >&2; exit 2 ;;
esac
