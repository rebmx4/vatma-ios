# ATMA для iOS — standalone browser

Подготовлены собственный UIKit/WKWebView браузер, общий интерфейс `BrowserUI`
и ручная сборка для iPhone/iPad. Приложение компилировалось на Mac и прошло 24
unit tests; полный UI-сценарий iPhone/iPad ещё не завершён. Новый standalone build
не загружен в TestFlight. Локальные проверки Windows не подтверждают поведение iOS.

Приложение: **ATMA**, bundle ID `ru.atma.app`, Apple team `GR3WB4Z646`,
App Store Connect ID `6774934498`, минимум iOS 17. Исходники приложения:
`BrowserNative`, ресурсы: `BrowserUI` и `BrowserResources`. Папка
`assets/certificates` сохраняется на месте для preview и попадает в bundle
под именем `certificates`. Подключённых пакетов, стороннего browser SDK,
расширений VPN/push и старой веб-обёртки нет.

`BrowserUI` — единый источник интерфейса для нативного приложения и Windows
preview. UIKit размещает отдельный site WKWebView над панелью ATMA. Сайты
не получают privileged RPC собственного UI. Входы и cookies хранятся в
постоянных отдельных WebKit data stores профилей; срок входа зависит также
от сайта, его cookies и правил авторизации. Обход ограничений embedded OAuth
не реализован. Синхронизация с ПК, произвольные фоновые push, полный перевод
и полная подмена fingerprint пока отсутствуют. Язык и timezone JavaScript
остаются системными; выбранный профиль меняет User-Agent и мобильный/настольный
режим сайта, сохраняя реальный движок и размеры экрана.

Окна сайтов создаются из конфигурации, переданной WebKit: сохраняются связь
с исходной вкладкой, её профиль и хранилище сессии, а исходный запрос загружает
сам WebKit. Закрытие окна возвращает к исходной вкладке. Это исправление
подготовлено для входов через Google/YouTube, но успешная авторизация провайдера
на iPhone ещё не проверена. [Локальные проверки и ограничения](docs/google-profiles-preflight-2026-10-23.md).

Основная OS-иконка генерируется из `BrowserUI/assets/atma.png`. Десять
альтернатив берутся из `atma-icons-a1.png` по тем же координатам, что и UI.
Непрозрачные RGB PNG для iPhone/iPad и 1024px marketing сохранены в
`BrowserResources/Assets.xcassets`. Карта `a1-01` ... `a1-10` соответствует
`AppIconA101` ... `AppIconA110`; реальные изменения выполняет UIKit с
обработкой системной ошибки. UI также синхронизирует светлую/тёмную/системную
тему с native status bar, сохраняя единственную настройку в UI localStorage.

Проверка HTTPS сначала использует обычное доверие Apple. Лишь после отказа
добавляется закреплённый RSA-корень из bundle с проверкой PEM/DER SHA256,
с сохранением hostname/SSL policy, срока и системных anchors. Сертификат
обновляется пересборкой подписанного приложения. Insecure TLS bypass отсутствует.
ATS разрешает произвольный HTTP только web content и loopback UI: это браузер,
а не список заранее ограниченных доменов. Для App Store потребуется объяснить
эту web-content exception. Камера/микрофон запрашиваются системой только при
соответствующем запросе открытого сайта, с описаниями RU/EN.

## Локальные проверки на Windows

Собственные плеер и YouTube-адаптер: [реализация и проверенный объём](docs/media-player-verification-2026-10-23.md).
Нативные PiP/фоновый звук подготовлены; реальная проверка iPhone пока не выполнена.

Все записи, TMP/cache и результаты размещать на D:. Новые инструменты не нужны:
валидатор и тесты используют Python stdlib. JSON-синтаксис `project.yml` и
`codemagic.yaml` совместим с YAML; это позволяет разбирать оба конфига без
установки YAML-библиотеки.

```powershell
$env:TEMP='D:\tmp'
$env:TMP='D:\tmp'
$env:PYTHONDONTWRITEBYTECODE='1'
$env:PYTHONPYCACHEPREFIX='D:\caches\python'
python -B -m unittest discover -s tests -v
python -B release/validate.py --report out/source-validation.json
```

Проверяются active inputs, идентификаторы/устройства, ручные CI workflows,
реальные certificate pins, generated icons, JSON/plist/Python syntax и
пакетные проверки на тестовых IPA fixtures. Это не компиляция Swift и не UI test.
Для сознательной пересборки изображений при уже установленном Pillow:
`python -B release/icons.py`. Установка Pillow локальным workflow не выполняется.

