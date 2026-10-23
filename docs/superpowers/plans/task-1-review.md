# Task 1 — native review

Дата: 2026-10-23. Проверен task-1-review.patch и соответствующие исходники task 1.
Изменения кода не выполнялись. Этот отчёт — единственная запись reviewer.

## Вердикт

- Spec verdict: основная архитектура соответствует brief, но переход навигации в загрузку файла требует исправления до принятия task 1.
- Quality verdict: REQUEST_CHANGES — 0 Critical, 1 Important, 2 Minor.
- Это статический review на Windows, а не подтверждение компиляции или поведения на iOS.

## Important

### I1. Переход navigation → WKDownload не завершает состояние вкладки

Место: `BrowserNative/BrowserNavigation.swift:34`, `:39`, `:67`;
связанные участки: `BrowserNative/BrowserController.swift:43`, `:189`,
`BrowserNative/DownloadService.swift:112`.

Оба `didBecome download` только вызывают `downloads.attach(download)`.
К этому моменту `didStartProvisionalNavigation` уже мог записать `loading = true`.
Ветка перехода в download не сбрасывает loading/error и не публикует состояние
исходной вкладки. Успешное завершение WKDownload вызывает только
`didChange(nil) → publish()`, который повторно сериализует сохранённое состояние
BrowserTab и не перечитывает isLoading.

Если WebKit завершает прерванную навигацию через cancellation (-999), обработчик
на строке 67 полностью пропускает обновление: loading может остаться true.
Если он сообщает policy interruption, тот записывается как ошибка сайта, хотя
файл загружается штатно. Callback завершения файла очищает только nativeError,
а не BrowserTab.error. Конкретный порядок callbacks на устройстве здесь не
воспроизведён; отсутствие собственного terminal transition подтверждено кодом.

Нужно связать download с исходной вкладкой, явно завершать её navigation state
и отличать ожидаемое превращение навигации в download от настоящей ошибки.
Не следует подавлять все ошибки произвольной навигации с кодом 102.
После исправления: сценарий открытия HTTP attachment в текущей вкладке,
сохранение файла, loading=false и отсутствие ложной ошибки; отдельно реальный
сбой загрузки должен оставаться видимым.

Apple описывает превращение response в отдельный download и отдельные callbacks
его прогресса: [navigationResponse didBecome](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webview(_:navigationresponse:didbecome:)),
[WKDownloadDelegate](https://developer.apple.com/documentation/webkit/wkdownloaddelegate).

## Minor

### M1. Исключение блокировщика может пережить redirect на другой hostname

Место: `BrowserNative/BrowserNavigation.swift:22`;
`BrowserNative/SiteSecurity.swift:79`.

Правило включается для hostname первоначального navigationAction. Обработчика
server redirect нет, а didCommit/didFinish не обновляют content rule list.
При переходе с исключённого host A через HTTP redirect на B renderer может
сохранить отключённый blocker, хотя state для B сообщает enabled=true.
Обратный переход может сохранить блокировку для исключённого B.
Требуется синхронизация с фактическим top-level hostname без применения
исключений к посторонним хостам. На устройстве не воспроизведено.

### M2. Ограничение имени скачанного файла не учитывает UTF-8

Место: `BrowserNative/DownloadService.swift:98`, `:104`.

prefix(160) ограничивает Swift Characters, а файловая система ограничивает
длину компонента в байтах. Длинное имя из кириллицы/emoji может превысить
допустимую длину даже после такого сокращения; при коллизии добавляется UUID.
Результат — ошибка сохранения обычного файла с Unicode-именем.
Ограничивать UTF-8 длину с запасом под суффикс и расширение.
Это вывод по коду; реальная файловая операция iOS не запускалась.

## Что проверено

- Прочитаны task-1-brief.md, task-1-report.md, docs/standalone-ios.md и task 1 patch;
  вручную просмотрены девять production Swift-файлов и BrowserSecurityTests.swift.
- Проверены границы UI/site WKWebViews, provenance RPC, ветвления
  navigation/download/TLS callbacks, табы/профили, cookie identity/deletion,
  доступ к файлам и статический HTTP handler.
- UI получает единственный reply handler; RPC проверяет identity, main frame,
  scheme, host и port. Site renderers получают отдельные конфигурации.
  Безусловного TLS bypass или пути выдачи cookie values в logs/export не найдено.
- Persistent data store получает UUID, сохраняемый отдельно для profile ID.
  Cookie deletion использует текущий захваченный store и точные ID; вызова
  blanket deletion storage/downloads в проверенных файлах нет.
- Сервер задаёт loopback endpoint, сохраняет первый успешный port, не выбирает
  новый origin при bind failure, обслуживает только перечисленные bundled
  ресурсы; GET, Host, ограничение заголовка и запрет traversal присутствуют.
- TLS fallback сохраняет SSL policies и системные anchors, проверяет bundled
  PEM/DER hashes и RSA key type. Видимые synchronous delegate completion paths
  возвращают решение однократно; асинхронные paths делегированы WebKit/UI.
- Подписи persistent store, reply handler и WKDownloadDelegate сопоставлены
  с первичными Apple/WebKit документами. Подтверждённого source-level
  API/type blocker не найдено; это не заменяет Swift type checking.
  [Persistent profile API](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/),
  [reply handler API](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/addscriptmessagehandler(_:contentworld:name:)).
- Точечно прочитан SWIFT_VERSION=5.0 из project.yml для оценки concurrency риска.
  Shared UI проверен только на использование системных JS dialogs; совпадений
  confirm/prompt/alert в BrowserUI/app.js не найдено.
- Поиск символов через graph tools не дал результата без project identifier;
  с учётом уже указанного в task report отсутствия индекса использованы только
  известные файлы из patch. Индексация не запускалась.

## Не проверено и остаётся

Swift/Xcode, XCTest, сборка, Simulator/устройство, CI, установки и публикации
не запускались. Структурные проверки из task-1-report.md повторно не запускались.
Размеры файлов и отсутствие зависимостей опираются на прочитанный patch и прежний
отчёт, а не на новую автоматическую проверку.

Сборка project/Info.plist, упаковка certificates и совместимость всего BrowserUI
остаются интеграционным объёмом parent. Путь certificates/manifest.json в корне
репозитория при точечном чтении отсутствовал; certificate packaging task 1 brief
прямо передаёт parent, поэтому это не включено в дефекты worker.

После I1 требуется целевой сценарий download; затем macOS compile/XCTest и
согласованные device tests для persistence, TLS, bridge и layout.
