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

- Owner added compact browser chrome: replace the right-hand media shortcut with a collapse arrow; collapse the full model/address/navigation panel to a thin restore strip, and lower the expanded navigation row toward the physical bottom edge. This is included in the same replacement, preserving keyboard clearance and a way to reopen controls.
- Native regressions use an 8-second H.264/AAC fixture and a real loopback WebKit page. A temporary early regression step runs before the unchanged full iPad/iPhone gate; it cannot produce a verified SHA on its own.
