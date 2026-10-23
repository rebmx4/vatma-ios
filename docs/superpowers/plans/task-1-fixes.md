# Task 1 review fixes

Status: DONE_WITH_CONCERNS. Review items I1, M1 and M2 are addressed in source. This report does not claim an iOS build, passing XCTest, or verified WebKit callback ordering.

## Scope and discovery

Read `task-1-review.md` as UTF-8 and verified each finding against the current sources. Graph-first lookup used project `atma-ios-release`; it returned zero native symbols, consistent with the stale index. Only the already identified native files were inspected. No reindexing, installation, CI/build, publication, commit or push. All work files and explicitly configured Python cache paths are on D:.

## I1 — navigation becomes WKDownload

Both action and response download-policy paths now record the expected main-frame conversion, its original tab, request URL and available WKNavigation identity. The action path can initially lack a navigation identity; before didStart it can recognize interruption only through the exact failing URL. The classifier additionally requires either NSURLErrorDomain cancellation or WebKitErrorDomain policy interruption 102. A different navigation, another error domain with code 102, or a real network failure does not match. There is no global suppression of code 102.

The two didBecome callbacks attach the WKDownload to its original tab. A matching main-frame conversion explicitly sets that BrowserTab's loading=false and error=nil, persists it and publishes state. Expected interruption can be reported before or after didBecome; after transfer, a late expected interruption does not clear a real download failure. A new normal main-frame navigation discards an older conversion, and callbacks from a superseded WKNavigation do not overwrite the current navigation state. Closing a tab or replacing its renderer clears its navigation tracking.

DownloadService now keeps a download-to-tab association through completion/failure. A real download failure updates the originating tab error rather than only a global nativeError; successful completion publishes state without wiping an unrelated error. Navigation terminal failure also explicitly overrides loading=false, instead of reading a potentially transient WebKit isLoading value.

## M1 — blocker exclusions across redirects

The main-frame response uses response.url.host. didReceiveServerRedirectForProvisionalNavigation, didCommit and didFinish additionally reapply the content rule list using the actual webview URL host. Subframe responses do not change the top-level policy. Exact-host matching is case-normalized and shared through HostBlockerPolicy; an exclusion for A does not disable B or a subdomain implicitly.

## M2 — safe Unicode filename length

DownloadFilename produces a single sanitized component, limiting its final UTF-8 length to 240 bytes. The stem budget reserves 37 bytes for a dash plus UUID even before a collision, and separately includes a bounded extension of at most 32 UTF-8 bytes plus its dot. Truncation preserves whole Swift Characters. A collision regenerates the name from the original suggestion through this same policy, preventing an unbounded suffix from being appended to an already maximal component. Empty/hidden components use a safe fallback; path separators/control characters cannot create child paths.

## Changed files

- BrowserNative/BrowserController.swift — tab-specific download results, navigation tracking, cleanup and explicit loading override.
- BrowserNative/BrowserNavigation.swift — expected conversion registration/classification, terminal loading behavior and main-host blocker refresh callbacks.
- BrowserNative/BrowserDownloadNavigation.swift — new conversion lifecycle integration and cleanup, 38 lines.
- BrowserNative/BrowserModels.swift — value-type terminal download-navigation transition on BrowserTab.
- BrowserNative/DownloadService.swift — originating-tab ownership through download callbacks and shared byte-budget filename policy.
- BrowserNative/DownloadPolicy.swift — new Foundation-only interruption classifier, UTF-8 filename policy and exact-host blocker predicate, 59 lines.
- BrowserNative/SiteSecurity.swift — shared exact-host predicate and normalization of saved exclusions.
- BrowserNativeTests/BrowserDownloadTests.swift — six tests, 64 lines, without instantiating WKWebView or invoking downloads.

## Tests authored

Six new XCTest cases cover:

1. Download terminal loading/error state while retaining tab ID, profile, URL and title.
2. Expected policy interruption with matching navigation identity; reject another navigation, wrong error domain and genuine network failure.
3. Pre-start download cancellation requires the exact failing URL; missing or different URLs do not match.
4. Cyrillic/emoji names and very long Unicode extensions fit the final byte budget, including the UUID collision suffix, while retaining ordinary extensions.
5. Path/hidden/backslash filename inputs remain safe components.
6. Case-normalized exact-host exclusions do not follow a redirect to another host or apply to subdomains.

These cases exercise production value logic. Their assertions are authored but NOT executed on this Windows host, so no red/green XCTest claim is made.

## Checks actually run

- Fresh Python static-source assertions passed for all 13 Swift files: each under 400 lines, no trailing whitespace, no old browser dependencies, print/NSLog or blanket website-data removal. Specific checks confirm redirect/response/commit/finish wiring, per-transition interruption classification, download-to-source-tab association, byte-budget naming and absence of the former prefix(160) path. This is source inspection, not execution of Swift logic.
- `git diff --check -- BrowserNative BrowserNativeTests` exited 0. Git emitted only configured LF-to-CRLF conversion warnings; no whitespace error was reported.
- `Get-Command swift,xcodebuild` again found neither executable. No Swift type checking, XCTest, Xcode build, Simulator/device run, download filesystem operation or real HTTP redirect scenario was executed.
- The public redirect callback was checked against [Apple's WKNavigationDelegate documentation](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webview(_:didreceiveserverredirectforprovisionalnavigation:)).

## Remaining validation

On macOS, compile and run the XCTest target. On iOS, open a same-tab HTTP attachment and confirm loading becomes false, no spurious navigation error remains and the file is saved; then verify a failed download remains visible. Exercise both action/download-attribute and response/attachment conversions, both interruption callback orders, a second navigation while a file is downloading, and closing/changing the originating tab. Verify excluded A→B and enabled A→excluded B server redirects, plus repeated Cyrillic/emoji filename collisions. These runtime requirements remain unverified; no blanket trust or error suppression was introduced to work around them.
