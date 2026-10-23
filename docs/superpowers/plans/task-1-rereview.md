# Task 1 — повторный scoped review

Дата: 2026-10-23. Объём: только исправления I1/M1/M2 из task-1-review.md
и новые helpers/tests, описанные в task-1-fixes.md.

## Вердикт

- Spec verdict в проверенном объёме: I1, M1, M2 закрыты по исходникам.
- Quality verdict: APPROVE для этих исправлений; новых Critical/Important/Minor
  замечаний в проверенном объёме не найдено.
- Это не подтверждение компиляции или выполнения на iOS. Общая ревизия task 1
  повторно не проводилась; прежние ограничения платформенной проверки остаются.

## I1 — состояние navigation/download

Проверены BrowserNavigation.swift:13–40, :43–69, :101–120,
BrowserDownloadNavigation.swift:4–36, DownloadPolicy.swift:3–16,
BrowserController.swift:45–53, :139–157, :194–205,
BrowserModels.swift:14–17 и DownloadService.swift:88–123.

- Перед решением .download записывается ожидаемый переход именно исходного
  renderer/tab. В didBecome переход явно ставит loading=false/error=nil,
  сохраняет состояние и публикует его.
- Классификатор требует совпадение WKNavigation identity; когда identity ещё
  нет, требуется точный failing URL. Совпадения одного кода 102 недостаточно.
  Разрешены только NSURLErrorDomain/-999 или WebKitErrorDomain/102.
  Другой domain, другой navigation ID и настоящая сетевая ошибка не
  классифицируются как ожидаемое прерывание.
- После transferred=true поздний ожидаемый navigation interruption только
  возвращает управление: finishNavigationForDownload повторно не вызывается,
  поэтому ранее записанная настоящая ошибка WKDownload не очищается.
- WKDownload.didFail всегда передаёт ошибку исходной вкладке. Успешное
  завершение не обнуляет постороннюю ошибку вкладки.
- Обычная текущая навигационная ошибка проходит в update с loading=false.
  Игнорирование ошибки superseded navigation связано со сравнением объектов
  WKNavigation, а не с глобальной фильтрацией сетевых ошибок.
- Новый main-frame navigation, закрытие вкладки и смена renderer очищают
  устаревшее tracking состояние.

В просмотренных путях suppression не скрывает настоящие ошибки текущей
навигации или WKDownload. Порядок callbacks на iOS этим чтением не проверен.

## M1 — top-level hostname

Проверены BrowserNavigation.swift:36–38, :72–89 и
SiteSecurity.swift:56, :72–84; predicate — DownloadPolicy.swift:54–58.

Main-frame response применяет правило по response.url.host; redirect,
commit и finish дополнительно применяют его по фактическому webView.url.host.
Subframe response top-level policy не меняет. State и apply используют один
HostBlockerPolicy.enabled; сохранённые exclusions приводятся к нижнему регистру.
Исключение A не переносится на B или поддомен A по самому predicate.
Реальные HTTP redirects и момент применения правил WebKit не выполнялись.

## M2 — Unicode filename

Проверены DownloadPolicy.swift:19–51 и DownloadService.swift:94–105.

Итоговый компонент ограничен 240 UTF-8 байтами: extension максимум 32 байта,
dot учитывается отдельно, для dash+UUID зарезервировано 37 байт.
Обычный и collision path используют один make; суффикс дополнительно ограничен
ASCII и 36 символами. Truncation сохраняет целые Swift Characters.
Fallback имеет короткое безопасное имя. Подкаталоги, backslash и управляющие
символы не попадают в итоговый компонент. Ограничение подтверждено анализом
бюджетов в коде; файловые операции iOS не запускались.

## Тесты и фактически выполненная проверка

Прочитаны все шесть новых XCTest cases в BrowserDownloadTests.swift.
Они проверяют terminal state и сохранение metadata, положительную/отрицательные
ветви interruption classifier, точный URL до navigation start, UTF-8 budget,
санитизацию имени и exact-host predicate. Полного lifecycle/WebKit callback
сценария эти unit cases не исполняют.

Graph-first попытка search_graph в atma-ios-release вернула 0 результатов;
после этого использованы только известные файлы из fixes report.
NativeHelpers.swift отсутствует: фактические новые helpers называются
BrowserDownloadNavigation.swift и DownloadPolicy.swift.

Выполнены только чтение report/source/test assertions и запись/read-back
этого отчёта. Код, конфигурация и тесты reviewer не менял.
Swift/Xcode, XCTest, сборки, установки, CI, commit/push не запускались.
Структурные checks и diff --check из fixes report повторно не запускались.

Остаётся заявленная проверка на macOS/iOS: compile/XCTest, оба варианта
download conversion и порядка callbacks, реальная download failure,
новая навигация во время скачивания, redirects A↔B и Unicode filename collisions.
