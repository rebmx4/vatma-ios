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
