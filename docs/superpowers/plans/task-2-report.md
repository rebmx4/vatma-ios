# Task 2 — shared UI, cookies, appearance and languages

The canonical UI is `BrowserUI/`; preview `public` is a junction to that folder.
`profiles.json` supplies both runtimes. Existing website renderers and user data
were retained. No service, Responsively restart, paid build, push or publication.

Changes:
- Native reply RPC plus native state events, guarded preview cookie messages.
- Cookie list/search/details with text-only values, exact selection and delete-all
  for the selected browser profile. Search remains below the scrolling cookie list.
- Preview main-process cookie service checks sender/frame and D: session storage;
  host derives the partition from authenticated actual context state.
- Cookie deletion expires the exact name/domain/path tuple rather than calling
  broad cookie removal. Files and other site storage are not cleared.
- APiKS verified palette: dark101010/191919/242424/cdb77a and
  lightf1f0ed/faf9f6/e9e7e2/745d25. Automatic/light/dark preserved.
- RU/EN live reversible interface localization and website menu; DE/FR removed.
  User app names, website titles, file names, cookie names and values opt out.
- Native appearance and alternate-icon RPC calls: Task3 owns their implementations.
- The simulated home indicator is hidden in native iOS, which already supplies
  the real system indicator below the safe area.
- Built-in Settings/Files are searchable by their English interface names as
  well as original names, without rewriting stored application names.
- Native per-site blocker switch, honest unsupported locale/timezone/probe controls,
  audio/video preview elements. Media files remain separate from cookies.

Verification on Windows:
- `node --test i18n.test.mjs appearance.test.mjs cookie-store.test.mjs workspace-model.test.mjs`:
  20 passed (23 October2026). UI module syntax checks passed.
- `cookie-host.test.mjs`: 2 passed for rejected origin/frame/action/nonce and
  deriving the actual profile partition. `blocker.test.mjs`: 1 passed for exact
  domains/subdomains and lookalike/path rejection in all 27 initial rules.
- `verify-cookies-appearance.mjs`: phone428×926 and iPad768×1024, RU/EN only,
  live language switching, both APiKS palettes, actual cookie-list RPC, fixture-only
  exact and all-cookie deletion, text-node handling and original sessions retained.
  Evidence: preview/out/cookies-appearance-verification.json.
- `verify-navigation-controls.mjs` passed on both devices after the palette change:
  blank tab, exact home centre, back/forward, plus, three-column overview and close.
  Fresh native-window captures in preview/out/atma-{light,dark}-{iphone,ipad}.png
  were inspected; the home/footer palette matches in both modes.
- A delayed real state-poll response reproduced closing a newer Settings panel
  before the fix. `stateActionVersion` now rejects replies started before a newer
  action. `verify-state-order.mjs` passed on phone and iPad, then cookie/language/
  appearance and navigation checks passed again. Source review approved this guard.
- Earlier real isolated Electron check used Secure/HttpOnly cookies with the same
  name at `/` and `/bank`: exact deletion retained the other path; all cleared only
  that isolated partition. No user cookie deletion or cookie-value logging.

No iOS compilation, WebKit rule compilation, actual native icon change, banking
login, OAuth or Safari/Chrome performance comparison has run. Windows results
are preview evidence only. The preview server was not restarted; startup wiring,
the server RU/EN allowlist and updated media CSP apply on its next normal launch.
