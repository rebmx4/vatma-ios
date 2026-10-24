# ATMA GitHub TestFlight delivery — 2026-10-24

## Authorization and scope

The owner explicitly authorized autonomous fixes and repeated standard GitHub Actions runs for the current ATMA browser build until delivery to TestFlight. This supersedes the earlier per-run confirmation requirement for this delivery. It does not authorize a public App Store review submission, paid runner upgrades, or changes to other applications.

## Physical-device startup failure after upload

Build 9 reached TestFlight but the owner reported `ATMA UI could not start. Bundled UI index.html is missing.` on a physical iPhone. The IPA contains BrowserUI/index.html; canonical-path indexing is being repaired. Build 9 must not be treated as a successful physical-device startup. See `docs/superpowers/plans/2026-10-24-resource-path-fix.md` for the reproduced failure, repair and replacement build status.

## Uploaded build 9

- App: ATMA, App Store Connect ID `6774934498`, bundle `ru.atma.app`.
- Version: **1.0.0 (9)**, minimum iOS 17.0, iPhone and iPad.
- Apple build ID: `11f0c4f7-50e8-4236-b513-432bfa561f52`.
- Exact tested and archived source: `900b142ca7552d25ba4e26da5817e7a36e23f3da`. Later branch commit `5419555` changes documentation only.
- Native verification: https://github.com/rebmx4/vatma-ios/actions/runs/40041415024 — success.
- Signing and upload: https://github.com/rebmx4/vatma-ios/actions/runs/40043499179 — success.
- TestFlight: https://appstoreconnect.apple.com/apps/6774934498/testflight/ios/11f0c4f7-50e8-4236-b513-432bfa561f52

## Verified

- 24 native unit tests passed on iPhone 17 Pro simulator.
- Browser UI smoke passed on iPhone 17 Pro (130.347 seconds) and iPad Pro 13-inch M5 (94.831 seconds): Home, Settings, blank tab, address entry, keyboard/rotation, real HTTPS content and relaunch.
- Both Xcode simulator invocations ended with `TEST SUCCEEDED`. Results, screen recordings, screenshots, logs and verified source SHA are retained in the native artifact downloaded to D:.
- The signed workflow independently checked the native run success and its exact source SHA before using signing secrets. The same provenance gate was also run locally.
- Xcode archive and export succeeded; macOS CI verified code signing. IPA structure, bundle identity, build number, icons and 32 packaged source resources passed validation.
- Apple package validation reported no errors; upload ended with `UPLOAD SUCCEEDED with no errors` at 2026-10-24 00:12:44 UTC.
- Apple processing completed: `VALID`, `expired=false`; internal state `IN_BETA_TESTING`, external state `READY_FOR_BETA_SUBMISSION` (not submitted).
- The internal group `Test` contains validated build 9. The browser showed build 9 under version 1.0.0.
- TestFlight Russian description and beta review notes now describe the browser. An ATMA demo account is not required; existing review contacts were preserved.
- Build 9 Russian What to Test text was saved and read back successfully.
- No new tester invitations were sent. The owner subsequently installed build 9 through TestFlight and reported the startup failure recorded above; the earlier invitation status is historical.

## Local artifacts on D:

- IPA: `out/signed-40043499179/ipa/ATMA.ipa` (23,743,124 bytes).
- IPA SHA-256: `e0f29f72d0438d540237c7379c368ca5901eea76da5d73459796339fc8d2f9ee`.
- Signed archive: `out/atma-signed-40043499179.zip`.
- Native evidence: `out/atma-native-40041415024.zip`; selected evidence extracted into `out/native-40041415024/`.
- Full job logs: `out/github-native-40041415024.log` and `out/github-signed-40043499179.log`.

## Limits and remaining user steps

Build 9 is superseded by its confirmed physical-device startup failure and must not be recommended for installation. A corrected replacement is being checked under the linked repair plan. A public App Store release and external beta review were not submitted. Physical startup, website account sign-in, media playback and background audio must be checked on the replacement; simulator success is not evidence for every website or real-device behavior.

No Codemagic cloud build was started during this delivery. GitHub used standard hosted macOS runners in the existing public repository; no paid runner or subscription upgrade was enabled.
