# ATMA: переход сборок на GitHub Actions

## Настроено

- Основной код и CI подготовлены в atma-browser-testflight, commit
  900b142ca7552d25ba4e26da5817e7a36e23f3da.
- На default branch main зарегистрированы только два workflow-файла:
  cd16f4f0c855f7645d61cf7cae0e7014e95bdf09, parent
  ed03c4eb48584b6106efb425646ac116aa151fe9. GitHub compare подтвердил ровно два
  добавленных файла; остальные источники main не изменены. Обновление без force.
- [ATMA 1: iPhone + iPad](https://github.com/rebmx4/vatma-ios/actions/workflows/atma-ios-check.yml)
  и [ATMA 2: signed IPA / upload](https://github.com/rebmx4/vatma-ios/actions/workflows/atma-testflight.yml)
  имеют state active. Chrome открыт на первом workflow с ручным меню запуска.
- Ручные задания используют standard macos-26, Xcode 26.4.1 и Python 3.12;
  30-минутный лимит. Existing prepare/smoke/gate/archive остаются в release/ci.sh.
- Репозиторий уже был публичным. Его visibility не менялась. Выполнение на standard
  GitHub-hosted runners бесплатно по правилам GitHub; artifact storage имеет
  отдельную квоту. Срок хранения результатов установлен в один день.
- Automatic push/PR/schedule/workflow_run triggers отсутствуют. DerivedData не
  сохраняется в отдельном GitHub cache. Артефакты повторной попытки заменяются
  только внутри того же run_id.

## Подпись и допуск к загрузке

- Существующий API-ключ АТМА и Issuer ID проверены настоящим authenticated GET
  приложения 6774934498: bundleId ru.atma.app. Новые ключи Apple не создавались.
- Локальная private key distribution-сертификата публичной частью совпала с
  действующим сертификатом DISTRIBUTION, срок до 2027-08-02. Сертификаты не менялись.
- Четыре encrypted repository secrets созданы через GitHub sealed-box API и
  подтверждены списком имён: APP_STORE_CONNECT_ISSUER_ID,
  APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY, CERT_KEY_B64.
  Plaintext значений не сохранялся в исходники, новые файлы или отчёт.
- Перед подписью проверяются repository/run ID/manual event/native workflow,
  completed + success и точное совпадение artifact verified-commit.txt с HEAD.
  SHA регистрации workflow на main не подменяет SHA исходников приложения.
- Upload по умолчанию выключен и требует отдельного явного input. Отправка
  на внешнее TestFlight beta review и App Store review автоматически не выполняется.
- Open-source codemagic-cli-tools 0.70.0 используются как Apple signing/upload CLI
  на машинах GitHub. Сервису Codemagic задания не отправляются.

## Проверено

- До изменения прошли 13 существующих Python checks.
- После реализации и исправлений прошли 20 Python checks: обе ветки отказа smoke,
  конфигурационные ограничения и provenance отрицательных/положительных случаев.
- Отдельно воспроизведён отказ при документированном workflow path@ref и проверено
  исправление с сохранением точного сравнения пути самого workflow.
- actionlint 1.7.12 прошёл для обоих workflow; shellcheck/pyflakes отключены.
- Source validator прошёл: 263 файла продукта, syntax/config/resource checks.
  Отчёт: out/github-migration-source-validation.json. git diff --check прошёл.
- Независимое финальное ревью: Critical 0, Important 0. Проверено соответствие
  используемых env и universal DISTRIBUTION pinned CLI 0.70.0.
- GitHub API и видимая страница подтвердили наличие обоих workflows и 0 запусков.

## Осталось

Новый облачный прогон не запускался. Windows-проверки и чтение кода не подтверждают
прохождение UIKit/XCTest. Полный сценарий iPhone/iPad, первая подписанная сборка на
GitHub и фактическая загрузка нового приложения в TestFlight ещё впереди.
Каждый запуск и публикация требуют отдельной прямой команды владельца.

Последний прежний Mac-прогон и исправление ожидания HTTPS описаны в
[native-https-smoke-2026-10-24.md](native-https-smoke-2026-10-24.md).
