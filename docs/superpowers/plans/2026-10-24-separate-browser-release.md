# ATMA separate browser release

> Execute inline with superpowers:executing-plans. The owner explicitly requested the new app and continued creation on 2026-10-24.

**Goal:** Deliver and submit the free browser as app 6826668990 / ru.atma.browser, without device impersonation or ad blocking.

**Architecture:** Keep the current Swift/WebKit browser, shortcut desktop, tabs, media and ordinary downloads. Use the real device WebKit configuration and one persistent website session. Remove device catalogue, chooser and switching RPC entirely; saved shortcuts open directly with the same real-device session. Release identity must agree in Xcode, signing and IPA checks.

**Tech stack:** Existing Swift/UIKit/WebKit, bundled JavaScript, Python validation and GitHub standard macOS runners.

## Constraints
- All working files on D:. Preserve task-1-review.patch and the delivered build13 evidence.
- New App Store app ATMA (Russian name АТМА), SKU ATMA_BROWSER_IOS_001; primary locale ru. The old ru.atma.app card is not submitted or removed.
- No hidden or dormant switching feature, no claim of guaranteed approval. Later features go through a new openly documented review.
- Keep the entirely free app and current removal of ad blocking.
- Screenshots and public copy must match the actual new binary.

## Tasks
- [x] Register new bundle ru.atma.browser and create App Store record6826668990 in the owner’s open browser; read back API identity.
- [x] Remove catalogue, UA overrides, chooser/panel and switching API. Simplify website data and shortcut launch to actual-device session. Add targeted native/JavaScript regression cases for rejected switching, persisted tabs/shortcut login and standard WebKit.
- [x] Change app/test bundle identifiers and signing/upload identity coherently; validate first-build numbering for a new record. Test IPA/signing validation against new and old identifiers.
- [x] Update RU/EN metadata, common policy/support and screenshot scenario to remove device-profile claims. Generate matching support pages.
- [x] Run local checks, fresh independent code review and exact-source iPhone/iPad native gate. Only a green exact revision can be signed and uploaded.
- [x] Verify IPA resources/signature/identity, TestFlight processing and new group delivery. Capture and inspect current iPhone/iPad screenshots.
- [x] Populate new card including free price, age, privacy, review notes and actual screenshots; submit public review when all mandatory validation is satisfied. Report Apple state honestly.

## Review focus
- A legacy or forged profile identifier cannot change the UA or select an alternate data store.
- Saved shortcut login persists across ordinary tabs and application relaunch without a chooser.
- Smaller browser chrome leaves usable space with the device row removed, including keyboard dismissal and iPad.
- New app signing/provenance/IPA checks cannot accept the previous app ID accidentally.
- New app has no existing TestFlight build; first build numbering must resolve safely to1.

Рекомендуемая модель для реализации: GPT-6.1-Sol, уровень high. Причина: нужно согласовать поведение браузера, новую подпись и сведения публикации.

## Local implementation and review
- New app identity read back from Apple:6826668990 / ru.atma.browser / АТМА / ru / ATMA_BROWSER_IOS_001. Version1.0.0 and Utilities configured.
- Device catalogue27entries, UA overrides, chooser and switching RPC removed. All website stores normalize to one actual-device namespace; saved shortcuts launch directly.
- Targeted regressions observed RED then GREEN for direct shortcut launch, new/old app identity and excluded IPA catalogue.
- Fresh reviewer caught an overbroad listener removal before any native build. Restored all original footer/navigation/edit-dismiss handlers except the3device controls; actual handler scenarios went3RED→3GREEN. Minor PIN/About/cookie localization issues corrected. No remaining Critical/Important review finding.
- Final local checks:47JavaScript,25Python(previous result unchanged),267-file source validation, syntax, bilingual dynamic labels, generated11site files and git diff checks passed. Native Swift/iPhone/iPad execution remains pending.
- First-build lookup inspected in pinned codemagic-cli-tools0.70.0 source: successful no-build lookup returns no value, default to0 only after successful command; errors still stop the shell.

