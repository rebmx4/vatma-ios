# ATMA media player and YouTube protection implementation plan

**Goal:** Own media controls, iOS Picture in Picture and background audio, plus
independent YouTube ad response/DOM handling. User approved the preceding chat
plan and explicitly chose an implementation written for ATMA, using Brave as a
reference rather than restoring its code or dependencies.

**Architecture:** Keep the original HTML media element in its existing profile
WKWebView; this preserves MSE/blob streams and authenticated website sessions.
Own JavaScript reports bounded media state and performs validated commands.
Native code owns audio-session/lock-screen controls and media tab lifetime.
WebKit owns the real OS PiP window. Network content rules and a separate,
YouTube-only response/DOM adapter implement the two blocking layers.

**Constraints:** All Windows writes on D:. No paid CI, install, push, publication
or Responsively/server restart. Existing user tabs/cookies/PIN/settings retained.
No Brave imports/services/copied implementation, private Apple API, external
video proxy, DRM bypass, player URL scraping service or automatic video download.
New source files below 400 lines. Windows evidence is not iOS runtime evidence.

## Tasks

- [x] 1. Write failing JS behavior tests; implement own YouTube adapter and media
  page controller in BrowserUI/assets. Protect ordinary player data, deliberate
  pause, unknown/live duration, unrelated origins and user blocker exceptions.
- [x] 2. Add BrowserMedia policy/controller/scripts/remote-controls under
  BrowserNative. Register a separate restricted site message handler; add only
  media actions to privileged UI RPC. Configure public PiP/background audio APIs.
  Update exact background-mode allowlist and targeted CI tests, preserving all
  TLS and privileged bridge boundaries.
- [x] 3. Add RU/EN media panel and preview host adapter. Keep media bound to its
  owning tab while browsing elsewhere. Stream/PiP errors remain explicit.
- [x] 4. Run isolated media/YouTube integration checks, source/config validation,
  review the complete change and record what still needs iPhone testing.

## Verification

Node: actual adapters in a bounded DOM/media harness; JSON/Response/XHR ad
removal without changing streams, response restoration, no host leakage, exact
media command validation, PiP failure and state handling. Windows live checks use
owned test tabs and a generated video only; an actual YouTube page is checked
separately. Native XCTest covers message/command policies and configuration;
real PiP/locked-screen playback remains an Apple-device requirement.

## Progress

Own adapters: Node behavior suite 7/7 passed after observed failures for missing
adapters and XHR response handling. Original streams/playability retained; wrong
hosts, blocker exceptions, invalid commands, pause and unknown/live seeking checked.
Native audio/PiP source and restricted media handler added; Swift/XCTest cannot
run on this Windows machine. Configuration audio allowlist tests failed before
validator changes, then Python suite passed 10/10. No CI or publication started.
UI/preview adapter implementation complete. Work uses the existing linked
checkout and junction; no commit sweeps unrelated prior changes.

Task 3: source implementation and preview integration complete. Native/preview
media commands preserve the source tab and never export stream URLs. RU/EN panel
and footer shortcut added. Actual generated-video checks passed in phone/pad
viewports, including real Chromium PiP and ownership lifetime. Public YouTube
video also played and entered actual PiP after its play button was clicked.
Final actual YouTube check removed ad fields from one player response and retained
working playback/PiP. This is not proof of blocking all served ad formats. Native
Xcode build, audio after iOS suspension, lock-screen commands and PiP on iPhone
remain unrun. Final RU/EN and dark/light checks passed on both viewport sizes.

Ruling: remove duration-based ad seeking and automatic muting. A failing test
showed that prefetched metadata plus a stale ad class could skip the main video
to its end. Keep response filtering, explicit ad-container CSS and visible skip
button clicks. Cost: an unrecognized, unskippable ad may still play; main-video
position and volume remain untouched. Regression observed RED, then fixed.

Final review: one fresh reviewer, Critical none. Important paused-ad skipping
and metadata-based main-content skipping reproduced RED and fixed; adapter suite
10/10 green. UI stale-poll/command ordering reproduced in real DOM, fixed and
green. Preview owner profile-release and reconnect retention RED then 4/4 green.
Preview document-start check initially failed, then passed after keeping a live
Page-enabled CDP session for each owned target. No second review was dispatched.
All preview Node tests: 48/48 green. Python: 10/10 green. Static product scan:
261 files passed. iOS XCTest is authored but not executed on Windows.

Final: minor (deferred): MPRemoteCommandCenter callbacks acknowledge queued
commands before asynchronous WebKit completion, including unsupported live seek.
The in-app seek controls already disable themselves for unknown/live duration.

Final: Ruling: retain the media owner across home/new tab/panels and keep the
background preference independent of blocker exceptions, as specified. Apple
runtime verification remains a release gate rather than inferred success from
Windows. Unrecognized unskippable ads may play instead of risking main content.
Work remains local; no paid CI, push or publication. User tabs/settings retained.

## Review focus

Site media messages cannot reach UI/cookie/file RPC. Ad removal must never mark
content unavailable or skip the main video. Commands cannot navigate, export
media URLs or alter cookies. A new tab, home screen or modal must retain the
media owner; closing it stops controls. No audio resumes after intentional pause.

Recommended implementation model: gpt-6.1-sol, high. Reason: coordinate WebKit
media lifecycle, YouTube compatibility, state authority and iOS audio/PiP.
