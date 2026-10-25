# ATMA privacy and navigation — approved 2026-10-25

Base: 261361668be4d157a6b7e6035eac9660718e8e65. Existing linked worktree: D:/Projects/atma-browser-ios.
User approved the complete chat plan with «Стартуй». Do not change the owner’s untracked task-1-review.patch.

## Tasks
1. Navigation: real WebKit back/forward availability; grey disabled arrows; Home glyph in saved-web-app compact toolbar.
2. Incognito: a permanent desktop system icon of a person wearing a hat; white start page titled Инкогнито with search/address input. Isolated nonpersistent website store, private tabs omitted from disk session/restoration, clear when the last private tab closes. Ordinary shortcuts retain ordinary saved sign-ins. Private popup windows inherit privacy. No device spoofing or ad blocker.
3. Desktop editing: long hold on background, icons and labels, including downloaded image icons. Prevent iOS image callout only within the desktop; cancel on scroll/pointer cancellation. Keep ordinary taps and dragging. Match iPhone timing after measurement; no unverified 2-second assertion.
4. Privacy and trust: preserve camera/mic consent, file uploads and mail links. Accurate in-app explanations, public source/version traceability, synthetic network checks, current README/store statements. Do not promise anonymity or collect visited-page information for developer analytics.
5. Notifications feasibility: verify authorized message-event and unread-count access for personal VK/Avito without message content. No AI, no message text logging/forwarding, no fake notification toggle. Generic notification У вас уведомление and summed badges are the target, not an existing capability. If access cannot meet privacy requirements, report the exact blocker rather than deploying another result.
6. Verify source, JavaScript, native iPhone/iPad; signed/TestFlight only from exact green source. Real phone camera/mic/social-account checks remain distinct. Refresh screenshots/metadata as needed; public release follows tests. Preserve the existing Apple submission until its state is checked.

## Deferred update
Device selection and ad blocking stay disabled in this release. Reintroduction requires accurate public descriptions and normal Apple review; no hidden post-review activation.

## Verification
Baseline reused: exact released source a879df5 passed native 46 unit + 4 UI; current tracked source unchanged except docs. Baseline JS: 59/59 passed in this session. New native privacy/history tests first, then observe failures on macOS before native implementation. JS changes use targeted RED→GREEN, then related suite. Final exact-SHA native gate and IPA resource check remain mandatory.

## Open facts
User iOS version is pending. Apple publishes no Home Screen edit delay in seconds. No notification backend or service integration exists. No additional paid service is authorized or purchased.

## Progress
- [ ] Navigation
- [ ] Incognito and ordinary/private separation
- [ ] Desktop gestures
- [ ] Privacy/trust documentation and checks
- [ ] Notification feasibility
- [ ] Native verification and test distribution
