# ATMA для iOS — standalone browser

Подготовлены собственный UIKit/WKWebView браузер, общий интерфейс `BrowserUI`
и ручная сборка для iPhone/iPad. Приложение в этой конфигурации ещё не собрано
и не загружено в TestFlight. Проверки Windows не подтверждают поведение iOS;
время сборки не измерялось.

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

## Ручные workflows Codemagic

[Приложение Codemagic](https://codemagic.io/app/6a1af30432a4361359ee5663):

1. `atma-testflight` - **1. ATMA standalone - iPhone + iPad check (M2)**.
   Сначала static checks и XcodeGen, затем XCTest и реальный UI smoke на
   доступных iPhone и iPad Simulator: домашний экран, настройки, пустая вкладка,
   загрузка HTTPS-сайта и возврат домой после перезапуска. Компиляция независимых
   content-blocker правил проверяется WebKit через XCTest. После успешного
   завершения появляются xcresult, screenshots и `verified-commit.txt`.
2. `atma-device-testflight` - **2. ATMA standalone - verified TestFlight (M2)**.
   Ввести exact SHA из успешного `verified-commit.txt` для той же ревизии.
   Первый шаг требует `verified_commit == HEAD`, затем повторяет static checks,
   создаёт Xcode project, подписывает, архивирует и экспортирует `ATMA.app`.
   До выдачи IPA в publishing проверяются подпись, entitlements, identity,
   ресурсы и обе системные карты alternate icons. Непроверенный экспорт лежит
   вне artifacts; в `out/ipa` попадает только прошедший проверки файл.

Оба задания только ручные, на `mac_mini_m2`, Xcode `26.4`, лимит 30 минут.
Идентификаторы workflows сохранены; automatic push/PR/tag triggers отсутствуют.
XcodeGen устанавливается при необходимости только на CI. DerivedData cache
дополняет сборку из исходников и не заменяет обязательные проверки.

Для подписи используются существующие integration `ATMA`, группа
`atma_browser_signing` и `CERT_KEY_B64`. Секреты не требуется открывать или
переносить в репозиторий. Запуск TestFlight workflow отдельно разрешает
предусмотренную в нём отправку; ни один workflow в этой сессии не запускался.

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
