# Надёжная локализация — дашборд

**Цель:** подготовить easy_localization_continued 4.0.0 с единым владельцем локализации и API без обязательного BuildContext.
**Ветки:** код `feature/localization-reliability` → `develop`; план `master` в `D:\.projects\plans`.
**Уровень:** UI + домен. **Кандидат:** не заморожен. База AUDIT-10 — `96c8bb0d2d2ad5bb7835a4151b27a98e7ebfdbaa`. Прежние оценки REL-4/REL-15 сохранены в архиве.

## Сейчас

Pool AUDIT-8 завершён: все четыре карточки приняты; AUD-39/40 прошли независимое ревью, AUD-41/42 приняты без ревью; pool style — PASS. Housekeeping не потребовал слияний. Кодовый HEAD после AUDIT-8 был `384602b`; общий release PASS не устанавливался. [Отчёт аудита](cards/notes/adversarial-audit-8-2026-11-10.md).

Pool AUDIT-8-DECISIONS завершён: AUD-43/44/46 — ACCEPTED, AUD-45 — DEFERRED; независимое ревью AUD-46 и pool style — PASS; housekeeping без слияний, семь логов удалены. Кодовый HEAD `a79a577`; [digest AUDIT-8-DECISIONS](cards/notes/orchestrator-digest.md). Пул вне обязательного release gate.

Общий AUDIT-9-R принял девять назначенных карточек; исправление AUD-55 подтверждено. Housekeeping завершён: веток и worktree пула для слияния или удаления не было; удалены 23 завершённых лога пула. STYLE-AUDIT-9-1 принят, pool style PASS на `96c8bb0`. [Результат проверки](cards/notes/audit-9-pool-style.md). Следующий шаг — передача итогового SHA в RELEASE и [CHECK-15](cards/CHECK-15.md).

AUDIT-10 исполняется последовательно. AUD-63…66 выполнены; общий review обнаружил дефект обработки синхронного исключения в AUD-63 и отсутствие результата analyze в отчёте AUD-64. Обе карточки возвращены Executor на адресную доработку; общий re-review — после исправлений. CHECK-16 следует после повторной приёмки.

## Нужно от Инженера

- Для [CHECK-16](cards/CHECK-16.md) подготовить Flutter SDK 3.44.0 в отдельной папке вне проекта и передать путь при запуске. Без него проверится только минимальное разрешение зависимостей.

- После приёмки AUDIT-10 на одном итоговом SHA выполнить полный suite с scenarios, PR Check с example и package dry-run и ручной [CHECK-15](cards/CHECK-15.md). До получения трёх результатов статус выпуска остаётся открытым.
- PR #1 открыт; merge, tag и публикация не выполнялись. Перед подготовкой tag нужно заменить `Unreleased` датой 4.0.0.
- Первая публикация и режим последующих публикаций остаются решением владельца; проверка pub.dev ранее вернула 404. [AUD-28](cards/AUD-28.md) фиксирует release guidance.
- [AUD-22](cards/AUD-22.md): SDK TLS advisory исследован, но нужна конкретная зависимая app/consumer для triage; изменение зависимостей не назначено.
- Отдельная сверка плановой ветки: commit `5e2f09e` AUD-51 в `D:\.projects\plans` включил staged изменения карточки и журнала `fitplus-app` (`INBOX-MESSAGES-UI-1`). Ветка уже продвинулась до `8acb127`, в рабочем дереве есть новые изменения; историю не переписывал, чтобы не задеть параллельную работу. Владелец должен сверить это после AUDIT-9.
- На заметку: одиночный зависший загрузчик или делегат без уже полученной ошибки по-прежнему не имеет timeout; [AUD-40](cards/AUD-40.md) закрывает только случай, когда другой loader уже сообщил ошибку. Путь `path` с завершающим `/` не находит ассеты (так было и в 3.x).

## Решения Инженера

