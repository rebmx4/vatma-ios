# ATMA startup repair — TestFlight build 10

Build **1.0.0 (10)** is processed and available to the existing internal TestFlight group **Test**. Physical iPhone retest is pending; the owner was asked to update from build 9.

## Change and reproduced cause

Build 9 was uploaded successfully but failed on the owner's iPhone with `Bundled UI index.html is missing`. Its IPA contained the file. The production indexer compared an unresolved bundle root with symlink-resolved child paths, so iOS container aliases could reject valid resources. The root and file URLs now use the same canonicalization. Child symlinks remain excluded and canonical containment remains required.

The regression compiles the actual production indexer, uses a real container-directory symlink, reads a nested asset and excludes external file/directory symlinks. It first failed with the original code. A second defect was reproduced: calling `skipDescendants` on a symlink file skipped a real directory. Removing that call restored nested assets without traversing symlinks.

## Exact source and checks

- Tested and archived source: `5d12c6b0bb3b6eae9707a4d9160ab177e79628ef`.
- [Native Release verification](https://github.com/rebmx4/vatma-ios/actions/runs/40061792023): success. iPad UI 108.018 seconds; 24 iPhone native tests and iPhone UI 45.399 seconds; both commands ended `TEST SUCCEEDED`.
- UI checks retain Home, Settings, a blank tab without a site renderer, exact address input, portrait/landscape keyboard bounds and hit testing, real HTTPS content and relaunch. Final relaunch removes the diagnostic launch argument.
- Production resource-alias regression, 23 Python checks, JavaScript checks and source validation passed. SDK/runtime selection requires matching major/minor; iPad runs first, then the entire iPhone suite.
- The downloaded native artifact SHA marker passed the independent local provenance gate. The signing workflow also required the same successful run and exact SHA.
- [Signing/upload](https://github.com/rebmx4/vatma-ios/actions/runs/40063005602): archive/export and code-signature checks passed. IPA identity, icons, structure and all 32 source resources passed. Apple package validation reported no errors; upload ended `UPLOAD SUCCEEDED with no errors` at 04:40:29 UTC.
- Local byte verification also passed against an LF Git archive of the exact SHA. Windows `core.autocrlf=true` had initially produced CRLF-only differences; the verifier and application were not changed to ignore mismatches.

## Apple availability

- App `6774934498`, bundle `ru.atma.app`; same existing application.
- Apple build ID `ca77c910-e9f1-4b20-832a-45456500da15`.
- Checked 2026-10-24 04:47 UTC: `VALID`, not expired, encryption declaration present, internal state `IN_BETA_TESTING`.
- Existing internal group Test contains build 10. Russian What to Test instructions were saved and read back.
- [Build in App Store Connect](https://appstoreconnect.apple.com/apps/6774934498/testflight/ios/ca77c910-e9f1-4b20-832a-45456500da15).

## Evidence on D:

- IPA: `out/signed-40063005602/ipa/ATMA.ipa`, **23,753,218 bytes**.
- SHA-256: `8911b4c156c50c173b7e8a8e4d2db75dd34f2d85ffc814a041b1c445ce26118c`.
- Full native evidence: `out/atma-native-40061792023.zip`; extracted `out/native-40061792023/` includes logs, recordings, screenshots and xcresults.
- Signed evidence: `out/atma-signed-40063005602.zip`; extracted `out/signed-40063005602/`.
- Apple status/readback: `out/apple-build-10-status.json`. Final app screenshots: `out/native-40061792023/iphone-app-relaunched.png` and `ipad-app-relaunched.png`.

## Limits and review rulings

Physical launch on the owner's iPhone, website sign-in/session retention, media playback and background audio remain to be checked on build 10. Simulator success does not establish those device results. Initial UI-test launch used test-only diagnostics; default behavior was checked on final relaunch.

A previous CI run stalled between HTTP response and WebKit commit. Independent review proved the full response was sent, with no evidence for a truncated response or the five-second server deadline as its cause. The final run passed the original 20-second Home criterion; late diagnostic observation cannot convert a failed criterion into success. No speculative transport/layout behavior change was made for the earlier stall, whose cause remains unconfirmed.

Review also identified an existing gap: a UI WebKit navigation-error callback sets `nativeError` without an independent native error view. It did not occur in the diagnosed stall and is outside the canonical-resource repair; it remains a known follow-up rather than a claimed fix.

No public App Store submission or external beta review was sent. No new tester invitation, Codemagic cloud build, paid runner or subscription upgrade was initiated for this repair.
