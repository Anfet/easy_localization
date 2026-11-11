# AUD-63 — Вернуть презентацию в том же кадре при синхронных Flutter-делегатах
**Status:** ACCEPTED · **Tier:** M1 · **Owner:** Executor · **Depends On:** — · **Probe:** none
**Pool:** AUDIT-10 · **Line:** main tree · **Priority:** P0 · **Source:** аудит `96c8bb0`, BLOCKER 1
**Review:** none — результат прямо проверяется прежними тестами первого кадра и тестами ранней ошибки AUD-49.
**Style:** project-codestyle core, ui; test-guidelines.

#### Goal
После монтирования корня и после смены языка содержимое снова появляется в том же кадре, что и до AUD-49. Ранняя ошибка асинхронного делегата из AUD-49 сохраняется. Правка локальная: `_EasyLocalizationState._prepare` в `lib/src/easy_localization_app.dart:352–405`.

#### Диагноз
С `5834e30` все выбранные загрузки ждутся через `Future.wait` (`easy_localization_app.dart:374–388`), а он всегда завершается асинхронно. До этого (`0a80a09`, `easy_localization_app.dart:367–371`) `await` стандартного `SynchronousFuture` продолжался синхронно, и `_prepared` был готов в том же `build`. Бисект: на `0a80a09` проходят `easy_localization_widget_test.dart`, `easy_localization_context_test.dart` и `easy_localization_init_test.dart`, на `5834e30` в них 24 падения: 17 + 6 + «a second presentation root is rejected without detaching the first».

#### Architect Decision
1. Запускать выбранные загрузки в прежнем порядке. Если все результаты — `SynchronousFuture` (так работают стандартные Material/Widgets/Cupertino delegates), собирать адаптеры синхронно, без `Future.wait`. Если есть хотя бы одна настоящая асинхронная загрузка, оставить текущий путь AUD-49: `Future.sync` и `Future.wait(eagerError: true)`. Синхронное исключение из `load` идёт в существующий `catch`. Analog: прежняя последовательная сборка `0a80a09:lib/src/easy_localization_app.dart:367–373` расширяется проверкой на `SynchronousFuture`. Scenario: `pumpWidget` с заимствованным или legacy-корнем и стандартными делегатами → первый кадр пустой, `Localization.of` недоступен до второго `pump`.
2. Сохранить выбор первого поддерживающего делегата каждого типа, адаптацию локали AUD-48, проверки ревизии и поколения перед публикацией, а также стадию `flutterDelegates` при ошибке.
3. Решение принято без отдельного вопроса: восстанавливается прежнее поведение, на котором стоят существующие тесты и рецепты README. Принять лишний кадр вместо этого может только Инженер. Score: 45 (локальная правка подготовки с сохранением двух ранее принятых гарантий).

#### Scope
- `lib/src/easy_localization_app.dart` — `_prepare`.
- `test/easy_localization_managed_root_test.dart` — новый тест первого кадра (DoD 2).

#### Constraints
- Не менять тесты, падающие сейчас: они фиксируют контракт, который восстанавливается.
- Публичный API, порядок делегатов и поведение AUD-48/49 не менять.
- Решение Инженера 11.11.2026: карточка меняет `easy_localization_app.dart`, поэтому её итоговая проверка — все тесты пакета и smoke-тест примера, а не только целевые файлы.

#### Definition of Done
1. Прежние сценарии первого кадра снова проходят: `easy_localization_widget_test.dart` 26/26, `easy_localization_context_test.dart` и `easy_localization_init_test.dart` без падений. — проверка: Validation 1 — слой: W — кто: Executor
2. Заимствованный готовый owner со стандартными делегатами → после одного `pumpWidget` без дополнительного `pump` дочерний `Text(tr(...))` найден, а `presentationLocale` равен локали owner. — проверка: Validation 1 — слой: W — кто: Executor
3. Ранняя ошибка AUD-49 сохранена: при открытом gate первого асинхронного делегата отказ второго переводит receipt в `failed`, повторная подготовка применяется. — проверка: Validation 1 (managed root) — слой: W — кто: Executor