- 11.11.2026: в AUDIT-10 включить все замечания аудита `96c8bb0`: тест связанных JSON примера в CI, сверку тега с версией в release workflow (правка workflow разрешена), проверку минимальных SDK и зависимостей. Карточки, меняющие `easy_localization_app.dart` или файловые загрузчики, завершаются прогоном всех тестов пакета и smoke-теста примера.
- 11.11.2026: в 4.0 добавить пункты 1–11 аудита `a79a577`, сохранить явно предпочитаемую письменность, разрешать ссылки сначала в словаре исходной фразы и уточнить два публичных контракта документацией.
- 10.11.2026: замена корня сменой key за один кадр поддерживается (пересматривает AUD-25). Недоступное хранилище не проваливает startup (пересматривает AUD-2). AUDIT-7 выполняется до 4.0.0. Отдельный Windows CI не нужен.
- 10.11.2026: «Подтверждаю состав» — утверждён минимальный состав пула AUDIT-8-DECISIONS по обоснованию Feature Architect.
- 10.11.2026: AUD-43 — следующий точный preferred-регион того же языка; AUD-44 — доверенные каталоги и явная документация; AUD-45 — ручной browser/WASM checkpoint без постоянного CI; AUD-46 — разрешено упрощение публичного AssetLoader API в 4.0 до выпуска.

## План работ

```text
AUDIT-7 + REL-15 (закрыты, историческая оценка)
  └→ AUDIT-8 завершён: четыре карточки приняты; независимое ревью и pool style прошли; housekeeping выполнен
      └→ AUDIT-9 завершён
          └→ AUDIT-10 → итоговый SHA → полный suite + PR Check + CHECK-15 → решение о merge / tag / publish
AUDIT-8-DECISIONS завершён вне release gate: AUD-43/44/46 ACCEPTED, AUD-45 DEFERRED; ревью и pool style PASS; housekeeping завершён.
```

### Pool AUDIT-8 — исправления аудита 8

Одна линия в main tree, сверху вниз — порядок исполнения; отдельная приёмка предшественника не требуется. Все четыре карточки специфицированы. AUD-39/40 делят instance tests; параллельные агенты не назначены. AUDIT-8-R проверит обе карточки одним проходом после завершения AUD-42; повторять проверки Executor не требуется. Выход: карточки приняты, housekeeping и pool style закрыты; общий release PASS этим не устанавливается.

| Задача | Результат |
| --- | --- |
| ✅ Pool AUDIT-8 | Все четыре карточки приняты; AUD-39/40 прошли независимое ревью; pool style PASS. Housekeeping без слияний; кодовый HEAD `384602b`. |

### Pool AUDIT-8-DECISIONS — вне обязательного release gate

Политики и состав подтверждены Инженером. AUD-43/44/46 приняты; AUD-45 отложена по решению Инженера и фиксирует ручной checkpoint. AUD-46 прошло независимое ревью; pool style — PASS по AUD-43/46. Housekeeping не обнаружил слияний; относящиеся к пулу логи удалены. Принятые AUD-20 и CHECK-10…14 не пересматривались.

| Задача | Результат |
| --- | --- |
| ✅ Pool AUDIT-8-DECISIONS | AUD-43/44/46 приняты; AUD-45 DEFERRED. Независимое ревью AUD-46 и pool style PASS; housekeeping без слияний; кодовый HEAD `a79a577`. Подробности — в digest и архиве ниже. |

### Pool AUDIT-9 — исправления аудита `a79a577` и согласованные уточнения

Одна линия в основном checkout; общий проход AUDIT-9-R охватил все изменения пула, затем pool style PASS и correction принята. Все карточки закрыты и сняты с активной доски; подробные SHA и доказательства — в [digest AUDIT-9](cards/notes/audit-9-digest.md). Кодовый HEAD `96c8bb0d2d2ad5bb7835a4151b27a98e7ebfdbaa`; общий release PASS не устанавливался.

| ✅ Pool AUDIT-9 | ACCEPTED | Все 16 карточек (AUD-47…AUD-62) и STYLE-AUDIT-9-1 приняты; единый pool review, pool style PASS, housekeeping завершён; итоговый кодовый HEAD `96c8bb0`. | [Digest](cards/notes/audit-9-digest.md) |

