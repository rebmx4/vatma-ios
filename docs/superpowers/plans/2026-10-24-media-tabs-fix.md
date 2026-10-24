# ATMA media and tab-preview repair

Base: c95ad7d693b273e7c0b26a8ad3435059b3fc39ae. Build 10 was delivered internally. Owner screenshots show the running browser, paused PiP video and blank RUTUBE tab previews; exact installed build is not shown. Original reports preserved in out/media-tabs-20261024/.

## Scope

Reproduce video stopping after about one second on YouTube/RUTUBE and unstable blank tab previews; fix confirmed app causes, retain origin restrictions, run required Release verification and deliver the exact verified source as the next internal TestFlight build. Existing autonomous build authorization applies. No paid runners or external review.

## Investigation

- Media state reports call setCategory/setActive(true); an unavailable report/invalidation calls setActive(false). Native interruption callbacks also issue a JavaScript pause. Need a real playback regression before attributing the physical failure.
- Opening a panel schedules layout that hides every site renderer, then tab-previews snapshots those hidden renderers. No native snapshot cache exists.
- The UI compares JSON.stringify of native dictionaries and replaces every card on a perceived change. Equal dictionaries with different property order compare unequal. Need a stable-render regression and real WebKit preview check.

## Plan

1. Write narrow regressions for passive media state/playback and tab preview state/visibility; observe the intended failures.
2. Fix only the confirmed causes with one source of truth and bounded snapshots captured while visible.
3. Run local targeted checks and full required Release iPad/iPhone gate, review the change, sign and upload the same successful SHA. Verify Apple/internal-group availability and request device retest.

Recommended implementation model: GPT-6.1-sol, high reasoning; WebKit, media sessions and asynchronous snapshots cross native and JavaScript boundaries. No model switch or delegation is authorized by this recommendation.

- Owner added a requirement: move the add-site icon to the left of the address field. Reordered the existing form button before address-entry; flex sizing/behavior are unchanged. Read back the resulting form.

- UI regression RED: equivalent dictionary order and title/selection updates both destroyed existing card/image nodes. Added keyed updates with a stable visible-field signature and late-response URL checks; all three tests now pass. The view owns update deduplication; removed the competing app-level dictionary signature.

- Final owner requirements supersede the earlier compact proposal: normal browsing retains the media shortcut and adds a separate collapse arrow to its right that hides only the model row. Shortcut launch enters web-app mode with no model row and starts with Back, Forward, and an expand arrow only. Expanded web-app mode shows address, navigation, refresh and ATMA Home at the far right. Native keyboardLayoutGuide usesBottomSafeArea=false lowers chrome to the physical bottom while retaining keyboard avoidance.
- A shortcut must retain its saved profile and associated website data store. New shortcuts save profileId from the same native current-site snapshot; edits preserve it. Legacy shortcuts do not contain an original profile; provide one explicit model choice rather than guessing that historical value. All future launches use the pinned profile.
- Native white-preview RED confirmed on 40073790172: real red/blue pages produced white snapshot channels (255). Native snapshots now run before visible renderer transitions, not after hiding. Images are bounded (280px, max 12 tabs), tied to URL and renderer identity, and invalidated on navigation/close/profile replacement.
- Initial video regression waited for readyState>=3 before play, which can stall on iOS preload. Retry 40076432469 waits for metadata and invokes play before waiting for progress; no media production fix has been applied pending that evidence.
- Added real-WebKit regression checks for shortcut pinning, data-store identity, DOM preservation through chrome expansion, lowered normal chrome, and model-row-only collapse. Full iPad/iPhone UI smoke also exercises quick-add, shortcut minimal/expanded controls, and keyboard clearance.
- Native regressions use an 8-second H.264/AAC fixture and a real loopback WebKit page. A temporary early regression step runs before the unchanged full iPad/iPhone gate; it cannot produce a verified SHA on its own.

- Media RED on 40076432469: actual H.264/AAC playback is ready and periodic reports pass (5.751s test); a passive AVAudioSession interruption notification makes the old native observer pause that same playing element (5.975s test, paused=true). Removed the duplicate native-to-JS interruption pause and per-report session activation/deactivation. Playback category is configured before a site starts; WebKit owns its player's audio lifecycle. User pause, explicit controls, owner handover and background-disabled policy remain. This is a reproduced app defect, not a claim that the physical YouTube/RUTUBE symptom is fully confirmed resolved.
- Removed the temporary early preflight before the final full gate, so new rendering regressions run once among the full iPhone unit/UI suite after the iPad UI run. The verified marker remains conditional on both successful Release device runs.

- Independent review found and corrected: production tabs UI requests previews before the panel RPC, so previews now joins/captures the still-visible current page before replying; regression clicks the real UI tabs button. Popup selection is deferred until opener capture while returning WebKit's supplied-config renderer immediately, with no duplicate navigation. Private legacy profile picker is cleared on vault lock. Quick-add now reads current-site via api (not action/consume) because that metadata includes profileId but is not a complete native state; a real UI regression records data-mode changes and checks the saved profile.

