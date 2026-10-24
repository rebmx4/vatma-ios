# ATMA App Store release preparation

> For agentic workers: execute inline with superpowers:executing-plans. Owner requested complete preparation for a public, entirely free app.

**Goal:** Prepare the current standalone ATMA browser, accurate metadata, real device-sized screenshots and required privacy/support information for App Store review.

**Architecture:** Keep the existing UIKit/WebKit app, pinned profiles and media controls. Share one legal-content source between the bundled UI and static support pages. Use real native simulator captures rather than invented screenshots.

**Tech stack:** Existing Swift/WebKit and bundled JavaScript; Python stdlib for reproducible store assets; App Store Connect API; existing GitHub macOS workflows.

## Constraints
- All work and outputs only on D:. Preserve owner file docs/superpowers/plans/task-1-review.patch.
- Price zero; no ATMA IAP, subscriptions or new advertising/analytics SDKs.
- Existing app 6774934498 / ru.atma.app. Preserve the existing app record; do not bypass its rejection using a duplicate.
- Owner explicitly chose a first public build without ad blocking. Remove actual native filtering, website filtering scripts, UI/RPC and payloads; retain media controls. Previous source is preserved by pushed tag atma-with-ad-blocking-20261024 at 30a936e912fa874dc56e73c9d77a47a72970d650.
- Actual public support/privacy URLs must work and describe this browser. Existing vatma.ru privacy describes the former astrology/dating product and must not be reused for the browser.
- New product-source changes require exact-revision iPhone/iPad gate and IPA validation before uploading a replacement build.
- No claim of guaranteed App Store acceptance or physical-device verification.

## Tasks
- [x] Inspect current app/version, price, IAP/subscriptions, age declaration, old screenshots and bundled data paths.
- [x] Add accessible in-app policy/support with one source of legal text and publish matching static pages.
- [ ] Capture and inspect real iPhone 6.9-inch and iPad 13-inch screenshots in the required opaque sizes.
- [ ] Populate RU/EN metadata, correct age declaration and verify support/privacy/category/free pricing. Attach the verified current binary, replacing old astrology screenshots.
- [ ] Prepare specific review notes covering the changed product and real browser capabilities; inspect previous rejection messages when browser authentication permits.
- [ ] Report remaining factual blockers, including legal declarations or account UI that cannot be completed through the API.

## Findings at initial inspection
- Existing release source:7b019ea298b01d4ad1a25dddfde6fa9495983d9b, build1.0.0 (12), beta APPROVED in Test1.
- The current subtitle is still astrology-related. Age declaration incorrectly says unrestrictedWebAccess=false and ageAssurance=true.
- All175 regional price points are zero. No IAP products or subscription groups exist.
- Old screenshots still date from May. Existing native check captures are iPhone17Pro1206x2622 and do not satisfy the required 6.9/6.5-inch slot by themselves.
- Bundled PrivacyInfo is present; no analytics/payment SDK found. No in-app privacy link found. Public policy currently describes birth dates, dating and AI messages.
- Browser login expired during inspection; API key remains functional. Chrome is shared with other work, so do not type into unrelated active tabs.

Recommended implementation model: GPT-6.1-sol, high; reason: native/browser behavior, privacy declarations and store metadata must agree.

## Follow-up rulings and evidence
- Fresh review found two Important issues, corrected: saved-shortcut screenshot selector must use the real document title; descriptions must not promise unsupported history/bookmark interfaces.
- Initial home state incorrectly selected an empty tab surface. Reproduced with the actual consume() code (RED), fixed, 2/2 regression tests GREEN. Later blank tabs remain blank.
- Native run 40111433136: iPad browser smoke passed; screenshot test reached real home/profile/appearance/compact captures, then failed because the compact app intentionally has no New Tab button. Corrected the test to return Home before opening another tab. iPhone was not run after that mandatory failure.
- Add explicit confirmation for visible-page links to external applications; executable/local URL schemes remain blocked from external launch. Native tests and mail-link cancel UI check added; final CI pending.
- Owner instructed all public information to describe the browser only. Removed the previous product reference from public and bundled policy. Old screenshot representations backed up before replacement.
- Owner decision received: first release genuinely excludes ad blocking. Both filtering mechanisms, payloads, UI/RPC and claims removed. New JavaScript regression leaves website advertising JSON intact. A native simulated YouTube-origin check covers injected scripts and visible ad elements.
- Required account access pending: Apple web login for App Privacy, regional declarations and the previous review conversation. API metadata editing works.

## No-blocking release validation
- Native run 40112969940 failed its iPad browser smoke check when a saved shortcut tap did not open the compact view; StoreScreenshotsTests passed, including external-mail confirmation/cancel. iPhone was not run after this failure. No signing is authorized from this failed gate.
- Asynchronous icon completion previously called saveApps(), rebuilding desktop and folder buttons during touch. Reproduced in both public/private regressions, then fixed by persisting icon-only changes without replacing the grid. PIN/vault persistence stays in the same save path. Smoke waits for a hittable saved shortcut and its compact-view outcome.
- Local checks after removal and icon fix: 42 JavaScript tests, 24 Python tests, 269-file static validation, generated support-site check, JavaScript syntax and git diff check passed. Native iPhone/iPad execution remains required.
- Four real iPad screenshots are COMPLETE in Apple; old seven screenshots and the old selected June binary were removed from the current version. RU/EN metadata, free pricing, browser age declaration and no-demo-account review notes prepared.