## First native gate and media correction
- Exact source7add3254a9b4701f124d456c39c5dac72000121c: native run40130058588 failed one playback case (2assertions in40unit tests). Both iPhone UI2/2 and iPad UI2/2 passed. No verified revision was produced; signing/upload did not start.
- Reproduced queued browser-guard pause cancelling a newer explicit Play. Guard pause tokens now preserve the newer intent, while real system/site pauses still revoke playback approval. Two meaningful event-queue regression cases added; native playback assertion strengthened from0.3to1.2seconds, with event diagnostics on failure.
- Read-only independent review found no Critical/Important/Minor issue and exercised additional queued interleavings.49JavaScript tests, source validation267files, changed-JavaScript syntax and diff checks passed; unchanged Python validation remains25/25. Full native gate must pass the corrected exact revision before signing.
- New app privacy label published (no collection), all175territories priced free, age/DSA/regional declarations inspected, RU/ENmetadata and beta review notes saved. Public support site9b5341ec68fe7e984c3ae6b0fac75ff9517b0c64 deployed and HTTP content verified. Current screenshots and binary remain pending.

## Second native gate and optional snapshot bound
- Exact source f8c365b209638da590373122a512b98e3128fc18: native run40133401944 passed iPad smoke but failed the iPad store capture scenario after tapping Home from a saved website. The website remained visible and New tab did not become available within15seconds; iPhone tests were not reached. No signing/upload started.
- BrowserRPC waits for an optional tab snapshot before Home/tab/panel transitions. The capture had no deadline. Added a1-second fallback, once-only callback draining and identity checks that prevent expired replies from completing a newer capture or storing a stale preview. The UI scenario and its assertions remain unchanged.
- Added native controlled-callback regressions for a snapshot that never replies, multiple waiting transitions, and an expired reply racing a newer successful capture. Native test execution is unavailable on Windows and remains pending the next exact-source gate; source validation267files and diff check pass.
- Independent review caught the new test override lacking the current MainActor/Sendable callback annotations; corrected both override and stored callback type to Apple’s documented signature. Final review has no open findings. The unbounded snapshot wait is a confirmed code risk; its connection to the observed iPad UI failure remains a hypothesis until the unchanged native scenario passes.

## Third native gate and ordered UI state
- Exact source b37f80e65b499aa9a574bc5c7bf1c973ec67d83b: run40135052091 compiled successfully. All42native unit tests passed, including the explicit Play>1.2seconds regression and both missing/late snapshot cases. iPad2/2UI passed; iPhone store capture passed. One iPhone smoke case failed because New tab was covered after closing Settings; AX evidence shows the Settings dialog and scrim still open. The overall gate failed and signing/upload remain stopped.
- Actual consume() regression reproduced a stale native push reopening a closed panel and undoing a newer tab/compact toolbar. Three local cases observed RED then GREEN. Native state snapshots now receive one monotonic sequence across reply/poll/push, and the UI rejects older or unsequenced snapshots once sequenced state is established. Existing action intent versions remain in place.
- Added a native sequence/immutable-panel-snapshot regression. The existing UI scenario remains unchanged. Diagnostic mode records the last navigation/panel command in the UI accessibility value to distinguish an unreceived tap from stale rendered state if it fails again.
- Local52JavaScript tests, changed JS syntax,267-file source validation and diff check passed. The connection between the observed native UI failure and the reproduced stale-push race is not yet directly proven; the next native run is still required.
- Final independent review found no open Critical/Important/Minor finding and reproduced8/8targeted state/home/footer tests. Native SDK compilation and the unchanged iPhone Close scenario remain required for this correction.

## First new-app submission completed
- The final application revision is a879df5306cd232616e6c1a17fc123565e7197cc; the icon follow-up is documented in2026-10-25-shortcut-icons.md. Native gate40141124891 and signed/upload run40142631653 passed. New app6826668990 contains VALID1.0.0(1), with34resources compared byte-for-byte against the tested source.
- All59JavaScript,46nativeunit and four device UI scenarios passed. Five iPhone and five iPad captures are COMPLETE in Apple. Owner internal TestFlight is available; external Test1 is waiting for beta review.
- Version and App Review submission are WAITING_FOR_REVIEW, with automatic release AFTER_APPROVAL. This is submission to Apple, not approval or public availability.
- Notifications remain a disclosed unsupported capability. The separate bundle does not import old-app website sessions automatically.
