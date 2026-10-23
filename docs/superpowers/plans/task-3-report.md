# Task 3 — standalone build pipeline and native appearance

Status: DONE_WITH_CONCERNS. Локальная замена активной сборочной конфигурации выполнена. Xcode generation/build, XCTest, UI Simulator/device, signing, Codemagic и TestFlight в этой сессии НЕ запускались.

## Архив до замены

До переноса старых путей создан `D:\Backups\atma-ios-before-standalone-20261023\legacy-project.zip`: 42 файла из ATMA/, release/, tests/, project.yml, codemagic.yaml и README.md. Размер 1112205 байт; SHA256 `ba1d027b0d8f6ce48685d84554629b86a1562b56655c606c8e1faad516055afc`. Внешний `manifest.json` содержит размер и SHA256 каждого файла; ZIP CRC и все 42 digest проверены после создания и повторно после изменений.

Команда удаления старых каталогов была отклонена автоматической проверкой с общим сообщением blocked by policy и не исполнилась. Выбран согласованный более безопасный вариант: ATMA/, release/ и tests/ перенесены целиком в `legacy-tree` рядом с ZIP, за пределы активного проекта. После переноса повторно сверены все 39 файлов этих каталогов с manifest. Первые project/CI/README остаются в ZIP; новых destructive действий не потребовалось.

assets/certificates/manifest.json и PEM сохранены на прежнем месте. .native, .git, исходный vatma-ios, D:\browser и приложение Responsively не изменялись. Новые Windows файлы, результаты и явно настроенные temp/cache находятся на D:. Новых локальных установок нет.

## Активный проект и ресурсы

- project.yml теперь описывает только ATMA/UIKit/WebKit, ru.atma.app, team GR3WB4Z646, iOS 17+, device families 1,2. Отдельные targets BrowserNativeTests и BrowserNativeUITests включены в схему ATMA. Старый ATMA/ и SDK checkout не являются inputs.
- Источники приложения ограничены BrowserNative, BrowserUI, BrowserResources и assets/certificates. BrowserUI и certificates копируются folder references с точными именами. Ресурсная группа BrowserResources объединяет локализованные InfoPlist.strings и asset catalogue; source Info.plist и icon-manifest не копируются как обычные ресурсы.
- Новый Info.plist использует собственный @main AppDelegate без legacy Scene, WKAppBoundDomains, URL schemes, push/background/VPN/group entitlements. ATS разрешает loopback и произвольный web content HTTP; HTTPS trust delegate не ослаблен. Camera/microphone usage descriptions RU/EN не инициируют запрос сами: их использует реальный запрос сайта.
- PrivacyInfo.xcprivacy описывает локальные UserDefaults (CA92.1) и file timestamp metadata для списка загрузок (C617.1), без telemetry/tracking.
- Основная иконка построена из канонического BrowserUI/assets/atma.png. Из atma-icons-a1.png получены десять разрешённых crops по тем же координатам, что и appearance.js. Сохранены 11 sets × 18 PNG = 198 непрозрачных RGB файлов, включая каждый marketing 1024×1024, с белым compositing background. Основная marketing-иконка просмотрена визуально. Manifest фиксирует SHA256 обоих источников, точную карту UI→OS и digest всех PNG.
- OS alternate names AppIconA101...AppIconA110 заданы ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES и INCLUDE_ALL_APPICON_ASSETS для универсальных iPhone/iPad sets. Согласно Apple, CFBundleIcons/CFBundleAlternateIcons генерирует asset compiler; эти словари не редактируются вручную. IPA validation требует primary AppIcon и все десять альтернатив отдельно в CFBundleIcons и CFBundleIcons~ipad. Факт генерации этих plist entries остаётся macOS build check.

project.yml и codemagic.yaml используют JSON-синтаксис, допустимый YAML. XcodeGen явно поддерживает JSON/YAML; Python stdlib читает оба файла без новой зависимости. Native/CI validation проверяет закрытый список application inputs, без пакетов и скрытых build scripts. Описательное слово Chromium в preview-справке не считается зависимостью: проверяются реальные import/framework/package/checkout/endpoint patterns, запрещённые binary SDK formats и Apple-only native imports.

## Ручной CI

Сохранены IDs atma-testflight и atma-device-testflight; названия имеют ASCII '-' и новый standalone/M2 смысл. Оба workflow только manual, mac_mini_m2, Xcode 26.4, max 30 минут, без triggering. Официальная Codemagic image specification подтверждает M2 и iPhone/iPad simulators для этой версии; скорость сборки не измерялась.

release/ci.sh выполняет четыре явных stages:

1. gate требует непустой verified_commit, в точности равный git HEAD, до подготовки подписанного workflow.
2. prepare выполняет Python unit tests, static source/JSON/plist/certificate/icon checks и JS syntax, устанавливает XcodeGen только при необходимости на CI, генерирует ATMA.xcodeproj в корне проекта и проверяет plist/target list. Корневая генерация сохраняет корректный относительный INFOPLIST_FILE.
3. smoke выбирает доступные iPhone и iPad на одном самом новом установленном iOS runtime. На iPhone запускаются unit + UI targets; на iPad UI smoke. Проверяются реальный home, Settings, пустая вкладка без site renderer, HTTPS example.com и возврат домой после перезапуска. xcresult и screenshots сохраняются; verified-commit.txt появляется только после обоих успешных устройств.
4. archive повторно требует exact verified HEAD и static validation, использует существующие CERT_KEY_B64/integration ATMA/group atma_browser_signing, получает подпись, архивирует ATMA.app, проверяет codesign и entitlements, экспортирует IPA и проверяет структуру/identity/resources/icons. Экспорт дополнительно распаковывается для codesign и entitlements проверки уже экспортированного приложения. Только после этого IPA копируется в artifact/publishing out/ipa. Не прошедший проверки экспорт остаётся вне publishing artifacts. set -euo pipefail останавливает этап на обязательной ошибке; необязательный экспорт diagnostic screenshots не маскирует исходный test failure.

