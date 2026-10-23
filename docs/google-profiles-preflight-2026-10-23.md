# ATMA: подготовка входов и профилей перед Apple-сборкой

Объём, разрешённый владельцем: первые два шага — доработки, локальные проверки
и фиксация версии. Codemagic, Apple-сборка, подпись, TestFlight и push не входят
в этот запуск. Рабочая копия: `D:/Projects/atma-browser-ios`, существующий linked
worktree `atma-browser-testflight`; исходный HEAD `ed03c4e`.

## Изменения

- Обработчик новых окон возвращает WKWebView из конфигурации, переданной WebKit,
  вместо отдельной загрузки запроса с возвратом nil. Это сохраняет механизм
  `window.opener` и позволяет самому WebKit исполнить первоначальный запрос,
  включая метод/тело POST, без второй загрузки со стороны приложения.
- Окно получает профиль исходного renderer, даже если активна другая вкладка.
  Persistent websiteDataStore берётся из общей модели профилей. Script handlers
  и списки скриптов у окна отдельные; привилегированный UI bridge не передаётся.
- Разрешён безопасный начальный `about:blank`; другие новые окна принимают
  только HTTP(S) без встроенных учётных данных. `window.close()` возвращает
  к исходной вкладке, если она ещё существует.
- Проверка перехода нового окна не меняет blocker/download state исходной
  страницы по чужому hostname. Эти изменения применяются только к renderer,
  чей собственный main frame действительно переходит на другой адрес.
- Внутренний `about:blank` корректно восстанавливает renderer и допускает смену
  профиля. Публичная адресная строка по-прежнему принимает только HTTP(S)/поиск.
- Выбранный профиль согласует User-Agent с мобильным/настольным content mode.
  Реальный профиль использует системные UA и recommended mode. Размеры ATMA,
  язык/timezone JavaScript и движок WebKit не подменяются. Пояснение RU/EN
  в выборе профиля обновлено; полный fingerprint spoofing не заявляется.
- Google остаётся поисковиком первого запуска. Существующие настройки владельца
  и данные сайтов не сбрасывались. BrowserModel принимает UserDefaults, чтобы
  нативные проверки использовали отдельную тестовую suite.
- Git сохраняет закреплённые сертификаты как двоичные данные: автоконвертация
  CRLF не должна менять PEM SHA256. Содержимое сертификатов не изменялось.
  В трёх прежних review-отчётах удалены только лишние пустые строки в конце.

## Локальные проверки

Исходное состояние: 10/10 Python и 14/14 JavaScript adapter tests прошли до правок.
После правок прошли:

- `python -B -m unittest discover -s tests -v`: 10/10.
- Все 11 `*.test.mjs` в `atma-mobile-preview`: 48/48.
- `node --test tests/site-media.test.mjs tests/site-video-controls.test.mjs tests/youtube-protection.test.mjs`: 14/14.
- `python -B release/validate.py --report out/google-profiles-source-validation.json`:
  263 product files, конфигурация, ресурсы и JS-синтаксис прошли.
- `git diff --check`: без ошибок.

Логи: `out/google-profiles-{python,preview-node,adapters}.log`. Все новые файлы,
temp/cache, индекс графа и результаты находятся на D:. Новых инструментов нет.

Подготовлены шесть XCTest в `BrowserNativeTests/BrowserWindowTests.swift`:
профиль фонового opener и возврат к нему; запрещённые окна; UA/content mode;
устойчивые идентификаторы хранилищ/Google default; смена профиля и пересоздание
пустого renderer; настоящий локальный
`window.open` с обратным `postMessage`. Эти XCTest **не запускались**: на Windows
нет UIKit/WebKit/Xcode. Red/green нативного сценария здесь не подтверждён.

## Что остаётся проверить

Swift compile, XCTest и Apple runtime относятся к следующему этапу. После них
нужен вход в YouTube и сайт через Google на iPhone, повторный запуск приложения,
проверка сохранения сессии и изоляции профилей, закрытие окна и POST-переход.
Cookie и сроки входа контролирует также сам сайт. Google может отклонить
встроенный браузер; исправление механизма окон не обходит его OAuth policy.

Источники: [контракт новых окон WebKit](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:)),
[Google OAuth policies](https://developers.google.com/identity/protocols/oauth2/policies).
Независимый статический обзор перед коммитом завершён: открытых Critical,
Important и Minor замечаний в согласованном объёме нет. Замечания о влиянии
popup на blocker исходной страницы и смене профиля пустого окна исправлены
и перечитаны. Это review исходников, не подтверждение Apple runtime.
