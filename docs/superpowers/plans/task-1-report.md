# Task 1 — native standalone implementation

Status: DONE_WITH_CONCERNS. Sources are implemented; iOS compilation and device behavior remain unverified on this Windows machine.

## Files and boundaries

Only `BrowserNative/*.swift`, `BrowserNativeTests/*.swift`, and this explicitly requested report were written by this worker. No existing PC browser files, package installation, CI run, build publication, commit, or push. Every work path used is on D:. Installed Python was read/executed from its existing location with bytecode disabled and cache redirected to D:.

- `BrowserController.swift`: standalone UIKit `@main` AppDelegate and root BrowserController, safe-area/keyboard-aware layout, actual-device geometry, lazy site renderers, tabs, state/persistence, bundled UI events.
- `BrowserModels.swift`: Codable tabs/preferences, profile catalogue, stable UUID-backed persistent WKWebsiteDataStores per profile.
- `BrowserRPC.swift`: reply-capable RPC, exact own-webview/main-frame/HTTP-loopback-host/port validation, tab/profile/navigation/preferences/cookie/file actions and bounded native thumbnails.
- `BrowserNavigation.swift`: independent WebKit navigation, target=_blank tab creation preserving request method/body, downloads, TLS callbacks, JavaScript dialogs and WebKit process termination.
- `BrowserSecurity.swift`: HTTP(S) address validation/search, length-prefixed SHA256 cookie identity, safe static resource request paths.
- `CookieService.swift`: native HttpOnly-inclusive cookie listing and current-profile ID-based deletion. No general website-storage deletion; cookie values only return to the authenticated local UI request.
- `DownloadService.swift`: WKDownloadDelegate with TLS/redirect decisions, safe Documents/Downloads destinations, metadata and limited previews. IDs resolve only to freshly enumerated regular files; symlinks and traversal are rejected.
- `LocalUIServer.swift`: Network.framework server bound explicitly to 127.0.0.1, GET-only bundled resources, bounded headers, Host validation, no arbitrary path access, stable saved first-use port and fail-closed bind behavior.
- `SiteSecurity.swift`: ordinary system trust first, then only bundled pinned RSA root, PEM SHA256 and DER fingerprint checks, original trust policies and system anchors retained; independent WKContentRuleList and per-host exclusions.
- `BrowserSecurityTests.swift`: four XCTest cases for dangerous URL schemes/embedded credentials/search escaping, cookie identity separation/ambiguity, exact cookie path/profile selection, and literal/encoded resource traversal.

## Integration contract

Parent owns the shared BrowserUI, project/Info.plist/CI and certificate packaging. Bundle folders must retain the names `BrowserUI` and `certificates`. `BrowserUI/profiles.json` is the existing profile-object array; `actual-device` is prepended natively and is the first-launch default. Non-default profiles change only the site WKWebView user agent, never the ATMA or device geometry.

UI entry URL is `http://127.0.0.1:<persisted-port>/?context=ios`. The UI webview receives the sole `atma` WKScriptMessageHandlerWithReply in the page content world. Site WKWebViews have separate WKUserContentControllers without that handler. UI replies contain full mutation state; asynchronous updates dispatch `CustomEvent('atma-native-state', {detail:state})` using argument serialization rather than source-string interpolation.

All specified state fields and actions are present. `tab-previews` returns `{previews:{tabId:dataURL},errors:{tabId:reason}}`; a request without rendered tabs rejects with an explanation. At most twelve renderers are captured per request, each image is resized to at most 280 physical pixels wide, and parallel duplicate requests reject. Blank tabs never instantiate a site renderer. Every launch starts on the home desktop, retaining tab list/selection and preferences.

Additional agreed RPC: `blocker/set` with `{enabled:Bool}` toggles the currently open exact hostname, persists its exception, applies rules and reloads that tab. State includes `blocker:{available,enabled,host,error}` and `capabilities.contentBlocking`. The independent rules resource is `BrowserUI/content-blocker.json`. This permits disabling blocking when troubleshooting a banking site without changing certificate acceptance.

Cookie actions match the brief. Cookie IDs include current profile ID/domain/path/name with length prefixes before SHA256. `cookies/delete` captures the current profile/store at request time and deletes only exact native cookies in that store, then lists it again. Concurrent websites may recreate their cookies; returned results reflect the actual refreshed store. No cookie values enter logs, exports or this report.

