# Task 3 — scoped integration/spec + quality review

Дата: 2026-10-23. Объём: Task 3 report, standalone project/release resources,
новые native appearance/icon actions/tests и их точная связка с BrowserUI.
Общие native/UI ревизии Task 1/2 повторно не проводились.

## Вердикт

- Spec verdict: соответствует проверенному объёму Task 3.
- Quality verdict: APPROVE; подтверждённых Critical, Important или Minor дефектов
  в просмотренном объёме не найдено.
- Это approval исходников и конфигурации, а не успешной iOS сборки или публикации.

## XcodeGen, application boundary и bundle

Проверены project.yml:23–122, release/ci.sh:37–49, release/validate.py и
BrowserResources/Info.plist.

- Текущая команда xcodegen generate --spec project.yml выполняется в корне
  CM_BUILD_DIR; output .cache/generated больше не используется.
  INFOPLIST_FILE=BrowserResources/Info.plist согласован с этим расположением.
- ATMA sources ограничены BrowserNative, BrowserUI, assets/certificates,
  BrowserResources. BrowserUI и certificates заданы folder references в resources,
  сохраняя нужные runtime имена; metadata Info.plist/icon-manifest исключены
  из обычного resource копирования.
- Target использует отдельный standalone AppDelegate из BrowserNative.
  Info.plist не вводит legacy Scene lifecycle, второй entry point или
  WKAppBoundDomains. Разрешения ATS совпадают с HTTP web content/loopback scope.
- iOS 17+, families 1,2, application identity/team заданы согласованно.
  В активных dependencies нет Brave/Chromium/package/checkout fallback.
- Unit/UI targets зависят от ATMA и включены в схему. XcodeGen документирует
  автоматическую установку TEST_HOST для application-hosted unit tests и
  TEST_TARGET_NAME для UI tests; отсутствие вручную заданного TEST_HOST
  само по себе не является дефектом.
- RU/EN InfoPlist.strings и privacy manifest прочитаны. Они описывают camera/mic
  purpose и локальные defaults/file timestamp usage без tracking declarations.

JSON spec, folder references и test-host behavior сверены с
[XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md).
Реальный .pbxproj/compiled bundle на Windows не генерировался.

## Native appearance/icons ↔ BrowserUI

Проверены BrowserAppearance.swift, новые case в BrowserRPC.swift:21–22,
nativeTheme/preferredStatusBarStyle в BrowserController, app.js:9, :78–98 и
runtime-specific home-indicator selector appearance.css.

- UI отправляет theme auto/light/dark; native принимает тот же whitelist,
  применяет overrideUserInterfaceStyle и status bar style. Dynamic UIKit
  backgrounds используют те же dark #101010/light #f1f0ed базовые цвета.
  Истина настроек остаётся в UI localStorage, второго native persisted theme нет.
- app-icon IDs default/a1-01…a1-10 совпадают между UI, native policy,
  icon-manifest и ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES.
- Native проверяет supportsAlternateIcons, default преобразуется в nil,
  остальные IDs — только в whitelist asset names. RPC reply выполняется
  после UIKit completion; системная ошибка возвращается как rejection.
  UI сохраняет успешный icon choice после ответа native.
- body[data-runtime=ios] определяется по native handler; synthetic home pill
  скрывается только для iOS. Preview сохраняет свой indicator.
- Asset compiler настройки используются для generated CFBundleIcons вместо
  ручного дублирования этих словарей; verify_ipa требует primary и все 10
  alternates отдельно для iPhone/iPad.

