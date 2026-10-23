# Task 1 brief: independent native ATMA browser

Read this first; these are your requirements. Work only in
`D:/Projects/atma-browser-ios/BrowserNative/*.swift` and
`BrowserNativeTests/*.swift`. Parent handles shared UI, CI, assets and preview.
No subagents. No commits or pushes. All files/temp/cache on D:; no new tools.

Implement UIKit browser (iOS17+, iPhone/iPad) using Apple frameworks only.
No Brave/Chromium imports, packages, SDK, endpoints or old vatma web client.
Root class `BrowserController: UIViewController`, own `@main` AppDelegate.
Each file <400 lines. Read existing relevant code through graph first if needed.

Own UI is bundled `BrowserUI` folder, profile catalogue `BrowserUI/profiles.json`.
It uses existing app.js and `window.webkit.messageHandlers.atma.postMessage({action,body})`
RPC with reply. Install `WKScriptMessageHandlerWithReply` ONLY on UI webview;
validate webView identity, main frame and exact loopback origin/port. Sites must
never invoke the handler. UI updates use CustomEvent('atma-native-state', {detail:state}).

Serve static UI via `LocalUIServer` using Network.framework, loopback only,
no arbitrary filesystem access, GET only, reject encoded traversal. Stable port
persisted on first use for stable localStorage origin; fail closed on collision.
Bundle resources location `BrowserUI` and `certificates` folder. UI load URL
`http://127.0.0.1:port/?context=ios`; state.id = 'ios'. Use safe-area layout.
Home/panels: UI fills safe area, site hidden. Browsing: UI footer174px at bottom,
site WKWebView above it. Preserve existing interface and sites' independent DOM.

State JSON fields: id,deviceName,profileId,mode(home|browse),panel(null|string),
url,title,siteName,iconUrl,width,height,footerHeight174,loading,error,capabilities,
searchEngine(google default),locale(ru-RU),timezone(Europe/Moscow),profiles(array),
tabs(array of id,profileId,url,title,siteName,iconUrl,loading,error),activeTabId.
Use actual-device profile default; UA profile selection must not change ATMA
geometry. Report actual limitations; never promise full fingerprint emulation.
Persist tab list/selection and preferences. Always show desktop on launch.

Actions: state,open({url}),home,panel({panel}),tabs/new,tabs/select({tabId}),
tabs/close({tabId}),profile({profileId}),preferences({searchEngine,locale,timezone}),
back,forward,refresh,current-site,tab-previews. Mutations reply full state.
Return current-site metadata. Real snapshot thumbnails may be bounded to280px.
Do not create site renderer for blank tab until navigation. Handle target=_blank.
URL resolver allows only http/https without embedded credentials and Google
search default; reject javascript/file/data in address input.

Cookie API: action cookies => {cookies:[{id,domain,path,name,value,secure,httpOnly,
session,expires(seconds since1970 or0)}],profile:{id,name}} for CURRENT profile.
IDs SHA256 of profile+domain+path+name. cookies/delete body {ids:[...]} or
{all:true}; only delete cookies using those IDs in current store, no caller paths.
Return refreshed cookies response. Access HttpOnly using WKHTTPCookieStore.
Profile WKWebsiteDataStores must be persistent, separate, stable UUID per ID.
Never print/log/export cookie values. Deletion must preserve other site storage
and downloaded media; no blanket removeData(all types).

files => {files:[{id,name,size,modified(ISO8601),extension,kind,mime}]};
file({fileId}) => metadata plus text/truncated or base64 for supported previews,
otherwise kind:'other',note. Implement actual WKDownload delegate to save safely
in Documents/Downloads. Prevent traversal/symlink access; IDs map only to listed
files. Ordinary audio/video remain downloadable without a Playlist module.

TLS: ordinary SecTrustEvaluateWithError first; if rejected add only pinned RSA
root from bundled certificates/manifest.json and PEM. Validate sha256 before use
using CryptoKit, preserve original trust SSL/hostname policy and system anchors
via SetAnchorCertificatesOnly(false), reevaluate. Never accept expired/wrong-host
or self-signed cert by ignoring trust. Handle all completion paths once.

Use WKContentRuleList with independent bundled content-blocker rules (parent
can supply JSON); no Brave updater. Keep per-site disable hook if reasonable.
Sync, arbitrary background push and complete translation are future work;
do not fake them. Unsupported probe/snapshot returns explanatory error.

Add meaningful Swift tests for cookie identity/path selection and URL validation
or resource resolver. Windows cannot compile UIKit; clearly report this limit.
Report full details to `docs/superpowers/plans/task-1-report.md`, return only
DONE/DONE_WITH_CONCERNS, files, checks and remaining concerns. Do not wait for
user approval; authorized requirements are complete. Send parent interface
decisions promptly if needed, and continue to completion.
