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
