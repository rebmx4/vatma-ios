# ATMA — проверка 23 октября 2026

Локально подготовлена независимая iOS-основа UIKit/WebKit без старого browser SDK.
Общий BrowserUI используется и в Windows preview. Активные product inputs не
включают Brave/Chromium, Wallet, Rewards, AI, News, VPN, Playlist или их сервисы.
Старый build path сохранён вне проекта в проверенном архиве на D:.

Сделаны Files/Cookie с просмотром и выборочным удалением, RU/EN интерфейс,
палитры APiKS, автоматическая тема, OS-иконки из a1, native appearance bridge и
базовая собственная блокировка из 27 доменных правил с исключением для сайта.
Для Windows сохраняется честное обозначение отдельного Chromium preview runtime.

Проверено на Windows:
- 9 Python unit tests нового standalone pipeline.
- 23 отдельных JavaScript unit tests appearance/workspace/cookies/localization/
  cookie authority/domain boundaries (несколько целевых запусков).
- Итоговый static validator: 253 product files, конфиги и ресурсы прошли;
  `out/final-standalone-validation.json`, `git diff --check` без ошибок.
- Реальные preview сценарии iPhone428×926 и iPad768×1024: RU/EN, обе палитры,
  cookie list RPC и изолированные fixture удаления, навигация, новые вкладки,
  три колонки, thumb controls, защита от запоздавшего state response.
- Существующие вкладки, renderers, настройки и PIN-запись сохранены; пользовательские
  cookies не удалялись. Данные cookie не экспортировались и не попадали в отчёты.
- Spec/quality review Task1, Task2, Task3: APPROVE в статически проверенном объёме.

Осталось проверить на Apple: XcodeGen, Swift build/XCTest, реальные iPhone/iPad,
TLS ВТБ/Т-Банк и отрицательные TLS случаи, вход Google/сохранение сессий, загрузки,
native Cookie и OS-иконки/status bar. Windows preview не заменяет эти проверки.
Отдельная Google-учётная запись ATMA/OAuth не подключена; назначение такой
авторизации требует уточнения, если она нужна помимо входов на самих сайтах.
Сравнение скорости с Safari/Chrome на iPhone не выполнялось.

Codemagic не запускался; время сборки не измерено. Новая конфигурация только
локальная: manual M2, iPhone/iPad checks и отдельный verified-revision TestFlight.
Git push, подпись и публикация не выполнялись. Предпросмотр и сервер не
перезапускались; серверные startup/RU-EN/CSP изменения применятся при следующем
обычном запуске. Все новые рабочие файлы и результаты находятся на D:.

Дополнение: собственные media/YouTube-модули и актуальные проверки описаны в
[отчёте плеера](media-player-verification-2026-10-23.md). Актуальные числа:
10 Node adapter, 48 preview Node, 10 Python; 261 product files. Реальные Chromium
PiP/YouTube проверены, Apple runtime остаётся непроверенным.
