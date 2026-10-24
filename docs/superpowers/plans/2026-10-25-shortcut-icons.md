# Shortcut artwork correction

Owner requests: original site artwork on new shortcuts; a simple optional choice of alternative icons in the editor. Existing authorization covers implementation, GitHub builds and TestFlight. Website chat notifications remain a separate unresolved capability; do not represent them as implemented.

- [x] Inspect the icon path and reproduce editor persistence/races. Four JavaScript regressions observed RED then GREEN.
- [x] Keep the 512 KiB metadata prefix even when the complete HTML response is larger. Existing image/manifest limits and credential isolation remain. Real Avito/RUTUBE/YouTube pages exceed the old whole-document limit.
- [x] Add original website icon and six local alternatives, persist the selected style, and stop old icon lookups overriding a later choice. Editing a built-in shortcut to a new URL opts into the new site's artwork.
- [x] Run source/JavaScript validation, independent review and exact-revision iPhone/iPad tests. Verify a large HTML page and actual editor/desktop icon persistence across UI reload.
- [x] Produce the verified TestFlight build with current artwork and publication assets. No notification claim is added.

Рекомендуемая модель для реализации: GPT-6.1-Sol, уровень high. Причина: согласуются нативная загрузка ресурсов, сохранение ярлыков и редактор.

## Evidence before native execution
- Previous revision60ed234 passed exact run40137615232:43nativeunit,2iPhoneUI,2iPadUI; artifact12577118793 downloaded and verified. It does not verify the new icon changes.
- New local checks:59JavaScript cases pass, source/resource validation268productfiles passes, changed JS syntax and git diff checks pass. Seven meaningful JS cases were observed failing then passing across style persistence, changed default URL, stale lookup/save, closed editor and Add panel.
- Independent review found an optional snapshot API mismatch and a test-file size issue before CI. Removed the unnecessary snapshot and extracted unchanged JSON/RGB assertions into a shared test helper. The main native scenario file is395lines.
- Review also reproduced a stale form submit overwriting a newer choice. An editor token/panel guard and two regressions now protect both storage and later panel closing.
- Native UTF-8 boundary regression and strict image/manifest-limit checks are written but require Xcode execution. A bounded HTML prefix trims only an incomplete1–3byte UTF-8 tail before legacy decoding.

- Final independent review: no open Critical/Important/Minor findings; reviewer ran21targetedJavaScript checks and diff validation. New native execution is still required.

## Delivered
- Application source a879df5306cd232616e6c1a17fc123565e7197cc passed native run40141124891:46unit,2iPhoneUI,2iPadUI. Both large-page/icon and editor/reload/return-to-original cases passed.
- Signed run40142631653 uploaded build1.0.0(1) to new app6826668990. Apple processing VALID. Local IPA comparison matched all34exact LF source resources; signature verification ran successfully in macOS CI.
- Owner added once to the new internal group ATMA — владелец; internal build state IN_BETA_TESTING. External Test1 submission WAITING_FOR_BETA_REVIEW; link https://testflight.apple.com/join/ATXfWhKZ waits for that decision.
- Five real iPhone and five iPad screenshots accepted COMPLETE. Public App Review submission2d5725ca-49c7-4b00-9c54-207ca5ed9d36 and version state WAITING_FOR_REVIEW; release AFTER_APPROVAL. App is not yet publicly released.
- Website chat notifications and badges remain unimplemented and are disclosed as unsupported in this build. No push backend was deployed.
