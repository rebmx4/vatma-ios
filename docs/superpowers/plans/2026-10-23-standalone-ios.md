# Standalone ATMA and Cookie Manager Implementation Plan

> For agentic workers: use subagent-driven-development or executing-plans;
> follow the user's minimal sufficient process, without another approval loop.

**Goal:** Remove the Brave build dependency and add inspectable, selectively
deletable cookie storage to Files while preserving downloaded media.

**Architecture:** Own UIKit/WKWebView browser with the existing shared ATMA UI.
Native message RPC owns website stores, navigation, cookies and downloads.
Preview keeps Electron solely as its Windows runtime and uses the same UI.

**Tech Stack:** Swift/UIKit/WebKit/Network/CryptoKit, JavaScript, XcodeGen.

**Spec:** `docs/standalone-ios.md`.

## Global Constraints

- All Windows writes, dependencies, temporary files and logs on D:.
- No Codemagic build, publication, push, paid service or Windows trust-store edit.
- Preserve user tabs, website renderer state, local settings, encrypted PIN data.
- Cookie values stay in the browser store and UI; never log or export them.
- No Brave/Chromium code, SDK or background service in the active iOS product.
- New source files below 400 lines; Apple runtime verification remains explicit.

## Review Focus

- Site content must never reach the privileged UI RPC handler.
- Same-name cookies on different domain/path must be deleted independently.
- Deleting cookie must preserve downloads, settings and other profile sessions.
- Local HTTP server must reject traversal and bind only loopback.
- CI must never fall back to the removed native core or publish failed checks.

### Task 1: Independent native browser

Files: create `BrowserNative/*.swift` and `BrowserNativeTests/*.swift` only.
Interface: own UI served from bundled `BrowserUI`, message handler `atma` with
reply, browser state/actions matching preview API. See task-1 brief for contract.

- [x] Implement native browser, stores, cookie API, downloads and TLS.
- [x] Add focused Swift tests and static source checks; report platform limits.
- [x] Review spec compliance and source quality before integration.

### Task 2: Shared UI and preview Cookie manager

Files: shared `BrowserUI`, preview `public` junction, cookie service/test modules,
preview server restoration support and Files Cookie UI.

- [x] Establish one UI source without changing live website renderers.
- [x] Test cookie identity/selection and implement list/delete scoped to profile.
- [x] Test real isolated cookies (including HttpOnly/path variants), not user data.
- [x] Verify phone/tablet preview UI and retention of existing tabs/settings.

### Task 3: Replace build pipeline and verify product boundary

Files: `project.yml`, `codemagic.yaml`, `release/ci.sh`, standalone validation,
asset packaging, smoke tests, README. Archive old Brave release path after a
local checkpoint; do not include it in targets or active workflow.

- [x] Baseline the forbidden dependencies, then require none in product inputs.
- [x] Prepare XcodeGen iPhone/iPad project spec and manual M2 build/test workflows.
- [x] Validate source/config, run focused tests and review the whole change.
- [x] Report changed/verified/remaining; do not claim an unrun iOS build passed.

## Deferred Apple verification

XcodeGen execution, Swift build, XCTest, native UI/TLS/cookie persistence/download
scenarios, OS icons/status bar and TestFlight remain unrun. Prepared CI requires
successful checks before publishing. No paid CI run, push or publication was
started; runtime work on Apple is deferred under the owner's cost constraint.
