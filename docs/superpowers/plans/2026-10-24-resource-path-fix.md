# Resource path repair after TestFlight build 9

## Scope

The physical iPhone shows `Bundled UI index.html is missing` although the IPA contains BrowserUI/index.html. Deliver a corrected TestFlight build, retaining path traversal and symlink protection. Owner authorized autonomous fixes and builds.

## Steps

1. Extract the existing resource enumeration unchanged into the production resourceIndex function and add a macOS integration regression using an actual container symlink. Run it in CI prepare before simulator tests; expect the missing-index failure with the original path comparison.
2. Canonicalize the root and enumerated file URLs consistently; keep child symlinks excluded. Confirm the same regression passes. Switch simulator checks to Release with testability enabled only for the test build, and run iPhone unit/UI plus iPad UI.
3. Obtain a fresh independent review, sign and upload the exact successful source SHA, and verify TestFlight processing.

## Review focus

- Real device aliases (/var versus /private/var) must not cause valid bundled resources to disappear.
- Canonicalization must not allow symlink escapes or unsafe relative paths.
- The regression must execute production indexing, not a copied implementation.
- Release UI checks and exact-source signing gate must remain required.

## Ledger

- Base: 3a75850. Branch atma-browser-testflight is an existing isolated worktree on D:.
- Test written before behavior fix. Mechanical extraction preserves the failing indexing algorithm so a fast host-native test can prove the defect before another simulator run.
- Build 9 reached internal TestFlight but failed startup on the owner's physical iPhone. Its earlier delivery status is superseded by this report.

- RED confirmed: GitHub native run 40044862013 compiled the actual production indexer and failed before simulator startup with `FAIL: Bundled UI index.html is missing.` (log: out/resource-alias-red-40044862013.log).
- Release command regression also failed locally because the real smoke command used Debug. Both causes are now being corrected before the full native run.

- Canonical root fixed index lookup, but CI 40045078408 still failed the nested-resource/security fixture. Diagnostic CI 40045235850 showed only ["index.html"], omitting assets/app.js.
- Apple FileManager URL enumerator documentation states it does not recurse through symbolic links; skipDescendants targets the last obtained subdirectory. Removed that call from the symlink-file branch while preserving explicit exclusion and canonical containment. Fixture now covers external file and directory symlinks.
- Fresh independent review: Critical 0, Important 1 (runtime regression still failing at review time), Minor 0. This finding remains gated on the next full green run.
- Final: Ruling: physical-device behavior requires owner retest of the next TestFlight build — this Windows session cannot drive the owner's iPhone — a remaining device-only defect could still require another build.
- Final: Ruling: full Release simulator and host regression success remain mandatory before signing — no source-only conclusion substitutes for runtime results — failed checks block upload.
- Final: Ruling: directory symlinks are explicitly included in the fixture after review — Foundation's documented non-recursion and containment guard are both retained — wrong enumeration assumptions would fail the fixture.
- Final: Ruling: post-index filesystem mutation is outside this repair because the resource source is the signed immutable app bundle — no dynamic filesystem content is served — a different mutable resource source would need a new design.

- GREEN host regression confirmed in CI 40045408456: `PASS: UI resources load through a container symlink; child symlinks remain excluded`. 20 Python checks, JavaScript suite and static validation passed in prepare.
- Required Release iPhone/iPad run: https://github.com/rebmx4/vatma-ios/actions/runs/40045408456, exact source f5857fad5d3d1ee00d0a58bf4842eb6f472493ca. Still running; signing remains gated on its successful completion and artifact SHA.

- Release run 40045408456: host alias regression PASS and native unit suite passed; UI failed after landscape rotation because Keyboard.exists became false. Video frame out/native-40045408456/rotation-release-45s.png confirms a closed keyboard, not an observed geometry violation.
- Ruling: the geometry scenario explicitly taps the address field after each rotation to establish an open keyboard before asserting all existing bounds, hit-testing and exact typed URL checks — rotation focus persistence is not the contract of this geometry test — uninterrupted typing across rotation remains a separate behavior to assess on a physical device. No production UI code changed for this finding.
- Added failure screenshot and accessibility hierarchy to the geometry assertion to diagnose any subsequent failure directly.

- Release retry 40046660427 again failed the 5-second geometry wait. Its failure snapshot/hierarchy show portrait UI bounds (0,62,402,409), address (59,335,276,51), Go (344,346,29,29), input-assistant toolbar at y=481 and an open keyboard. Controls are visibly within bounds in the later failure snapshot; stale accessibility queries or delayed settling remain possible.
- Ruling: re-query accessibility controls after rotation and on each predicate poll, wait up to 20 seconds for the identical geometry/hittability conditions, and log the exact last predicate observation if unsuccessful — this accommodates delayed CI snapshots while preserving the pass criteria — it does not establish real-device rotation focus persistence or physical-device performance.
- The simulator build compiled unused architectures in Release. Added ONLY_ACTIVE_ARCH=YES only to simulator tests, with a real-script command regression first observed failing then restored; device archive flags remain unchanged.