File replies match the brief. Text reads at most 100000 bytes with `truncated`; image/audio/video/PDF previews return base64 up to 8 MB. Unsupported or larger files remain saved and return kind `other` plus an explanation. Downloads use safe unique names and never accept caller-supplied filesystem paths. Cookie deletion does not delete downloads or other website storage.

Preferences accept google/yandex/bing/duckduckgo, ru-RU/en-US only, and valid platform timezone identifiers. These values persist; WebKit's JavaScript Intl timezone and language remain the real platform values, and explicit capability flags report that limitation. Google search is the default. No synthetic Google/ATMA account login is present.

Info.plist must permit local loopback HTTP and intended plain-HTTP web content through the appropriate ATS web-content settings. HTTPS always follows the trust delegate. Parent was notified. Project must target iOS 17+, compile these Swift files rather than legacy application sources, include iPhone/iPad, and use the standalone AppDelegate without a conflicting scene lifecycle or another `@main`.

## Verification performed on Windows

1. Code graph discovery attempted first: graph returned project not indexed, so direct scoped inspection was used.
2. Read back the changed controller/RPC and manually reviewed state, lazy tabs, profile stores, TLS completion paths, server path handling, download handling and cookie deletion boundaries.
3. Fresh Python structural check passed for all 10 Swift files: every file under 400 lines, no trailing whitespace, no old browser dependencies/imports/endpoints, no print/NSLog/cookie logging or blanket removeData calls; every required RPC action and source guard present; exactly one reply-handler installation; persistent store and system-anchor preservation APIs present. Production files range from 32 to 202 lines at this check.
4. `Get-Command swift,xcodebuild` found neither command. XCTest, Swift type checking, app build, simulator and physical device scenarios were NOT run. Static checks do not establish compilation or runtime behavior. The tests were authored before the implementation, but a red/green XCTest cycle could not be executed on Windows.
5. Public API signatures checked against Apple/WebKit primary documentation: [reply handlers](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply), [persistent profile stores](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/), [loopback listener endpoint](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint), [download delegate](https://developer.apple.com/documentation/webkit/wkdownloaddelegate), [download authentication challenges](https://developer.apple.com/documentation/webkit/wkdownloaddelegate/download(_:didreceive:completionhandler:)).

## Remaining concerns and honest platform limits

- A macOS Xcode build and XCTest execution are mandatory before calling the iOS application validated. Then exercise launch/relaunch, storage isolation and persistent website sign-in, real downloads, cookie deletion, wrong-host/expired/self-signed TLS rejection, pinned-root TLS success, UI bridge rejection from site/subframes, iPhone/iPad layout and keyboard, foreground/background tabs, and exact-host blocker exceptions.
- Persistent stores retain website cookies/site storage according to WebKit and the site's own expiration/session/logout policies. They cannot guarantee an indefinite login, override a provider's embedded-browser OAuth restrictions, or move PC sessions to iOS. Google/ATMA OAuth integration is still a parent/user decision, not a fake native login.
- Full fingerprint emulation, JavaScript language/timezone spoofing, cross-device sync, arbitrary site background push and complete page translation are unavailable and reported false. There is no deceptive probe result. iOS uses Apple WebKit regardless of a selected desktop/Android UA.
- Replacing bundled pinned certificates requires a rebuilt signed application. There is no remote certificate updater or unchecked TLS bypass. Wrong hostname, expiration and trust policy checks remain active, including for downloads.
- Hidden/process-terminated tabs can fail WebKit snapshots; errors are explicit. Only the first twelve rendered tabs are captured in one preview batch. Favicon metadata is currently the empty string rather than an invented external favicon endpoint.
- Arbitrary external URL schemes, window.open() workflows that require a returned blank popup object, provider-restricted embedded OAuth, background download resumption and opening very large file previews need future platform-specific work. Normal HTTP(S) target=_blank links and HTTP(S)/blob downloads with the download attribute are handled.
- Independent content-blocker rules are supplied by the parent; no subscription updater or advertised comprehensive blocker coverage exists. Per-host disabling is implemented.