#### Validation
При итерации — целевые файлы:
```powershell
python D:/.projects/.tools/scripts/test-batch.py test/easy_localization_widget_test.dart test/easy_localization_context_test.dart test/easy_localization_init_test.dart test/easy_localization_managed_root_test.dart -- --no-pub
flutter analyze --no-pub lib/src/easy_localization_app.dart test/easy_localization_managed_root_test.dart
```
До завершения, по решению Инженера, — все тесты пакета (покрывают DoD 1–3) и smoke-тест примера из `example/`:
```powershell
python D:/.projects/.tools/scripts/test-batch.py test -- --no-pub
flutter test --no-pub test/widget_test.dart
```
Smoke-тест примера проходит только после AUD-64. Если AUD-64 ещё не принята, его падение по `TimeoutException` на сбросе языка в отчёте помечается как ожидаемое.

#### Approach
Сохраняю порядок выбора поддерживающих Flutter-делегатов и собираю их Future последовательно. Пока все результаты являются `SynchronousFuture`, собираю адаптеры в том же стеке; при первой обычной Future перехожу к `Future.wait(eagerError: true)` для всего набора, сохраняя раннюю ошибку AUD-49. Синхронные исключения остаются внутри существующего `try/catch`.
Не добавляю новый helper или тип: развилка локальна в `_prepare` и понятнее рядом с обработкой результатов.
Добавляю проверку первого кадра заимствованного корня и запускаю указанные регрессионные и полные проверки карточки.

#### Executor Report
**Rework R1:** blocking finding закрыт. Синхронное исключение `delegate.load` сразу попадает во внешний `catch`; последующие делегаты не вызываются. Регрессионный тест подтверждает стадию `flutterDelegates` и отсутствие вызова следующего делегата. Уже запущенные asynchronous loads сразу получают обработчик ошибок; прежний тест раннего async отказа проходит.

**Acceptance:** Executor, `Review: none`. Code commit: `0883c612949e33e78aec96638ad4ff02b3ed41a8`.

**Definition of Done:**
1. Существующие сценарии первого кадра восстановлены: widget 26/26, context 10/10 и init 7/7.
2. Добавлен тест заимствованного owner: после единственного `pumpWidget` текст локализации найден и `presentationLocale` равна `en`.
3. Managed-root набор прошёл 21/21, включая ранний отказ второго делегата и повторную подготовку.

**Validation:**
- W: 4 файла, 65/65 тестов; managed-root 22/22 после уточнения distinct resource type.
- U: полный пакет, 35 файлов, 347/347 тестов, 76 с.
- Example smoke: `test/widget_test.dart`, 2/2 теста, 4 с.
- Analyze: оба изменённых Dart-файла, ошибок нет. `git diff --check` чистый.
- Style sweep: только прежний пустой catch (строка 266) и map-кандидат (строка 396), вне исправленного участка.
- Smoke прошёл; AUD-64 timeout больше не воспроизводится после исправления helper.

#### Review
Pool review 11.11.2026, reviewed head `05dd5ffbf89f263fb1373276ac508fb7f4d1b2bf`: blocking finding — in `lib/src/easy_localization_app.dart` the `catch` around `delegate.load(locale)` wraps a synchronous exception in `Future.error` and continues the loop, invoking later delegates. This contradicts Architect Decision 1, which requires synchronous `load` exceptions to reach the existing outer `catch`. Correction: preserve the synchronous throw path so it immediately reaches the outer `catch`; already-started asynchronous loads must retain eager error handling. Add a regression test proving the receipt fails at `flutterDelegates` and the later delegate is not called; keep the existing asynchronous early-error test passing. Re-review closure: inspect fix and regression test; trust existing validation unless the fix invalidates it.

Executor R1 closure: direct `delegate.load(locale)` call now leaves synchronous throws on the existing outer catch path. Regression test verifies the later delegate is not invoked. The asynchronous early-error regression and complete requested validation pass.

Executor R2 closure (`Missed in review 1`): поздний делегат теперь возвращает `_CountedResource`, отдельный тип от `_OtherResource` падающего делегата, поэтому он остаётся выбранным и тест проверяет `loads == 0` именно из-за синхронного отказа. Managed-root, полный пакет и smoke прошли повторно. Code SHA remains `0883c612949e33e78aec96638ad4ff02b3ed41a8`.

Pool review recheck of AUD-63 at `0883c612949e33e78aec96638ad4ff02b3ed41a8`: finding closed; the direct call preserves the synchronous throw, the regression test covers the later delegate, and full package/smoke validation passes.

Missed in review 1: the regression test's failing and later delegates both use `_OtherResource`, so delegate selection removes the later delegate before the failure and the test cannot detect continued iteration. Give the later delegate a different resource type; verify the failure path runs and the later delegate's load count remains zero.