- Current required native run: https://github.com/rebmx4/vatma-ios/actions/runs/40048326485 (job 120735046536), dispatched 2026-10-24 01:07:17 UTC. Exact revision 390fd6568c157f770227b82e1fb1cc1c386060f0. No signing run for this repair has started.
- If this run fails, read `Address/keyboard check failed:` in its job log first; it prints exact last presence, frames and hittability values. All geometry checks are unchanged; only query refreshing and bounded settling time changed.

- Run 40048326485: iPhone entire suite passed (UI 141.467 s); iPad geometry checks passed in both orientations but immediate post-typeText value read returned h. Video frame out/native-40048326485/ipad-input-97s.png shows the full exact URL already present by the failure time. Input handlers do not truncate text.
- Ruling: poll a fresh accessibility query for the exact full URL for up to 20 seconds instead of comparing an immediate cached value after synthetic typing — actual recording confirms complete input while the earlier snapshot was partial — an actual wrong/missing URL still fails and blocks signing. Production input code is unchanged.

- Current run after exact-address synchronization: https://github.com/rebmx4/vatma-ios/actions/runs/40050119695, job 120740709257, exact source 2e46d7cea91e7ebbf1d210b47cfdd2397f4d0897. Dispatched 2026-10-24 01:30:37 UTC. Signing/upload of the repair has not started; build 9 is still the latest uploaded build.

- Run 40050119695: host regression, 24 native tests and iPhone UI (140.475 s) passed. iPad landscape failed with per-query address/Go frames (0,0,0,0), although its full hierarchy immediately afterward reports address (440,398,488,51), Go (937,409,29,29), UI (0,32,1376,502), keyboard y=589. Failure screenshot confirms visible controls above the keyboard.
- Ruling: use the public XCUIElement.snapshot() API to read geometry and input values from a coherent full accessibility snapshot; retain all bounds, hittability, exact URL and real navigation requirements. No speculative production layout change. Snapshot errors and wrong geometry still fail the required run.

- Coherent snapshot run: https://github.com/rebmx4/vatma-ios/actions/runs/40052265511 (job 120747300921), source f0c199a529e3ba0e6644c3a641e17795b7ad501d. Signing remains blocked until all native Release checks pass.

- Run 40052265511: iPhone UI passed (95.082 s); iPad full snapshots have correct control frames, but a redundant post-rotation tap opens the system Paste/Autofill edit menu (visible in screenshot and separate accessibility window), making both controls non-hittable. A zero-size toolbar snapshot also incorrectly reduced keyboardTop to 0.
- Ruling: after rotation, re-focus only if the address field lacks focus or the keyboard is not visible; do not reopen a blocking edit menu on an already focused field. Keyboard/accessory geometry must use nonempty frames intersecting the application bounds. All existing control bounds, exact input, hit testing and HTTPS navigation checks remain mandatory. Production app source is unchanged.

- Focus-precondition run: https://github.com/rebmx4/vatma-ios/actions/runs/40053616669, source 810347e58a41206c96fac6fd3877e6752365bc8d. Required full Release run; no replacement upload has started.

- Run 40053616669 stopped at the iPhone landscape geometry assertion because the new visible-frame filter used the application snapshot frame. The hierarchy has no application-level frame, while Window (Main), atma.ui and Keyboard all have valid frames. Corrected the helper to use the main window frame consistently; keyboard and accessory filtering still requires positive intersecting frames. The focus/edit-menu correction remains in place. No production code changed.

- Main-window measurement run: https://github.com/rebmx4/vatma-ios/actions/runs/40054379296, job 120753988713, source 2153659c0e0763eeac38b2048a9c602148a76955. Required Release checks remain the upload gate.

- Run 40054379296: all 24 native tests and iPhone UI (71.679 s) passed; iPad landscape failed. No redundant post-rotation tap or edit menu is present. Application snapshot returned keyboard frame (3,0,440,1376), while the full debug hierarchy normalizes it to (0,589,1376,440). UI control frames remain correct. System keyboard/accessory frames now come from their own element queries; bundled WebKit control frames still share one snapshot, and hittability checks are retained.
- The same log confirms SDK 26.4.1 was paired with runtime 26.5 by the previous latest-version selector. Installed runtime 26.4.1 is available. CI now requires the active SDK major/minor runtime, with no silent fallback, and runs iPad first while retaining full iPhone tests and the final SHA marker after both pass.
- Selector regressions were red before implementation (3 errors); real CI-script regressions were red for wrong runtime/order. All 23 Python tests now pass, including short-circuit failure handling and provenance gates. Bash syntax and git diff checks pass. Production app source remains unchanged since f5857fa.

