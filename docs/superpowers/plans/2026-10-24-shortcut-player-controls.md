# Shortcut and player controls implementation plan

> For agentic workers: use superpowers:executing-plans inline. Owner approved the chat plan with «старт» on 2026-10-24.

**Goal:** Remove the bottom media shortcut, always show the compact saved-app toolbar, restore each shortcut's existing profile without a launch chooser, and stop unrequested hidden playback while preserving intentional playback on screen lock.

**Architecture:** Existing Swift/WebKit shell and bundled JavaScript. Persistent profile data stores remain the source of cookies. The page media adapter owns user intent and PiP exit; native code supplies actual renderer visibility and lock state.

**Spec:** Approved conversation plan, including latest exception: intentional visible-player playback continues when the phone screen is locked.

## Global constraints
- Work, temporary files, caches and outputs only on D:.
- Preserve owner file docs/superpowers/plans/task-1-review.patch.
- No paid Codemagic runs. Existing internal TestFlight group Test only.
- Exact-revision native iPhone/iPad gate before signing and upload.
- Never discard profile cookies or invent notification counts.

## Tasks
### Task 1: Playback intent and hidden-player lifecycle
Files: BrowserUI/assets/site-media.js, BrowserNative/BrowserMediaController.swift, BrowserNative/BrowserController.swift, tests/site-media.test.mjs, BrowserNativeTests/BrowserRenderingTests.swift.
- [ ] Reproduce autoplay, hidden renderer and PiP-exit resume in executable adapter tests.
- [ ] Track explicit play intent; pause/revoke on hidden presentation exit and reject automatic restarts.
- [ ] Feed renderer visibility and screen-lock state from native lifecycle. Keep AVAudioSession playback category and intentional lock/background playback.
- [ ] Verify targeted JavaScript and actual WebKit fixture playback.
### Task 2: Saved profiles and compact toolbar
Files: BrowserNative/BrowserShortcutProfiles.swift (new), BrowserNative/BrowserModels.swift, BrowserNative/BrowserRPC.swift, BrowserNative/BrowserController.swift, BrowserUI/app.js, BrowserUI/index.html, BrowserUI/app.css; existing native rendering/UI tests.
- [ ] Resolve unbound legacy shortcuts against existing profile stores and matching site tabs; persist the chosen profile before launch. No launch chooser.
- [ ] Keep pinned profiles and cookies independent of the normal browser's model choice.
- [ ] Remove bottom media and app-collapse buttons and JavaScript references. Saved app always has Back, Forward, Address/Reload, ATMA Home at right; normal device-row collapse remains.
- [ ] Verify real quick-add/legacy launch/cookies and iPhone/iPad physical-bottom toolbar.
### Task 3: Notification feasibility and delivery
- [ ] Confirm supported notification delivery for requested sites. Apple DTS says Web Push is unavailable in WKWebView; native APNs needs an event source. Await concrete sites; do not ship a decorative enable switch.
- [ ] Run existing Python/JS/static checks, fresh review of complete diff, full native gate.
- [ ] Only after exact-source native gate passes: sign, validate IPA and deliver to existing internal TestFlight Test. Record any unsupported notification scope and device-only validation remaining.

## Review focus
- Paused/closed PiP must not restart while hidden; explicit Play must restore it.
- Screen lock must not revoke intentional playback.
- Legacy profile lookup must never delete/move cookies and must validate website URLs/profiles.
- Fixed compact toolbar must retain keyboard dismissal and physical bottom alignment.
- Multiple saved accounts: avoid opening an arbitrary profile; resolution preference must be recorded.

## Progress
- Base: 2057e50bbf099785329e7666dadeaeb9af1b7bd1, linked worktree at D:/Projects/atma-browser-ios.
- Baseline: existing three site-media tests pass.
- Pre-flight: native footerHeight and CSS must change together; native media API and injected adapter must change together.
- Notification delivery remains a feasibility task until a supported event source is confirmed; no universal Web Push promised.

- JavaScript: 26/26 pass, including baseline failures reproduced then fixed for unrequested playback, hidden PiP and legacy chooser. Python: 23/23 pass. Static source validation: 266 files pass.
- Ruling: ambiguous legacy accounts are not guessed; the owner can select the desired existing session in normal browsing, then re-open the shortcut. No website data is deleted. Cost if wrong: an extra normal-browser visit for ambiguous old shortcuts.
- Ruling: new unvisited legacy/default shortcuts use actual-device rather than the currently selected unrelated model; the chosen profile is persisted once.
- System PiP edge-stashing has no exposed visibility event in the WKWebView adapter; closure/exit and renderer visibility are covered, actual device behavior remains to be checked.

- Final review 8e8ad39: four Important issues. Fix pass covers ambiguous current cookie profiles, pause→scripted resume, zero-size custom audio, and new-document visibility. Two new JS regressions were observed RED then GREEN; native profile/document regression cases are included in the forthcoming macOS gate.
- Ruling: programmatic HTMLMediaElement.play() is gated separately so a true native PiP transport Play can work without a document click. Native transport and real lock event order still require owner-device retest; protected-data availability is not a guaranteed screen-lock signal.
- No Critical findings and no deferred Minor findings from independent review.
