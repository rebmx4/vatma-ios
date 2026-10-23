# Task 2 — scoped spec + quality review

Дата: 2026-10-23. Объём: shared BrowserUI и preview cookie/localization/appearance
integration из task-2-report.md. Native Task 1 повторно не ревизовался.

## Вердикт

- Spec verdict: соответствует проверенному объёму Task 2.
- Quality verdict: APPROVE; подтверждённых Critical, Important или Minor дефектов
  в просмотренном объёме не найдено.
- Windows/Responsively evidence не подтверждает iOS/WebKit runtime behavior.

## Cookie authority и текущий профиль

Проверены preview cookie-rpc.js, cookie-host.mjs:4–16,
electron-cookies.cjs:6–15 и узкие соседние host/server участки.

- Привилегированный host принимает только ожидаемый origin, action и request ID;
  source обязан совпасть с contentWindow зарегистрированного iframe[data-atma-panel].
  Произвольный website webview или дочерний iframe такой проверке не соответствует.
- Context берётся из host-owned dataset найденного iframe, а не из тела сообщения.
  Текущий profileId получается из /api/state с X-Atma-Token.
  Сервер проверяет token, origin при его наличии и существование context.
- Partition выводится из authenticated deviceName/profileId. Формула совпадает
  с host.mjs:69–70, создающим настоящий site webview; UI не задаёт partition.
- Electron handler допускает зарегистрированные при установке window webContents
  с file URL и проверяет senderFrame относительно mainFrame. Дополнительно
  проверяются action, формат partition и размещение sessionData на D:.
- Ответ отправляется только исходному UI iframe с exact target origin.
  Cookie UI принимает ответ только от parentWindow с совпадающими type/id.
- В прочитанных файлах нет вывода cookie values в log/export. Cookie list
  остаётся ответом UI RPC. Пользовательские cookies reviewer не запрашивал.

## Точное удаление, HttpOnly и XSS

Проверены cookie-store.cjs:3–26, cookies-ui.js:15–38,
соответствующие branches BrowserUI/app.js и cookie-store.test.mjs.

Cookie identity включает scope/domain/path/name и не зависит от value.
Удаление повторно перечисляет cookies выбранного store и истекает только
совпавшие tuples с точными path/name и domain либо host-only domain semantics.
Сохраняются secure/httpOnly/sameSite; broad cookies.remove и очистки иных
типов website data/downloads здесь нет. All использует только выбранный store.

Raw name/domain/path/value вставляются как textContent; идентификаторы задаются
через dataset, а не HTML. Cookie content помечен data-no-translate.
Значения не интерполируются в markup/JavaScript. File names экранируются и
исключены из перевода; website titles в tabs-view.js выводятся textContent
и также исключаются. Подтверждённого raw-cookie XSS пути не найдено.

Результат предыдущей изолированной Electron проверки HttpOnly и двух путей
использован из отчёта. Сам reviewer реальных cookie mutations не выполнял.

## RU/EN и пользовательские данные

Проверены assets/i18n.js, assets/locale-en.js, app.js settingsPickers,
language change, user-name rendering и tabs-view.js.

- Допустимы только ru/en; сайтам предлагаются ru-RU/en-US. Неизвестный старый
  interface language нормализуется в ru.
- Localization хранит исходные тексты/attributes в WeakMap и обновляет их при
  последующих перестроениях. Переключение языка сохраняет только LANGUAGE_KEY,
  не перезагружает страницу и не записывает apps/vault/PIN/tabs.
- User app names, website titles, file names и cookie content исключаются.
  Dynamic label prefixes переводятся с сохранением пользовательского suffix.
  Input values localization не изменяет.
- Custom settings dialogs используют экранированные option labels и сохраняют
  value исходного select. Native locale/timezone/probe capability=false отключает
  недоступные controls и сообщает ограничение.
- Native RPC/atma-native-state соединены с существующим consume; отдельные
  site renderers не получают UI DOM.

Отсутствие native appearance/app-icon обработчиков не рассматривается как
дефект Task 2: их реализация явно отнесена к Task 3.

## Appearance, media, layout и blocker

Прочитаны appearance.css, index.html, cookies.css, appearance-related branches
app.js и узкие branches file preview. APiKS light/dark tokens присутствуют,
auto разрешается через prefers-color-scheme. Cookies list прокручивается внутри
flex column; search следует после списка. Media preview использует blob URL
и controls. Preview server CSP теперь допускает media-src self/blob.

Прочитаны существующий out/cookies-appearance-verification.json и отчёт о
20 passed tests: phone 428×926 и iPad 768×1024 отмечены passed без overflow.
Эти проверки reviewer не повторял. Состояние уже запущенного server не менялось;
обновлённые startup wiring/RU-EN allowlist/CSP активируются при обычном следующем
запуске, как указано в task report.

Blocker control вызывает native blocker/set с enabled и восстанавливает
checkbox при ошибке. Встроенный content-blocker.json просмотрен вместе с
docs/content-blocker.md: это 27 начальных third-party доменных правил;
ограниченная полнота и отсутствие Windows native blocker явно документированы.
WKContentRuleList compilation/runtime здесь не проверены.

## Что фактически выполнено и осталось

Прочитаны task-2-report.md; перечисленные shared UI/cookie preview modules;
точечные соседние app.js/host.mjs/server.mjs/appearance.js участки для проверки
конкретных связей; i18n.test.mjs/cookie-store.test.mjs и существующий evidence JSON.
Graph-first поиск atma-mobile-preview дал 0, atma-ios-release — только старые
ATMA/Settings.swift symbols. Поэтому использованы известные текущие файлы.

Reviewer записал только этот отчёт на D: и прочитал его обратно.
Код и конфигурация не менялись; tests/server/Responsively/CI/build/install,
публикации и commit/push не запускались. Runtime token/config файлы не читались.
Пользовательские cookies/PIN/tabs не удалялись и не изменялись.

Остаются Task 3 native appearance/app-icon и согласованная macOS/iOS проверка
WebKit bridge/layout, native icon changes и content-rule compilation.
