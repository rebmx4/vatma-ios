# Приватные уведомления ATMA — Implementation Plan для GPT Sol

> **СТАТУС 25.10.2026: ПРИОСТАНОВЛЕНО НА GATE A.** [Apple DTS](https://developer.apple.com/forums/thread/760767) прямо подтверждает: Web Push не работает в `WKWebView`. Поэтому изложенную ниже схему «Web Push сайта → relay → APNs» нельзя реализовать как заявлено в текущем браузере. Подготовленный локальный probe проверяет только чистоту диагностического отчёта, а не доставку. Не выполнять задачи 2–8, не запускать relay и не выпускать сборку с обещанием уведомлений, пока не найден и не проверен иной официальный источник событий для VK/Авито либо владелец не изменил требование. Подробности: [матрица источников](../../research/2026-10-25-notification-provider-matrix.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Исполнение — GPT Sol; этот документ сам по себе не разрешает запуск субагентов или реализацию.

**Goal:** Уведомления только о сообщениях соцсетей, без доступа сервера ATMA к переписке, с проверенными счётчиками ярлыков и общей меткой iOS.

**Architecture:** Сначала доказать совместимость источника. Затем провести зашифрованный Web Push через собственный relay и APNs в Notification Service Extension, расшифровать на iPhone, обновить общий локальный ledger. Не превращать экспериментальную интеграцию в обещание всех соцсетей.

**Tech Stack:** iOS 17+, Swift 5, UIKit/WebKit, CryptoKit, Keychain, UserNotifications, SQLite; существующий JS UI; Python 3.12 + SQLite + uvicorn + httpx[http2] + cryptography для relay.

**Spec:** [Архитектура и условия допуска](../specs/2026-10-25-private-social-notifications.md). Прочитать целиком до реализации.

## Global Constraints

- Сейчас запрошен только план. Код, сборки, сервер и Apple submission при подготовке плана не менять.
- Рабочая копия `D:/Projects/atma-browser-ios`, ветка `atma-browser-testflight`, origin `https://github.com/rebmx4/vatma-ios.git`. `main` содержит старое приложение.
- База плана HEAD `6f22e1715ffc5685f1444dd25b78eabdc1d52b5d`; последняя проверенная сборка 1.0.0(2), source `261de4976185dfa437a1c455a52e991cacc5eca3`.
- Все новые файлы/кэши на D:. TEMP/TMP `D:/tmp`, npm cache `D:/npm-cache`, Python cache `D:/caches/python`; venv relay внутри его каталога.
- Не читать/редактировать/stage/delete владельческий `docs/superpowers/plans/task-1-review.patch`. Перед работой проверить git status и актуальные AGENTS.md.
- Граф кода первым; актуальный cache `D:/caches/codebase-memory-mcp`, CLI env `CBM_CACHE_DIR` указывает туда. Имя проекта `atma-browser-ios`.
- Никаких cookie/паролей/OAuth соцсетей или private key/auth Web Push на relay. Только synthetic test accounts и данные в тестах.
- Никакого ИИ для анализа переписки, фонового опроса сайтов каждую минуту, VoIP/audio-обходов и скрытого включения после App Review.
- При ошибке обязательной проверки остановить выпуск; не повторять одинаковые платные/облачные сборки без исправленного основания.
- Старый App Review и уже работающие сборки не отзывать. Codemagic не запускать. Платный хостинг автоматически не подключать.
- Исследование протокола на компьютере возможно без iOS-сборки; настоящее APNs/NSE-поведение требует подписанного диагностического билда на iPhone.

## Review Focus

1. Выход/смена аккаунта и поздний push не дают уведомление или счётчик от предыдущего аккаунта — задачи 1, 3, 5, 8.
2. Порядок событий, два сообщения в одном чате, чтение с другого устройства и дубликаты ярлыка не искажают сумму — задачи 1, 3, 8.
3. Вредоносный iframe/переход на другой origin не получает права UI RPC, ключи или чужую подписку — задача 4.
4. Тайм-аут NSE, холодный старт и большой payload не раскрывают текст и не рисуют случайную цифру — задачи 2, 5, 8.
5. Лайки/реклама, отключённые alerts, отозванное разрешение и отсутствие entitlement не маскируются под работающие сообщения — задачи 1, 5, 6, 8.

## Карта существующих точек интеграции

| Файл / символ | Изменение при реализации |
|---|---|
| `BrowserNative/BrowserController.swift`: AppDelegate, `renderer`, `state`, `publish` | APNs callbacks/coordinator; узкая регистрация site bridge; снимок notification state |
| `BrowserNative/BrowserRPC.swift`: `userContentController`, `dispatch`, `perform` | UI-команды уведомлений, сохранить проверку bundled UI + main frame + origin |
| `BrowserNative/BrowserModels.swift` | Идентификатор обычной сессии; не переносить push в private store |
| `BrowserNative/CookieService.swift`, `BrowserNative/BrowserPrivacy.swift` | Отзыв при очистке данных и жизненный цикл приватных вкладок |
| `BrowserUI/app.js`: `saveCurrentSite`, `renderAppForm`, `renderApps`, `saveApps` | Предложение включить, настройка, отображение снимка, удаление/перенос ярлыка |
| `BrowserUI/app.css`, `BrowserUI/assets/locale-en.js`, `BrowserUI/assets/legal.js` | Значки, состояния, точные RU/EN объяснения |
| `project.yml`, `release/ci.sh`, `release/validate.py`, `release/verify_ipa.py`, `release/verify_signing.py` | NSE target, entitlements, подпись и проверка обоих bundles |
| `.github/workflows/atma-ios-check.yml`, `.github/workflows/atma-testflight.yml` | Сохранить exact-SHA gate, включить целевые новые проверки |

Новые компоненты создаются только после соответствующего gate. Не переписывать большой `app.js` целиком; новая логика в малых модулях. Каждый новый файл ≤400 строк.

## Контракт состояния

Определить в `NotificationShared/NotificationTypes.swift`:

- `ProviderID`: `vk | avito`; `CapabilityState`: `unknown | blocked | prototype | verified`.
- `NotificationIdentity`: `provider`, `canonicalOrigin`, случайный `accountSessionID`, `epoch`, `subscriptionID`, набор `shortcutIDs`. Имена/ID аккаунта соцсети наружу не передавать.
- `UnreadState`: `known(count: Int, revision: String, observedAt: Date) | stale(lastKnown: Int?, reason: String) | unknown`.
- `MessageSignal`: `eventID: String`, `kind: message | read | other`, `unread: Int?`, `revision: String?`. Это локальная структура без sender/text/body.
- `NotificationSnapshot`: `sequence: Int64`, `byShortcut: [String: ShortcutNotificationState]`, `totalUnread: Int?`, `authorization: String`; отсутствие точной суммы — `nil`, не 0.
- `ShortcutNotificationState`: `enabled`, `capability`, `subscriptionStatus`, `unread`, `updatedAt`, публичный `reasonCode`; никаких ключей.

Для каждого сайта отдельно определить сравнение revision и канонические origins по исследованию задачи 1. Номер доставки relay не подставлять вместо revision. Никаких выдуманных селекторов/API или универсального regex по заголовку страницы.

## Task 1: Доказать источник уведомлений, начиная с ВК

**Files:** создать `docs/research/2026-10-25-notification-provider-matrix.md`, `tools/notification-probe/README.md`, `tools/notification-probe/probe.mjs`, `tests/notification-probe.test.mjs`. Протокол и synthetic fixtures хранить в `tools/notification-probe/fixtures/`; приватные временные данные — только в gitignored `out/notification-probe/`.
**Interfaces:** результат — матрица `provider, origins, endpointAccepted, encoding, messageOnly, eventID, unreadUnit, authoritativeCount, revisionOrder, remoteReadSync, logoutSignal, revocation, evidence, verdict`.

- [ ] Проверить актуальные официальные Push API/условия сайта и существующую browser registration с отдельным тестовым аккаунтом. Если вход недоступен, запросить у владельца вход вручную; пароли/коды в чат не просить.
- [ ] Написать и запустить `node --test tests/notification-probe.test.mjs`: экспорт отчёта не содержит `Cookie`, `Authorization`, текста synthetic message, токенов и полного endpoint; сохраняются только разрешённые поля матрицы.
- [ ] Сделать минимальный HTTPS receiver для ciphertext и локальное создание ключей. Его наружный запуск выполняется только в согласованной инфраструктуре; не использовать публичные request-bin, HAR с чужими данными или платный tunnel.
- [ ] Проверить, может ли обычная страница зарегистрировать произвольный стандартный endpoint, без подделки FCM credentials. Допустим клиентский адаптер обычного потока subscribe; запрещено обходить ограничения сервера сайта.
- [ ] С отдельного тестового аккаунта отправить два сообщения в одном чате и одно в другом; затем лайк/несообщение, прочтение с другого устройства, выход/смену аккаунта. Расшифровка — локально, сохранение только типов и чисел. При отсутствии исходных событий зафиксировать точный блокер.
- [ ] Отдельно проверить Авито по той же матрице; бизнес-API не выдавать за доступ обычного личного аккаунта.
- [ ] Gate A: разрешить дальнейший прототип только для сайта, который принимает endpoint и реально отправляет encrypted events; до production дополнительно нужны все условия spec. При блокировке обоих источников остановить реализацию интеграции, представить доказательства и официальные альтернативы; не собирать ещё один релиз без уведомлений.

## Task 2: Relay, который не умеет читать сообщения

**Files:** создать `notification-relay/{README.md,requirements.in,requirements.lock,server.py,registry.py,webpush.py,apns.py}`, `notification-relay/tests/{test_registry.py,test_webpush.py,test_apns.py}`.
**Interfaces:** `POST /v1/installations` выдаёт случайные installID/manageSecret; `PUT /v1/installations/{id}` обновляет APNs token с авторизацией; `POST /v1/subscriptions` принимает installID, VAPID public key и выдаёт opaque endpoint; `DELETE /v1/subscriptions/{id}` отзывает. `POST /push/{opaque}` принимает ciphertext от сайта; `GET /v1/payloads/{id}` отдаёт ciphertext только его установке. Секрет установки хранить на телефоне в Keychain, на сервере — hash.

- [ ] Написать тесты отклонения чужого manageSecret, VAPID key, неверного JWT audience/expiry, неизвестного/revoked endpoint; ожидаемые 401/403/404/410. При смене APNs token старый больше не используется; unregister удаляет mapping.
- [ ] Поднять venv в `notification-relay/.venv`, pip cache на D:, закрепить совместимые версии зависимостей после проверки официальных источников; добавить lock с хешами. Не менять системный Python.
- [ ] Реализовать TLS за проверенным reverse proxy, SQLite registry/очередь, VAPID ES256 и APNs HTTP/2. APNs .p8 только в серверном secret storage; не путать с App Store Connect upload key.
- [ ] Добавить лимиты: ciphertext ≤64 KiB; endpoint случайный 32 байта; TTL=min(TTL источника,24 ч); bounded очередь и 429/backoff; отдельный лимит создания installations. Доступный порт и домен проверить до deployment, не выдумывать существующий адрес.
- [ ] Формировать исходный APNs alert `ATMA / У вас уведомление`, `mutable-content=1`, без `badge` и имени соцсети. Inline только если весь JSON ≤4096 байт; иначе opaque payload reference с ограниченным TTL и авторизованной загрузкой. Не добавлять текст из входящего тела.
- [ ] Тесты: большой пакет не усечён; 410 удаляет очередь; 429/5xx APNs ограниченно повторяются; APNs Unregistered деактивирует token; повтор ciphertext не раздувает очередь; request body/access URL/секреты не попадают в логи.
- [ ] Запустить из `notification-relay`: `.venv/Scripts/python -B -m unittest discover -s tests -v`; ожидаются все PASS с mock APNs. Затем synthetic sender получает 201 и ciphertext на локальном receiver; plaintext/key отсутствуют в relay DB/logs.

## Task 3: Ключи и один ledger на iPhone

**Files:** создать `NotificationShared/{NotificationTypes.swift,PushKeyStore.swift,WebPushDecryptor.swift,NotificationLedger.swift,NotificationProviderAdapter.swift}`, `BrowserNativeTests/{WebPushCryptoTests.swift,NotificationLedgerTests.swift,NotificationKeyStoreTests.swift}`. Подтверждённые адаптеры — `NotificationShared/Providers/VKNotificationAdapter.swift` и `NotificationShared/Providers/AvitoNotificationAdapter.swift`, только для прошедших Gate A сайтов. Общие файлы включить в будущие app/NSE targets.
**Interfaces:** `PushKeyStore.create(identity:) throws -> WebPushPublicKeys`, `delete(subscriptionID:)`; `WebPushDecryptor.decrypt(_ encrypted: Data, keys: WebPushPrivateKeys) throws -> Data`; `NotificationProviderAdapter.decode(_ plaintext: Data) throws -> MessageSignal`; `NotificationLedger.apply(_:identity:) throws -> NotificationSnapshot`, `revoke(subscriptionID:)`, `snapshot()`.

- [ ] Зафиксировать типы контракта; `WebPushPublicKeys` содержит p256dh/auth, `WebPushPrivateKeys` — приватный P-256/auth только в процессе iPhone. Никакой передачи ключей через общий UI snapshot.
- [ ] Тесты RFC8291 Section5/AppendixA и независимого synthetic sender: правильная расшифровка, неверные ключ/тег/соль, truncated record, перепутанный origin, размер; несовместимый старый aesgcm явно отклоняется.
- [ ] Реализовать RFC8291 через CryptoKit без своей криптографии; ключи с `AfterFirstUnlockThisDeviceOnly` в общей Keychain access group. Включить app/NSE единственный общий источник алгоритма.
- [ ] Реализовать SQLite ledger с транзакциями и защитой файлов `completeUntilFirstUserAuthentication`. Хранить только счётчики/версии/эпохи, eventID как локальный HMAC; plaintext не сохранять. Состояние private/PIN не переносить в публичный ledger без согласия.
- [ ] Тесты ledger: VK2+Avito4→6; два ярлыка VK всё ещё→6; repeat/out-of-order не меняют новое состояние; подтверждённое прочтение VK→0 даёт4; unknown/stale не превращаются в точную сумму; старый epoch отклонён; два одновременных процесса не теряют update.
- [ ] Добавить provider adapters только для форматов из Gate A; неизвестный формат возвращает unsupported/stale. Не читать текст для эвристической классификации, не выполнять загруженный JS, не обращаться из NSE за перепиской.
- [ ] Проверить на macOS целевые native tests: `xcodebuild test -project ATMA.xcodeproj -scheme ATMA -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath "$PWD/.cache/notification-tests" -only-testing:BrowserNativeTests/WebPushCryptoTests -only-testing:BrowserNativeTests/NotificationLedgerTests -only-testing:BrowserNativeTests/NotificationKeyStoreTests CODE_SIGNING_ALLOWED=NO`; все PASS. `$SIM_ID` взять из существующего `release/simulators.py`, не угадывать.

## Task 4: Узкий мост подписки для сайта

**Files:** создать `BrowserNative/{BrowserNotificationCoordinator.swift,WebsitePushBridge.swift,NotificationRelayClient.swift}`, `BrowserUI/assets/site-push-subscription.js`, `BrowserNativeTests/WebsitePushBridgeTests.swift`, `tests/site-push-subscription.test.mjs`; изменить `BrowserController.swift`, `BrowserModels.swift`, `CookieService.swift`, `BrowserPrivacy.swift` только в точках интеграции.
**Interfaces:** `enable(shortcutID:origin:) async throws -> ShortcutNotificationState`, `disable(shortcutID:) async throws`, `subscribe(origin:vapidKey:) async throws -> PushSubscriptionDTO`, `getSubscription(origin:)`, `unsubscribe(origin:)`; DTO — стандартные endpoint/expirationTime/keys p256dh/auth. Приватный ключ никогда не возвращается в JS.

- [ ] Тесты: untrusted origin, iframe, http, incognito, отсутствующее согласие, redirect во время async subscribe, stale tab/session — отказ; site bridge не может вызвать `home`, cookies/delete или выполнить произвольный код.
- [ ] Реализовать отдельный handler, не добавлять `atma` UI handler в site WebView. Проверять реальный `frameInfo.securityOrigin`, webView identity, main frame и эпоху на входе и после await. Разрешённые origins получать из проверенной матрицы.
- [ ] Создавать subscription/public keys только после пользовательского согласия и OS permission; регистрировать на сайте по адаптеру Gate A. Не считать enabled до подтверждения сервера сайта. При частичной ошибке отозвать endpoint/ключи.
- [ ] Подключить hook в `renderer` до загрузки сайта; отдельно проверить, что метод регистрации сайта работает в настоящем WKWebView, а не только desktop probe. Не ломать service workers и другие страницы.
- [ ] Отзыв при cookies/delete, logout, account change; раздельные epochs; отключение offline не возвращает подписку в enabled после перезапуска. Удаление/смена URL последнего ярлыка отзывает подписку, дубликат сохраняет оставшуюся привязку.
- [ ] Запустить `node --test tests/site-push-subscription.test.mjs` и native `-only-testing:BrowserNativeTests/WebsitePushBridgeTests`; все PASS. Gate B: synthetic сайт успешно подписывается из WKWebView; неподдерживаемые реальные сайты остаются blocked.

## Task 5: APNs и Notification Service Extension

**Files:** создать `NotificationService/{NotificationService.swift,Info.plist,NotificationService.entitlements}`, `BrowserResources/ATMA.entitlements`, `NotificationShared/NotificationPresentation.swift`, `BrowserNativeTests/NotificationPresentationTests.swift`; изменить `project.yml`, AppDelegate в `BrowserController.swift`, signing/IPA scripts из карты.
**Interfaces:** `NotificationPresentation.make(signal:snapshot:identity:) -> UNMutableNotificationContent`; единственный completion guard NSE; APNs callbacks передают token coordinator; уведомление несёт локально проверяемый subscriptionID/epoch, не произвольную команду.

- [ ] XcodeGen: extension bundle `ru.atma.browser.notification-service`, App Group `group.ru.atma.browser.notifications`, общая Keychain group с AppIdentifierPrefix; embedding `.appex`, `APPLICATION_EXTENSION_API_ONLY=YES`. Существующий bundle ATMA `ru.atma.browser` сохраняется.
- [ ] Подготовить Apple identifiers/capabilities/profiles для обоих targets, APNs provider key, production/sandbox разделение. При message-only отсутствии подготовить запрос filtering entitlement; отправка обращения Apple требует отдельного явного поручения, одобрение нельзя считать полученным заранее.
- [ ] Тесты: при успешном message событии показывается только заданная общая фраза; sender/body/attachments не копируются; unknown event, timeout, fetch failure, недоступный Keychain и malformed payload дают безопасный fallback без новой цифры; completion вызывается ровно один раз.
- [ ] Реализовать загрузку ciphertext при необходимости, decrypt→provider adapter→ledger→generic presentation. Установить собственный deadline20сек для завершения до системного лимита; отменять сети в `serviceExtensionTimeWillExpire`.
- [ ] Фильтровать other/read/dedup/revoked только законным механизмом после выданного entitlement; без него не выдавать такое подавление за работающее. Предпочитать message-only source; нестабильная классификация блокирует заявленную поддержку.
- [ ] Обрабатывать нажатие через subscription→существующий shortcut→проверенный URL; не открывать переданный сервером произвольный адрес. PIN-страница требует PIN. Запуск ATMA не обнуляет сообщения автоматически.
- [ ] Native presentation tests PASS; `release/verify_signing.py` и `verify_ipa.py` проверяют extension, App Group, Keychain, aps-environment, версии bundles и отсутствие server .p8/секретов. Отсутствующая подпись расширения останавливает upload.

## Task 6: Пользовательское управление и цифры

**Files:** создать `BrowserUI/assets/notifications-ui.js`, `tests/notifications-ui.test.mjs`; изменить `BrowserUI/app.js`, `app.css`, `assets/locale-en.js`, `BrowserNative/BrowserRPC.swift`, `BrowserController.swift`.
**Interfaces:** UI RPC `notifications/sync-shortcuts {revision, entries:[{id,url,scope}]}`, `notifications/state`, `notifications/enable {shortcutID}`, `notifications/disable {shortcutID}`, `notifications/open-settings`. Только bundled UI передаёт актуальные ярлыки; native coordinator проверяет URL/origin, сохраняет производную привязку в registry и возвращает применённую revision. Источник ярлыков остаётся существующий `saveApps`, источник счётчиков — ledger. Старые revision отклоняются; website handler не имеет этих команд. State только из `NotificationSnapshot`.

- [ ] После создания поддерживаемого обычного ярлыка предложить «Включить уведомления о новых сообщениях?», действия «Включить»/«Позже». OS prompt вызывается после «Включить». При неизвестном сайте показать точную причину недоступности, не фиктивный переключатель.
- [ ] После сохранения ярлыков и при старте UI синхронизировать registry; enable разрешать только после ack текущей revision. Удаление/смена URL/PIN-перенос сверяются до включения новой подписки; при сбое синхронизации показать ошибку и сохранить требуемое отключение для retry. Скрытые PIN-URL не передавать в публичный registry: список допустимых ярлыков исключает закрытые страницы.
- [ ] В `renderAppForm` добавить настройку для существующих ярлыков; состояния: выключено, включается, включено, нужен вход, запрещено iOS, источник недоступен. При отказе iOS не повторять prompt бесконечно; дать переход в Settings.
- [ ] Значок с белым числом на красном фоне — справа сверху иконки, `99+` на UI при >99; accessibility label включает полное число. Обновлять значок без полной перестройки desktop и потери drag/hold750ms.
- [ ] Общую метку iOS задаёт native ledger через системный API; UI не суммирует отдельный счётчик самостоятельно. Условие запуска NSE при включённых alerts объяснить при выключении пользователем баннеров; не обещать badge-only работу.
- [ ] Тесты: создание/редактирование, отказ permission, offline retry/revoke, дубликаты и удаление, смена URL, папки, PIN-перенос и incognito, stale snapshot sequence. Старые ярлыки после миграции остаются с уведомлениями off.
- [ ] `node --test tests/notifications-ui.test.mjs tests/native-state-order.test.mjs tests/desktop-hold.test.mjs tests/shortcut-launch.test.mjs tests/quick-add-privacy.test.mjs`; все PASS. Проверить native UI toggle и badge snapshot целевым сценарием iPhone/iPad.

## Task 7: Проверить конфиденциальность и эксплуатацию

**Files:** создать `docs/security/notification-data-flow.md`, `notification-relay/tests/test_privacy.py`, `docs/operations/notification-relay.md`; изменить `BrowserUI/assets/legal.js`, README и актуальные privacy/store тексты по обнаруженным каноническим файлам.
**Interfaces:** отчёт перечисляет каждое поле, получателя, срок хранения и удаление; не содержит реальных идентификаторов/секретов.

- [ ] Synthetic canary сообщение не появляется в relay логах/БД, APNs plaintext, crash diagnostics, JS UI и telemetry. Записать схему движения ciphertext и доказательство отсутствия ключа у relay; простой поиск canary не считать единственным криптографическим доказательством.
- [ ] Подтвердить: app/private keys не экспортируются, backup не содержит plaintext, отключение удаляет очереди/ключи, VAPID и management API нельзя использовать как открытый relay. Тесты `test_privacy.py` PASS.
- [ ] Предоставить конкретный deployment manifest, HTTPS домен, ресурсы, квоты/расходы и инструкцию rollback. Не разворачивать на существующем сервере без актуального разрешения; платные услуги не подключать. Проверку публичного сайта вести только на synthetic аккаунте.
- [ ] Убрать прежнее «не реализовано» только для фактически работающей части; написать «не читаем содержимое, пересылаем зашифрованные пакеты; обрабатываем технические данные доставки». Не писать «никакие данные не передаются».
- [ ] Подготовить точные App Privacy/Review notes по реальным данным, зависимостям и поведению; не менять текущий submission и не утверждать, что Apple уже одобрила архитектуру.

## Task 8: Одна диагностическая сборка и реальные приёмочные испытания

**Files:** создать `docs/releases/notification-device-acceptance.md`; при необходимости обновить `.github/workflows/atma-ios-check.yml`, `.github/workflows/atma-testflight.yml`, `tests/test_github_ci.py`, `tests/test_standalone.py` для новых targets/resources.
**Interfaces:** отчёт привязан к exact SHA, build number, версии iOS, provider, состоянию приложения и наблюдённым результатам, а не «вроде работает».

- [ ] До сборки Gate A/B пройдены хотя бы для одного реального сайта; остальные отмечены blocked/unknown. Если невозможно подтвердить протокол desktop-проверкой, разрешён только явно обозначенный диагностический эксперимент, не выпуск готовой функции.
- [ ] Выполнить существующие JS/Python проверки и GitHub native workflow на конкретном SHA; зелёный native run является входом signed workflow. Сохранить существующую цепочку `release/ci.sh gate`→prepare→archive. Код после проверки не менять перед подписью.
- [ ] После авторизации выполнения/тестовой доставки выпустить диагностический TestFlight build с extension. Зафиксировать, что это проверка настоящего APNs; симулятор push injection её не заменяет. Не обещать, что одной попытки обязательно хватит; каждый следующий запуск должен иметь установленную причину.
- [ ] Проверить ВК, затем Авито: foreground, background, экран заблокирован, приложение выгружено, перезагрузка до/после первого unlock, Wi-Fi/mobile/offline→online, Focus, alerts off, revoked permission. Записывать границы iOS; не обещать гарантированные секунды доставки.
- [ ] Основной сценарий: ATMA закрыта; отправить 2 ВК + 4 Авито; generic banners без текстов, иконка ATMA 6, после открытия ярлыки 2/4; затем прочитать ВК на другом устройстве — после доставки сверки сумма 4. Если Авито заблокирован, сценарий 2+4 не объявлять пройденным и полный исходный запрос не закрывать.
- [ ] Проверить несообщения, повтор/reorder/gap, два ярлыка одного аккаунта, account switch, logout, offline disable, PIN и удаление ярлыка. Считать отдельно «получение alert», «фильтрацию» и «точную сумму».
- [ ] Gate C: только подтверждённым providers присвоить verified. При недоступном authoritative unread/read sync или необходимых Apple capabilities составить отчёт блокера, согласовать изменение требований до сокращённого релиза. Не выпускать ещё одну сборку как готовые уведомления, если их нет.
- [ ] После прохождения Gate C подготовить релизные notes/screenshots/privacy и продолжить обычный согласованный выпуск отдельным шагом. Старую проверку Apple не отменять автоматически.

## Передача GPT Sol

Первое действие после команды владельца начать: прочитать spec, сверить git/AGENTS и выполнить задачу1. Не начинать с покупки сервера, APNs UI, настройки переключателя или подписанной сборки.

Отчёт по каждой контрольной точке: что доказано; что осталось неизвестным; что блокирует исходное требование; следующий конкретный тест. Если требуется участие владельца, просить ровно недостающее: войти в тестовый аккаунт, открыть разрешение iOS или проверить диагностический билд. Не запрашивать заново уже выданные разрешения на обычные обратимые правки.

Самопроверка плана: все требования spec распределены по задачам1–8; пять Review Focus имеют тесты; запись ciphertext не названа отсутствием обработки данных; возможность Web Push источника, фильтрация и счётчики — отдельные gates; подпись и физический тест отделены от компиляции. Это план, а не выполненные проверки продукта.

Рекомендуемая модель для реализации: GPT-6.1 Sol, уровень high. Причина: нужно согласовать криптографию, нативную доставку iOS, сервер и жизненный цикл аккаунтов без утечки данных.