### Pool AUDIT-10 — блокеры аудита перед выпуском `96c8bb0`

Одна линия в основном checkout, порядок сверху вниз; карточки независимы, предшественник принимать не нужно. Для карточек `Review: none`; после реализации всех изменений проводится один общий проход ревью по коду всего пула, затем pool style review. Карточка, меняющая `easy_localization_app.dart` или файловые загрузчики, перед завершением прогоняет все тесты пакета и smoke-тест примера. CHECK-16 идёт последней, на итоговом коде пула. Выход: AUD-63…66 и CHECK-16 приняты, общее ревью и pool style PASS; общий release PASS этим не устанавливается.

| Задача | Результат |
| --- | --- |
| [AUD-63](cards/AUD-63.md)<br>ACCEPTED · M1 · Review: none · `0883c612949e33e78aec96638ad4ff02b3ed41a8` | Синхронный отказ сразу попадает в общий `catch`, следующий делегат не вызывается; полный пакет 347/347, smoke примера 2/2. |
| [AUD-64](cards/AUD-64.md)<br>TODO · E2 · Codex · Review: none | UI: требуется добавить результат обязательного `flutter analyze --no-pub test/locale_wait.dart` в отчёт (или выполнить проверку, если она не запускалась). |
| [AUD-65](cards/AUD-65.md)<br>ACCEPTED · E1 · Review: none · `95aed09` | Примеры API-документации используют форму 4.0 без `context:`; analyze и format прошли. |
| [AUD-66](cards/AUD-66.md)<br>ACCEPTED · E2 · Codex · Review: none | Domain: **Сейчас:** CI не запускает тест связанных JSON примера, а release публикует по тегу, не сверяя его с версией. **Станет:** CI проверяет связанные JSON, публикация останавливается при несовпадении тега и версии. <br><br>**Проверили:** связанный JSON тест прошёл; совпадающий тег принят, несовпадающий остановлен. YAML прочитан вручную; PyYAML недоступен. |
| [CHECK-16](cards/CHECK-16.md)<br>TODO · E2 · Review: none · Needs: Flutter 3.44.0 | Domain: **Результат:** известно, собирается ли и проходит ли тесты пакет на Flutter 3.44.0 и на минимальных версиях зависимостей; конфликт получает отдельную карточку исправления. |

### RELEASE

| Задача | Результат |
| --- | --- |
| [CHECK-15](cards/CHECK-15.md) | TODO · ручной JS/WASM journey на итоговом SHA, после приёмки AUDIT-10. |
| Полный suite с scenarios и PR Check | Инженер, один итоговый SHA после приёмки AUDIT-10. |

## Сохраняющиеся ограничения

- API 4.0 требует Dart 3.12/Flutter 3.44; earliest allowed patches и native minima не подтверждены. Browser, Android, iOS Simulator и macOS evidence ограничены средами и journeys в принятых CHECK-10…14.
- Физическая iOS, дополнительные браузеры и native Settings/per-app locale events остаются непроверенными. Pana/platform tags отложены до публикации по решению Инженера.
- Namespace переименован в `easy_localization_continued`; upstream 3.x loader plugins требуют porting. AUD-6 остаётся post-4.0.0.

## После выпуска

| Задача | Результат |
| --- | --- |
| ⏳ [AUD-6](cards/AUD-6.md)<br>BRIEF · Tier не назначен | Domain: **Результат:** после 4.0.0 Architect декомпозирует удаление неиспользуемых веток контроллера (дополнено находками аудита 7); сейчас не release gate. |

## Архив

[AUD-45](cards/AUD-45.md) — DEFERRED · E1 · Owner: Engineer · Review: none. Domain+UI: **Результат:** сохранён ручной browser/WASM checkpoint перед выпуском по CHECK-10; процедура и границы записаны в карточке. Постоянная browser-автоматизация отложена по решению Инженера, отдельный Windows CI не вводится; Executor не нужен.

