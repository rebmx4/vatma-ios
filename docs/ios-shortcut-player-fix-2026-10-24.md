# ATMA saved apps, icons and playback — 2026-10-24

Source: 7b019ea298b01d4ad1a25dddfde6fa9495983d9b
Native gate: https://github.com/rebmx4/vatma-ios/actions/runs/40101298503 — success.
Signed release: https://github.com/rebmx4/vatma-ios/actions/runs/40103146068 — success; build 1.0.0 (12) available in internal TestFlight group Test.

## Changed
- Removed the lower media shortcut. Saved apps keep a thin Back/Forward/Address/Reload/ATMA Home toolbar without a device row or collapse control. Ordinary browsing retains device-row collapse.
- New apps retain the creation profile and session. Existing unbound apps resolve matching tabs and cookie stores before opening, without a model chooser or moving/deleting cookies. Ambiguous old accounts require selecting the intended site session in ordinary browsing once.
- Hidden inline playback and closed hidden PiP are paused and revoked; scripted play cannot silently restart them. Actual page input or explicit Play authorizes initial playback. System PiP transport remains usable after user authorization. Intentional lock-screen playback is preserved in the implementation.
- Website icons use touch icons, manifests and favicons from the website itself, normalized to a durable 192px PNG. Manual creation, quick-add, old missing icons and folder miniatures share this logic. Failed lookups retry after a 10-second backoff or a real online event. A late response cannot modify a locked/reopened private vault.
- Quick-add rejects a loading or changed document, so navigation cannot save the preceding page under the new address/profile.

## Verified
- 44 JavaScript tests; 23 Python tests; standalone source/config/resource validation of 268 product files. Targeted regressions were observed failing before their fixes and passing afterward.
- Exact-source native run 40101298503: 40 native tests, plus one end-to-end UI scenario on each of iPhone and iPad, zero failures, Xcode 26.4.1 (17E202). Artifact 12563288239. The verified source marker matches the source above and the local release gate passes.
- Real WebKit cases cover manual manifest fallback, quick-add touch artwork, offline UI reload, folder miniature repair, slow-navigation rejection, existing profile cookies, actual video continuity, hidden-page pause and document visibility synchronization.
- Independent review found no Critical issues. Four Important findings in the original scope and two Important findings in the added icon scope were fixed and covered by regressions; no repeated review of the fix pass.

## Remaining and boundaries
- Physical iPhone verification is still required for YouTube/RUTUBE, native PiP Play/X/close, screen lock/unlock and background event ordering. Simulator/fixture success does not verify these device behaviors. Protected-data notifications are not an exact screen-lock signal, and WKWebView exposes no PiP edge-stash visibility event.
- Website notifications and per-app/total badges are not connected. Apple DTS confirms ordinary Web Push is unavailable in WKWebView: https://developer.apple.com/forums/thread/760767. Native APNs requires a concrete website event integration; the owner has not supplied priority sites. No decorative switch or fabricated count was added.
- The original item 2 was an incomplete sentence without an actionable defect; no behavior was invented for it.

## Delivery
Signed artifact 12564150292 downloaded to out/signed-40103146068/ipa/ATMA.ipa (23,832,350 bytes). SHA-256: c1b1f8d743be3a1cca1b8def36fcfef3b145816c0c89cc027bb48c661682f819. Local validation matches all 34 UI/certificate resources byte-for-byte against the exact-source archive above; macOS CI verified signing. Apple upload COMPLETE with no errors/warnings; build 2194a510-c5c1-4dd0-ab33-2972f5e5232f VALID, unexpired, usesNonExemptEncryption=false. Internal state IN_BETA_TESTING; membership in existing Test group read back. Russian release notes saved and read back exactly. Availability confirmed 2026-10-24T14:51:59.400Z.

## Owner phone access — Test1
Owner follow-up requested adding build 12 through the group add-build step while away from the computer. Existing installed phone testers are in external Test1 (33903aaa-30ca-42f7-9352-6dcbe72319a0); internal Test had only an invited tester, so internal availability alone did not establish access on the phone.

Build 12 was explicitly associated with existing Test1 and read back. Beta review submission was created and Apple approved it. External build state is IN_BETA_TESTING, autoNotifyEnabled=true. VALID/unexpired membership in Test1 confirmed 2026-10-24T15:02:13.265Z. No new build was needed. When checking access for these phone testers, verify Test1 membership and external IN_BETA_TESTING, rather than only internal Test availability.