Build settings и nil/completion semantics сопоставлены с
[Apple alternate icons documentation](https://developer.apple.com/documentation/Xcode/configuring-your-app-to-use-alternate-app-icons).
Это не проверка supportsAlternateIcons или смены иконки на устройстве.

## Иконки и tests

Прочитаны icons.py, metadata manifest, один полный alternate Contents.json,
BrowserAppearanceTests.swift, ContentBlockerTests.swift и BrowserSmokeTests.swift.
Выборочно визуально просмотрены primary и AppIconA101 marketing PNG.

- Crop coordinates/generation и карта UI→OS согласованы с appearance.js.
  Проверка 198 PNG dimensions/RGB/hashes присутствует в validate.py; повторно
  её не запускал. Просмотренные изображения декодируются и соответствуют
  основной/первой альтернативной иконке.
- Appearance tests проверяют primary nil, 10 mappings и rejection посторонних IDs.
- ContentBlockerTests реально вызывает WKContentRuleListStore compile callback,
  проверяет list/error и timeout; это не статическая фиктивная компиляция.
- UI smoke проверяет home/settings, blank tab без site renderer, HTTPS
  example.com и relaunch домой. Ошибка assertion не игнорируется.
- Unit/UI runtime выполнение на Windows отсутствует; внешняя сеть example.com
  остаётся зависимостью будущего smoke, и её недоступность приведёт к failure.

## Manual CI, signing и publishing boundary

Проверены codemagic.yaml, полный ci.sh и
release/{verify_ipa.py,verify_signing.py,simulators.py,validate.py}.

- Оба workflow manual, M2, Xcode 26.4; automatic triggering отсутствует.
- Signing workflow начинает с gate: непустой input должен в точности совпасть
  с git HEAD. Archive повторяет эту проверку до чтения signing key.
  Это заданный manual flow: оператор переносит SHA из успешного smoke artifact;
  gate не запрашивает удалённый CI verdict через API.
- prepare делает обязательные Python/static/JS checks и generation.
  smoke запускает unit+UI на iPhone и UI на iPad одного доступного iOS runtime;
  verified-commit.txt записывается после успешного завершения обоих.
- set -euo pipefail сохраняет ошибку xcodebuild через tee.
  Необязательный screenshot export не подавляет основной test failure.
- archive повторяет static validation, затем получает signing files и выполняет
  archive. Проверяются archive codesign/entitlements, export, IPA identity/resources,
  exported codesign/entitlements. Только затем cp создаёт out/ipa/ATMA.ipa.
- Publishing artifact pattern ограничен out/ipa/*.ipa; промежуточный export
  находится вне publishing artifacts. У mandatory validation failure нет
  успешного пути к этому cp.
- Signing key сохраняется с 0600 и удаляется EXIT trap; в командах нет echo
  значения key. Reviewer секреты не открывал.
- Caches ограничены derived data, secrets/export не включены в cache artifacts.

Workflow inputs проверены по
[Codemagic build inputs](https://docs.codemagic.io/knowledge-codemagic/build-inputs/).
Отсутствие default у verified_commit действительно требует явный ввод.
Пути artifacts соответствуют
[Codemagic configuration](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/).

## Фактически выполнено и осталось

### Узкое дополнение: порядок state responses

После основного review просмотрены stateActionVersion guard в app.js:61,
:180–183, :882–884 и verify-state-order.mjs. Каждый action увеличивает version;
action response, initial state и poll response вызывают consume только при
совпадении сохранённого номера с текущим. Ответ state, начатый до нового
Settings action, поэтому не может закрыть его panel после завершения запроса.
Native handler/API и native event delivery этим guard не изменены.

Regression script задерживает настоящий старый /api/state response, открывает
Settings и выпускает ответ, затем проверяет, что Settings остаётся открытым.
Он восстанавливает fetch и исходный panel в finally. Использованы сообщённые
parent результаты: до исправления red на iPhone, после — green phone+iPad;
cookie/appearance checks повторно прошли у parent. Reviewer этот сценарий
не запускал. Нового подтверждённого замечания в этих строках не найдено;
APPROVE остаётся в силе для данного добавления.

Выполнены только scoped чтение исходников/config/tests/reports, сопоставление
публичной документации, просмотр двух существующих PNG и запись/read-back
этого отчёта на D:. Graph-first lookup atma-ios-release нашёл только старый
ATMA/AppDelegate; использованы известные текущие файлы из task report.

Прочитан out/task-3-static-validation.json: status=passed, 253 product files.
Результаты 9 Python tests, bash/10 JS syntax checks и архивных 42/39 hashes
использованы из task-3-report.md; повторно не запускались.
Исходники/config не менялись. Установки, XcodeGen/build/tests/CI/signing,
сервисы/UI restarts, commit/push и публикации reviewer не запускал.

Остаются macOS generation/compile/XCTest и iPhone/iPad UI smoke, generated
CFBundleIcons dictionaries, системные theme/status bar/icons, content rule
compilation, реальная подпись/entitlements/exported IPA и TestFlight.
Ни один из этих runtime результатов статическим APPROVE не заявляется.