## Ручные workflows GitHub Actions

Основная площадка сборки — [GitHub Actions](https://github.com/rebmx4/vatma-ios/actions).
Репозиторий уже публичный. Выполнение на стандартном macos-26 runner бесплатно по
[правилам GitHub](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
Хранение artifacts имеет отдельную квоту; результаты сохраняются только на один день.
Платные larger runners и автоматические push/PR/schedule triggers не используются.

1. [ATMA 1 - iPhone + iPad check](https://github.com/rebmx4/vatma-ios/actions/workflows/atma-ios-check.yml).
   Нажать Run workflow после отдельной команды владельца на один запуск.
   Поле revision по умолчанию — atma-browser-testflight; можно указать exact SHA.
   Workflow вызывает общий release/ci.sh prepare/smoke: статические проверки,
   XCTest на iPhone и UI smoke на iPad, включая клавиатуру, поворот, HTTPS и перезапуск.
   В artifact atma-native-<run_id> сохраняются логи, xcresult, screenshots и, только
   после успеха обоих устройств, verified-commit.txt с SHA исходников.
2. [ATMA 2 - signed IPA and TestFlight upload](https://github.com/rebmx4/vatma-ios/actions/workflows/atma-testflight.yml).
   Отдельный ручной запуск. Указать exact source SHA из verified-commit.txt и ID
   успешного первого запуска. Проверяются его repository, workflow, event, status,
   conclusion и совпадение SHA. SHA workflow на main может отличаться от SHA приложения.
   Истёкший или неуспешный artifact не допускает подписанную сборку.
   Поле upload_to_testflight по умолчанию выключено: после явного разрешения на
   загрузку оно включает отправку проверенного IPA в App Store Connect. Отправка
   на внешнее TestFlight beta review и App Store review автоматически не выполняется.

Оба job ограничены 30 минутами, используют Xcode 26.4.1 через установленный alias
Xcode_26.4.app и Python 3.12. GitHub публикует состав
[образа macos-26](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
Actions закреплены по полным SHA. DerivedData собирается в рабочем каталоге; отдельного
платного cache нет. CM_BUILD_DIR используется как совместимый alias GITHUB_WORKSPACE
для существующего общего скрипта, а не как обращение к сервису Codemagic.

Для второго workflow нужны encrypted repository secrets:
APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_IDENTIFIER,
APP_STORE_CONNECT_PRIVATE_KEY, CERT_KEY_B64. Ключи нельзя коммитить в исходники.
Open-source codemagic-cli-tools 0.70.0 устанавливаются в venv рабочего каталога
только для подписи и общения с Apple; вычислительные мощности предоставляет GitHub.

На main регистрируются только файлы workflows, чтобы GitHub показывал Run workflow.
Приложение берётся из явно указанной revision. Старые источники main не смешиваются
с standalone browser. codemagic.yaml сохранён как неавтоматический резерв; его запуск
тоже требует отдельного разрешения и расходует платные минуты после квоты.

Новый GitHub workflow ещё не подтверждён облачным выполнением. Предыдущий Mac-прогон
скомпилировал приложение и прошёл 24 unit tests; UI остановился на устаревшем ожидании
содержимого страницы. Подготовленная правка: docs/native-https-smoke-2026-10-24.md.
Полное прохождение iPhone/iPad и доставка нового build в TestFlight пока не заявляются.

## Архив и границы проверки

Старые `ATMA/`, `release/`, `tests/` и прежние project/CI/README сначала
сохранены и проверены по SHA256 в
`D:\Backups\atma-ios-before-standalone-20261023\legacy-project.zip`.
Исходные каталоги дополнительно перенесены в `legacy-tree` рядом с архивом,
вне активного проекта. `.native`, `.git`, исходный `vatma-ios` и `D:\browser`
не изменялись; они не являются inputs нового Xcode project или workflow.

Нужны macOS compile/XCTest, iPhone/iPad UI smoke и отдельная проверка устройства:
TLS, persistent sign-in, cookies, загрузки, OS icons и status bar. Сборка,
отправка и статус TestFlight не подтверждены локальными static checks.
Подробности: `docs/superpowers/plans/task-3-report.md` и отчёты Task 1/2.
