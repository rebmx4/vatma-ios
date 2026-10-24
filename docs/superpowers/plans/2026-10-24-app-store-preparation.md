# ATMA App Store release preparation

> For agentic workers: execute inline with superpowers:executing-plans. Owner requested complete preparation for a public, entirely free app.

**Goal:** Prepare the current standalone ATMA browser, accurate metadata, real device-sized screenshots and required privacy/support information for App Store review.

**Architecture:** Keep the existing UIKit/WebKit app, pinned profiles and media controls. Share one legal-content source between the bundled UI and static support pages. Use real native simulator captures rather than invented screenshots.

**Tech stack:** Existing Swift/WebKit and bundled JavaScript; Python stdlib for reproducible store assets; App Store Connect API; existing GitHub macOS workflows.

## Constraints
- All work and outputs only on D:. Preserve owner file docs/superpowers/plans/task-1-review.patch.
- Price zero; no ATMA IAP, subscriptions or new advertising/analytics SDKs.
- Existing app 6774934498 / ru.atma.app. Preserve the existing app record; do not bypass its rejection using a duplicate.
- Do not delete media/ad-blocking features solely on the earlier unsupported claim that special scripts imply an Apple ban. Brave's public iOS rules contain comparable site-specific filters; YouTube ToS risk remains disclosed. No such source change is authorized by silence.
- Actual public support/privacy URLs must work and describe this browser. Existing vatma.ru privacy describes the former astrology/dating product and must not be reused for the browser.
- New product-source changes require exact-revision iPhone/iPad gate and IPA validation before uploading a replacement build.
- No claim of guaranteed App Store acceptance or physical-device verification.

## Tasks
- [x] Inspect current app/version, price, IAP/subscriptions, age declaration, old screenshots and bundled data paths.
- [ ] Add accessible in-app policy/support with one source of legal text and publish matching static pages.
- [ ] Capture and inspect real iPhone 6.9-inch and iPad 13-inch screenshots in the required opaque sizes.
- [ ] Populate RU/EN metadata, correct age declaration and verify support/privacy/category/free pricing. Attach the verified current binary, replacing old astrology screenshots.
- [ ] Prepare specific review notes covering the changed product and real browser capabilities; inspect previous rejection messages when browser authentication permits.
- [ ] Report remaining factual blockers, including legal declarations or account UI that cannot be completed through the API.

## Findings
- Existing release source:7b019ea298b01d4ad1a25dddfde6fa9495983d9b, build1.0.0 (12), beta APPROVED in Test1.
- The current subtitle is still astrology-related. Age declaration incorrectly says unrestrictedWebAccess=false and ageAssurance=true.
- All175 regional price points are zero. No IAP products or subscription groups exist.
- Old screenshots still date from May. Existing native check captures are iPhone17Pro1206x2622 and do not satisfy the required 6.9/6.5-inch slot by themselves.
- Bundled PrivacyInfo is present; no analytics/payment SDK found. No in-app privacy link found. Public policy currently describes birth dates, dating and AI messages.
- Browser login expired during inspection; API key remains functional. Chrome is shared with other work, so do not type into unrelated active tabs.

Recommended implementation model: GPT-6.1-sol, high; reason: native/browser behavior, privacy declarations and store metadata must agree.
