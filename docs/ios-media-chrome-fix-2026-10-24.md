# ATMA iOS browser update — 24 October 2026

Status: Build 1.0.0 (11) is available in the existing internal TestFlight group Test. Apple processing is VALID, internal state IN_BETA_TESTING. Owner physical-iPhone retest is pending.

Source: `2c14bf00ffbd9505da8995fb64df5fac058790e1`. Native [run 40085672807](https://github.com/rebmx4/vatma-ios/actions/runs/40085672807) passed. Signing [run 40087431683](https://github.com/rebmx4/vatma-ios/actions/runs/40087431683) passed.

## Changed

- Shortcuts persist the selected profile/device at creation. Opening one applies that profile and its persistent website data store before creating the renderer. Later ordinary-browser device changes cannot replace this binding. Legacy shortcuts ask for an explicit device once because their original data never stored it.
- Ordinary browsing keeps the model/address/navigation/player. Add-site icon is left of the address field. A separate arrow right of the player hides only the device row.
- Saved web apps launch with Back, Forward and an expand arrow. Expanded controls show address, reload and ATMA Home at the far right; no model selector. Presentation changes retain the current renderer and document.
- The viewport follows the keyboard guide only while the keyboard is presented. After dismissal it attaches to the physical bottom; this avoids the observed stale 68pt keyboard-guide inset.
- Desktop rendering responds to both element and final window resize events, so an early callback deferred by the native-height guard receives another attempt. Slot positions/page semantics are retained.
- Tab cards/images survive equivalent state updates. Native previews capture the visible page before it is hidden, include popup transitions, reject stale URL/renderer results and retain a bounded cache.
- Media state reports no longer repeatedly activate/deactivate AVAudioSession. A passive audio-session notification no longer sends a second JavaScript pause to the website. Explicit controls, owner handover and the background-disabled preference remain.

## Verified

- 18 JavaScript tests, 23 Python/config/release tests and standalone source/resource validation passed; 265 product files checked.
- Release iPad UI smoke passed in 148.079s. All 30 native iPhone tests passed with 0 failures (47.719s). iPhone UI smoke passed in 116.684s.
- Native regressions cover real H.264/AAC playback across periodic reports, passive interruption, actual red/blue snapshot pixels, popup opener previews, shortcut profile/store identity, retained document through chrome changes, quick-add state and tile visibility, keyboard/rotation and physical-bottom layout.
- The local desktop viewport behavior test was RED with observer-only behavior, then GREEN with final window resize delivery. The formerly failing native quick-add/Home scenario passed in 10.673s in the final full run.
- Screenshot measurements and visual review confirm the footer heights below; the former 68pt excess is absent.

| iPhone presentation | Previous height | Verified height |
|---|---:|---:|
| Ordinary browser |234pt |166pt |
| Device row hidden |196pt |128pt |
| Web-app minimal |138pt |70pt |
| Web-app expanded |154pt |86pt |

Native evidence is in `out/native-40085672807/`; exact source provenance passed `release/github_ci.py gate`. Source resources for local IPA comparison were extracted from the exact Git SHA with LF conversion explicitly disabled (`out/source-2c14bf00ffbd/`, 33 files).

## Delivered

- App Store Connect app 6774934498, bundle `ru.atma.app`, version 1.0.0 (11); Apple build `219bdd9f-a664-4167-8a29-8099167bb705`. Uploaded 24 October 2026 at 10:56:17 UTC. Processing VALID, not expired, usesNonExemptEncryption=false, internal IN_BETA_TESTING; existing group Test includes 11.
- Signed IPA: `out/signed-40087431683/ipa/ATMA.ipa`, 23,790,591 bytes. SHA-256: `da6d778b8e9512be538cfcacb719cbee212353e86f0a48217ac847c3b44221a0`.
- macOS CI verified archive and exported signatures with `codesign --verify --deep --strict`. Local IPA structure/identity/icons verification passed and all 33 bundled source resources matched the exact LF Git archive.
- Russian What to Test instructions were saved and read back exactly. Evidence: `out/signed-40087431683/apple-testflight-confirmation.json` and `out/delivery-state.json`.

## Remaining verification

Owner physical-iPhone retest: YouTube/RUTUBE for 30 seconds inline and in PiP; save shortcut with device A, choose B in ordinary browsing, reopen shortcut and confirm A/session; verify collapse/expand and stable tab previews. Simulator fixture playback alone does not verify every condition on those physical websites.