DerivedData caches находятся под CM_BUILD_DIR/.cache/derived-simulator и derived-device. Generated project, export и signing secret не являются cache/artifact paths. Ключ не печатается, сохраняется с mode 0600 и удаляется EXIT trap. Секреты не открывались в этой сессии.

## Разрешённое дополнение native appearance

В BrowserNative добавлен изолированный BrowserAppearance.swift; BrowserController получил только nativeTheme/preferredStatusBarStyle, BrowserRPC — два actions. Остальные native файлы в Task 3 не менялись.

- app-icon принимает только default/a1-01...a1-10, преобразует их в whitelist OS asset names, проверяет supportsAlternateIcons и возвращает {icon} только из системного completion без ошибки. Ошибки UIKit возвращаются RPC rejection; имитации успеха нет.
- appearance принимает auto/light/dark, меняет overrideUserInterfaceStyle и status bar contrast, фон safe-area/window/UI webview на #101010 или #f1f0ed; auto использует системные traits. Вторая persisted настройка темы не создаётся, истина остаётся в UI localStorage.
- BrowserAppearanceTests содержит три pure-unit проверки primary/default, полной карты альтернатив и отказа произвольных IDs. ContentBlockerTests использует Bundle.main/BrowserUI/content-blocker.json и реальный WKContentRuleListStore compile callback/expectation: неподдерживаемое WebKit правило должно провалить CI unit target, без сетевых запросов.

## Изменённые файлы

project.yml, codemagic.yaml, README.md; новый release/{ci.sh,validate.py,verify_ipa.py,verify_signing.py,simulators.py,icons.py}; новый tests/test_standalone.py; BrowserResources/{Info.plist,PrivacyInfo.xcprivacy,icon-manifest.json,ru.lproj,en.lproj,Assets.xcassets/**}; BrowserNativeUITests/BrowserSmokeTests.swift; BrowserNative/BrowserAppearance.swift и небольшие изменения BrowserController.swift/BrowserRPC.swift; BrowserNativeTests/BrowserAppearanceTests.swift и ContentBlockerTests.swift. Старые tracked ATMA/release/tests заменены после внешнего архива.

## Проверено локально

- `python -B -m unittest discover -s tests -v`: **9 tests passed**. Проверяются закрытый project boundary, отсутствие automatic CI и обязательный gate, реальная certificate integrity/tampering, все PNG dimensions/RGB/hashes, IPA fixtures identity/resources/vendor-framework rejection, signed-entitlement fixtures и simulator selection. Fixture Mach-O header/IPA не являются настоящей сборкой приложения.
- `python -B release/validate.py --report out/task-3-static-validation.json`: **passed**, статические application inputs/config/resources, iOS 17 и families 1,2. Число проверенных product files зависит от финальных parent UI файлов; последний результат хранится в JSON.
- Git Bash `--noprofile --norc -n release/ci.sh`: **passed**; executable уже установлен, shell не исполнял release stages.
- Scoped `git -c core.autocrlf=false diff --check`: **passed** после нормализации принадлежащих Task 3 text config/resources к LF; первая проверка выявила CRLF как trailing whitespace, исправлено без изменения поведения.
- Node `--check`: **10 shared UI JS/mjs modules passed**. BrowserUI не изменялся этим worker.
- ZIP/manifest: **42 archive hashes + 39 preserved-tree hashes passed** повторно.
- Все новые source files проверяются на <400 строк; Python modules проверяются ast.parse без записи bytecode. Для PNG/Pillow использована уже установленная программа; установка не запускалась.

## Не проверено и остаётся

Swift/Xcode/XcodeGen и Apple SDK на Windows отсутствуют; XCTest (включая новые 3+1 native cases), UI smoke, system alternate icon change, status bar rendering, generated CFBundleIcons dictionaries, codesign/signing profile/export, IPA реальной сборки и TestFlight не запускались. Публичные API/config signatures и локальная статика не заменяют эти действия. CI подготовлен к их проверке, но пока не доказано, что конфигурация компилируется и проходит runtime.

На macOS требуется выполнить схему/unit/UI smoke на iPhone/iPad; отдельно проверить device camera/mic prompts, TLS validity/hostname/root pins, website sign-in persistence, downloads/cookies, alternate icons и manual/system appearance. parent контролирует общую BrowserUI/RPC совместимость и scope review Task 3, включая новые native helper/actions и иконки. Никаких дополнительных функций сверх согласованного scope не добавлено.

## Первичные источники

[Codemagic Xcode 26.4 image/M2/simulators](https://docs.codemagic.io/specs-macos/xcode-26-4/), [manual workflow inputs](https://docs.codemagic.io/knowledge-codemagic/build-inputs/), [caching](https://docs.codemagic.io/knowledge-codemagic/caching/), [XcodeGen spec/JSON/folder references/test hosts](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md), [Apple alternate icons build settings and API](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons), [UIKit completion semantics](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:)), [ATS web-content exception](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent), [required-reason privacy APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