AUD-43 — ACCEPTED без ревью: следующий точный регион того же языка учитывается перед частичными совпадениями; startup/reset/events/resume и явный выбор сохранены; tests 42/42, targeted analyze PASS; SHA `01af4d0e576744961feb6bacd394cf46664a97e1`.
AUD-44 — ACCEPTED без ревью: README описывает доверенные каталоги и linked JSON для CLI по принятому AUD-20; кодовые проверки пропущены по Validation; SHA `acf7843e4fbfa63cc3fdbeb1c4f77b23001a4b94`.
AUD-46 — ACCEPTED после AUDIT-8-DECISIONS-R: базовый AssetLoader упрощён, локальные и generated loaders мигрированы; 36/36 targeted tests, root/example analyze PASS; reviewer замечаний не нашёл, проверки не повторял; SHA `a79a57742abe97ed8779e65c8a8523a33b898377`. Pool style AUD-43/46 — PASS.

AUD-39 — ACCEPTED после AUDIT-8-R: перенос корня сохраняет экран и состояние, устранённая ошибка делегата исчезает; tests 28/28 и 18/18, analyze PASS; SHA `7d17d31`.
AUD-40 — ACCEPTED после AUDIT-8-R: известная ошибка loader завершает команду сразу, поздние ответы не публикуются; tests 39/39 и 7/7, analyze PASS; SHA `76b5591`.
AUDIT-8-R — приняты AUD-39/40; проверены ревизии/ownership корня и порядок поздних ошибок загрузчиков; повторные проверки не запускались, так как валидированные файлы не менялись.

AUD-42 — ACCEPTED без независимого ревью: strict audit проверяет достижимые связанные строки, отображает циклы как непроверенные; CLI tests 24/24, targeted analyze PASS; SHA `384602b0cb3b16eb226c0eef5fa6f4476af6bb36`.

AUD-41 — ACCEPTED без независимого ревью: пустые связанные переводы сохраняются, fallback работает; resolution tests 10/10, targeted analyze PASS; SHA `d4b8d50`.

AUDIT-7 — шесть карточек приняты, AUD-33 и AUD-37 прошли AUDIT-7-R; housekeeping и pool style закрыты. Единственный кандидат стиля отклонён ([решение](cards/notes/audit-7-pool-style.md#решение-decision-architect--10112026)). Новые дефекты повторной активации оформлены отдельно в AUD-39.

REL-15 — аудит принят на `bb71786a3e3f00c698ecb14acafbaf585f525042`: подтверждённых BLOCKER/SHOULD FIX нет в проверенном scope; полный suite с scenarios/example и PR Check UNVERIFIED, общий PASS не установлен. ACCEPTED без ревью.

AUD-36 — ошибка legacy-конфигурации называет первое изменённое поле; README и changelog поясняют правила равенства и миграцию `startLocale`. ACCEPTED без ревью, `dd530c2526f3b6a1950e5fb6cd216fe5759f7bb5`.

AUD-34 — plural подставляет число при пустых аргументах, а владелец без сохранения скрывает прежний язык; отмена получила понятное описание. ACCEPTED без ревью, `6469dff9d212fec8a51d990a4eef69889f75c7c5`.

AUD-38 — startup переживает ошибку чтения storage, ошибки записи доступны в состоянии; ACCEPTED без ревью, `61c2b2ac34f5816dd1fa212b8db6a496523e0a99`.

AUD-35 — нераспознанные вызовы перевода и соседние строковые литералы отображаются как непроверенные; ACCEPTED без ревью, `bb71786a3e3f00c698ecb14acafbaf585f525042`.

AUD-31/32 и REL-4 приняты; [итоговый CI](https://github.com/Anfet/easy_localization/actions/runs/42722030097). Повторный аудит 6 не нашёл новых задач: [отчёт](cards/notes/repeat-audit-6-2026-11-10.md). Ранее завершённые CORE/TOOLS/DEMO/DOCS, RELEASE prep, SIMPLIFICATION и AUDIT-1/2: [сводка](cards/notes/completed-through-audit-2-2026-11-09.md). AUDIT-3/CHECK-13: [отчёт](cards/notes/adversarial-audit-3-2026-11-09.md); AUD-29/30 и CHECK-14 — в карточках.