- SDK-matched run: https://github.com/rebmx4/vatma-ios/actions/runs/40056150273, job 120759470143, source 06460b63487782c76596ca4ff2bf8e947851c10c. iPad UI runs first, then all iPhone native/UI tests. Signing remains blocked until full success.

- Run 40056150273 selected iOS 26.4.1 successfully but failed Swift compilation before any UI test: one focus-helper call still passed an XCUIElementSnapshot after hasVisibleFrame changed to take CGRect. Corrected that call to $0.frame and audited all three call sites. No production code changed; all 23 Python checks and shell checks remain valid for unchanged files.

- SDK-matched frame-call retry: https://github.com/rebmx4/vatma-ios/actions/runs/40056752812, job 120761302357, source 32ee46c58763c1e39a3e980f24cf381005afc566. Full success remains mandatory for signing.

- Run 40056752812 compiled on iOS 26.4.1 but failed before Home appeared. Recording frame out/native-40056752812/ipad-home-60s.png shows a genuinely blank white WebKit surface. Accessibility hierarchy includes atma.ui and no missing-index label. Added test-launch-argument-gated server HTTP/read diagnostics, WebKit response/error/DOM diagnostics and simulator unified log capture. Default app behavior is unchanged; no further speculative behavioral fix is applied.

- Startup diagnostic run: https://github.com/rebmx4/vatma-ios/actions/runs/40058059906, job 120765338284, source 2aa3065ebb8f21c35abb313bd301789ab4182304. Diagnostic launch flag is test-only; full native gate remains required.

- Run 40058059906: iPad passed Home, Settings, blank tab, both rotation/keyboard bounds and exact URL input. It created the site renderer but did not see the HTTPS fixture heading within 30 seconds. Runtime log proves index/CSS/JS all HTTP 200 with correct MIME, DOM ready=complete, mode=home and no JavaScript errors. No site load completion/error was previously logged, so the next run adds site response/TLS/navigation diagnostics, waits up to 60 seconds for the same required heading, and relaunches with diagnostics disabled before final Home assertions. httpbingo remains the fixture; example.com explicitly discourages monitoring/testing use.

- Site/TLS diagnostic run: https://github.com/rebmx4/vatma-ios/actions/runs/40059398937, job 120769415567, source e7bb3a84aefd37c5952b6ec430cdce44b3e77edd. Exact heading and default-mode relaunch remain required.

- Run 40059398937 failed initial Home at 20 seconds. Independent reviewer confirmed all 4788 response bytes (173 header + 4615 body) were sent without retransmission; the 5-second deadline fired after connection closure. WebKit received HTTP 200 but had no commit/subresource request by failure. No proven transport/layout defect; do not change cancellation or timeouts on speculation.
- Review ruling: preserve the 20-second pass criterion and, only after failure, observe the live app up to 60 seconds with screenshots/hierarchies and capture WebKit processes as well as ATMA. Late appearance remains a failed original check. This distinguishes a delayed cold commit from persistent loading.
- Review ruling: independent native presentation for UI navigation errors is a real pre-existing gap, but no error callback occurred in this run; keep it separate from the current causal diagnosis. Default cold startup still needs coverage; the existing unflagged final relaunch does not establish a cold start.
- Local verification after diagnostic-only changes: all 23 Python checks passed, Bash syntax and git diff checks passed. Production behavior unchanged.

- Bounded observation run: https://github.com/rebmx4/vatma-ios/actions/runs/40061792023, job 120776689824, source 5d12c6b0bb3b6eae9707a4d9160ab177e79628ef. Both full Release checks remain required; build 9 remains the last upload.

- GREEN: run 40061792023 completed success. iPad UI 108.018s, all 24 iPhone native tests and iPhone UI 45.399s passed in Release. Both logs contain TEST SUCCEEDED; exact artifact marker 5d12c6b0bb3b6eae9707a4d9160ab177e79628ef passed the local provenance gate. Full 202519763-byte native artifact saved and extracted on D:. Signing/upload dispatched for precisely this SHA and verified run; no new behavior patch for the intermittent prior WebKit stall.

- Signed run 40063005602 completed success, package validation reported no errors and upload ended UPLOAD SUCCEEDED with no errors at 04:40:29 UTC. Build number 10. IPA saved on D: (23753218 bytes), SHA-256 8911b4c156c50c173b7e8a8e4d2db75dd34f2d85ffc814a041b1c445ce26118c. Local byte validation initially compared Windows CRLF files; every difference was solely CRLF. Repeated against a Git archive of the exact tested SHA with core.autocrlf=false/core.eol=lf: all 32 packaged resources, identity, icons and structure passed without changing the verifier or application.

- DELIVERED internally: build 1.0.0 (10), Apple ID ca77c910-e9f1-4b20-832a-45456500da15, VALID/not expired, IN_BETA_TESTING; existing Test group contains it. Russian What to Test saved/read back. Owner physical retest requested; no physical success claimed. Final report: docs/resource-path-fix-2026-10-24.md.