- Full-gate RED 40077445464 reached shortcut tapping on iPad but did not enter app chrome; recording shows an empty desktop page. Later source 787c7e passed the full gate 40078087940 (iPad UI137.145s,30native tests including media/previews/profile/chrome and iPhone UI89.501s). Therefore do not attribute the old failure solely to layout: the partial-state consume fix also changed that path.
- Additional narrow geometry hardening addresses a directly observed code issue: renderApps calculated pages while home was hidden or native UI still had footer-only height. It now waits for home/full native viewport (blank tabs excluded), retries on changed native geometry and actual grid ResizeObserver events. Original page-counter/Add-page semantics are preserved. Review found and closed the geometry ordering gap; the rejected counter redesign was reverted. Native quick-add regression additionally waits for the saved tile to be physically inside visible desktop after Home. Evidence: out/media-tabs-20261024/first-full-gate.zip and shortcut-failure.png.

- Visual inspection of GREEN787 iPhone screenshots revealed an extra68pt of bottom area after the real address/keyboard flow: 1206x2622 PNG left-edge footer regions measure138/154/234pt in minimal/expanded/normal, while configured chrome is70/86/166pt. The prior physical-bottom native unit does not open the keyboard. Added a full-AX-snapshot UI criterion after actual keyboard dismissal and in minimal app mode; it must reach the real window bottom. Hypothesis under test: end the native WebKit input session before resizing the UI. Native open/home/chrome now explicitly endEditing(true); diagnostics-only deduplicated layout logs include root, viewport, UI, keyboard guide and safe insets. Do not claim the hypothesis is confirmed until this criterion and images pass. Apple documentation confirms usesBottomSafeArea=false targets the view bottom: https://developer.apple.com/documentation/uikit/uikeyboardlayoutguide/usesbottomsafearea .

### Closed-keyboard viewport regression, 09:38 UTC

- Run 40081172240 (cc5a594) passed iPad UI and all 30 native iPhone tests. The iPhone UI regression correctly failed: window bottom 874pt, UI bottom 806pt, Home centre 114pt above the bottom. Keyboard-dismissal assertion passed.
- CI layout diagnostics show the keyboard guide first becomes zero-height, then returns to a 68pt height even after native editing ends. The viewport follows that stale guide. This isolates the extra gap to the native constraint, not CSS.
- Use the keyboard guide only between system keyboard-will-show and keyboard-will-hide notifications. Otherwise constrain the viewport to the physical view bottom. Keep the guide during presentation for native keyboard resizing/rotation; use system animation timing when switching. No fixed 68pt correction and no renderer replacement.
- Re-run the existing red physical-bottom scenario and the full iPhone/iPad gate; inspect actual new screenshot pixels before signing.

### Viewport event ordering, 10:21 UTC

- Source1adaac5/run40083212629: both Release UI smoke scenarios passed, including real keyboard/rotation and physical-bottom assertions. Actual iPhone screenshot footer heights are now normal166pt, device-row-hidden128pt, minimal web-app70pt and expanded86pt. The68pt excess is gone.
- The full gate still failed: native quick-add/Home scenario timed out waiting for the newly saved tile inside the visible desktop. Other29native cases passed. The timeout previously emitted only video data, insufficient to distinguish hidden DOM from scroll/geometry.
- Desktop rendering was retried only by element ResizeObserver. A callback can run while window.innerHeight still has the footer height; the native-height guard defers rendering, and there was no window resize subscriber to retry it. Extracted the existing observer into a small desktop-viewport module: a behavior test reproduces a missed final viewport event (RED), then passes after subscribing to window resize too (GREEN). No polling, timer or changes to slot/page layout. Whether this accounts for the actual native failure must be confirmed by the full regression.
- Native timeout diagnostics now include viewport, desktop rect/scroll/pages and bounded tile rectangles. The strict visibility assertion and deadline are unchanged.

### Delivered build 11, 10:59 UTC

- Shipped source `2c14bf00ffbd9505da8995fb64df5fac058790e1`. Full native run 40085672807 passed: iPad UI 148.079s, all 30 native iPhone tests without failures, iPhone UI 116.684s. The formerly failing quick-add/Home scenario passed in 10.673s. Final footer measurements remain 166/128/70/86pt.
- Signing/upload run 40087431683 passed using that exact successful native artifact/SHA. IPA: 23,790,591 bytes; SHA-256 `da6d778b8e9512be538cfcacb719cbee212353e86f0a48217ac847c3b44221a0`. macOS strict codesign validation passed; the local verifier matched all 33 resources against LF Git source.
- Apple build `219bdd9f-a664-4167-8a29-8099167bb705`, version 1.0.0 (11): processing VALID, not expired, usesNonExemptEncryption=false, internal IN_BETA_TESTING. Existing internal group Test includes 11. Russian test instructions were saved and read back.
- Asked owner to update in TestFlight and retest physical YouTube/RUTUBE inline/PiP for 30 seconds. Physical verification remains pending and is not inferred from compilation or simulator fixture playback.
