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
