# GitHub Actions migration implementation plan

> **For agentic workers:** Use superpowers:executing-plans. Owner requested implementation directly; continue inline.

**Goal:** Move manual ATMA iPhone/iPad verification and a separately requested signed build to GitHub-hosted macOS.

**Architecture:** Reuse release/ci.sh and exact verified source SHA. Register only workflow files on main so workflow_dispatch is available; checkout the explicit source revision from atma-browser-testflight. Keep product code untouched.

**Tech Stack:** GitHub Actions JSON-compatible YAML, standard macos-26 ARM runner, Xcode 26.4.1, Python 3.12, existing Codemagic open-source CLI tools for Apple signing only.

**Spec:** Owner: “переходи на гитхаб”, “делай там”, “открой в браузере покажи что да как”. Existing rule: a separate direct owner command for each build and each publication.

## Global constraints

- Local files, new tools, caches and reports only on D:.
- Manual workflows only; no push, pull_request, schedule or workflow_run triggers.
- Standard public-repository runner; 30-minute timeout; artifacts retained one day.
- Keep ru.atma.app / GR3WB4Z646 / 6774934498 and all native/UI checks.
- No automatic TestFlight beta/App Store review submission. Binary upload requires an explicit workflow input.
- Never publish secret values; use encrypted repository secrets.

## Review focus

- Failed, foreign or wrong-workflow runs must not authorize signing.
- The verified artifact must match the exact source commit being archived.
- GitHub workflow SHA belongs to main; source SHA comes from checkout and verified-commit.txt.
- Both workflow files must exist on the default branch without merging old application sources.
- Missing signing credentials must fail before archive/upload.

## Task 1: Workflows and revision gate

Files: .github/workflows/atma-ios-check.yml, .github/workflows/atma-testflight.yml, release/github_ci.py, release/validate.py, tests/test_github_ci.py, README.md.

- [x] Add targeted tests for manual/cost boundaries and failed/foreign/mismatched verification runs; observe missing implementation failure.
- [x] Implement workflow validation and provenance gate; reuse prepare/smoke/gate/archive.
- [x] Validate with unittest, source validator, actionlint and git diff --check; do not run cloud builds.
- [x] Document launch instructions, actual public-repository billing and unverified native result.

## Task 2: Register and show GitHub

- [ ] Commit/push working branch; register the two checked workflow files only on main with a non-forced update.
- [ ] Migrate available signing credentials securely and identify any missing values without inventing them.
- [ ] Confirm Actions exposes both workflows and has no new run; show the native workflow page in Chrome.
- [ ] Independent final review; correct material findings, record verified state and remaining prerequisites.
