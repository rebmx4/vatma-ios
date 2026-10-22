# ATMA native iOS browser

Ручной запуск в [Codemagic](https://codemagic.io/app/6a1af30432a4361359ee5663):

1. Нажмите **Start new build**, выберите ветку **main** и задание
   **1. ATMA browser — iPhone check (M4)**. Оно собирает браузер и проверяет
   открытие сайта, восстановление страницы и настройки на симуляторе iPhone.
   После успешной проверки скриншоты и `verified-commit.txt` появятся в Artifacts.
2. Для загрузки в TestFlight отдельно запустите
   **2. ATMA browser — TestFlight (after iPhone check, M4)** на той же ветке
   и той же версии кода. В поле `verified_commit` вставьте содержимое
   `verified-commit.txt` из успешной проверки. Несовпадение остановит задание
   до подготовки исходников, компиляции и публикации.

Оба задания запускаются вручную; автоматические запуски при отправке кода
отключены. Используется Mac mini M4 с пределом 120 минут на каждое задание.
Первичная сборка большого нативного браузера занимает значительное время;
подготовленная конфигурация сама по себе не подтверждает успешную компиляцию
или загрузку в TestFlight. Для просмотра текущих логов и симулятора при запуске
можно включить Remote access.

This branch prepares the native browser for the existing Apple app `ru.atma.app`
(App Store Connect ID `6774934498`). The product name is **ATMA**. Its icon is the
owner's `atma.png`, copied into `assets/` and pinned by SHA-256.

`release/config.json` pins the native upstream source revision. Codemagic fetches
that source and its locked dependencies; `release/prepare.py` applies display
text, logos, icons, the ATMA user agent and Apple identity. Internal API/module
names, license notices and third-party URLs retain their original meanings.

The first browser build contains the main application. It does not claim the
upstream vendor's app groups, VPN extensions or default-browser entitlement.
Those capabilities require separate registration and verification for ATMA.
The legacy web-app sources in `ATMA/` are not built by this workflow.

The `atma-testflight` workflow runs a simulator scenario that opens an HTTPS
website and Settings and checks for old branding. After this passes, run
`atma-device-testflight` with `ATMA_VERIFIED_COMMIT` set to the tested repository
commit. That workflow rejects a different revision before building, then signs,
validates and uploads the app. These are separate jobs to stay within the build
service's 120-minute limit. Automatic push triggers are omitted.

Node has a 4 GB heap limit; heavy resource actions run one at a time. Native
compilation uses 8 jobs on a 12 GB worker and 6 on a smaller worker. Remote access
should be enabled when starting a diagnostic build so logs and simulator images
can be inspected during the run.

Local verification: `python -m unittest discover -s tests -v`, followed by
`python release/validate.py --source <prepared-native-source>`.
Compilation, simulator behavior and App Store delivery require the macOS CI.
