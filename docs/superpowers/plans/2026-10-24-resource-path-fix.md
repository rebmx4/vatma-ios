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
