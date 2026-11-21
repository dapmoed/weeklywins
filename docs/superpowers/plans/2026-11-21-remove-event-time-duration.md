# Удаление времени дела и длительности — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Удалить из модели дела `occurredAt` и `duration` вместе со всеми местами хранения, отображения и парсинга этих значений.

**Architecture:** Жёсткое удаление полей из `DiaryEvent` (мягкая миграция — старые JSON декодируются, т.к. поля опциональные и лишние ключи игнорируются), затем выливание ошибок компиляции и обновление тестов. Распознавание длительностных фраз в экстракторе сохраняется только как правило слияния фразы с предыдущим делом.

**Tech Stack:** Swift 5, SwiftUI, XCTest, XcodeGen-проект без внешних зависимостей.

**Spec:** `docs/superpowers/specs/2026-11-21-remove-event-time-duration-design.md`

## Global Constraints

- iOS deployment target 26.0, Swift 5, без новых зависимостей.
- `Recording.duration` (длина аудио) НЕ трогаем.
- Копирайт на русском, тёмная схема, палитра `StudioTheme` без новых цветов.
- Команда тестов (из `docs/handoff-voice-diary-2026-11-15.md`):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WeeklyWins.xcodeproj -scheme WeeklyWins -destination 'platform=iOS Simulator,id=01FDA22D-80AB-4612-B93C-C63DFD9ABBAB' -derivedDataPath /private/tmp/weeklywins-derived CODE_SIGNING_ALLOWED=NO test`
- UI-тесты с фикстурой скипаются без `RUN_REDESIGN_AUDIT_FIXTURE=1` — это нормально.
- После каждой задачи — коммит.

## Review Focus

- Транскрипт «обсудил проект; встреча заняла час» — «встреча заняла час» должна слиться с делом «обсудил проект», а не стать отдельным делом (покрыто задачей A1).
- Старый манифест записей с `occurredAt`/`duration` в событиях — должен декодироваться без ошибок (покрыто задачей A1).
- Шеринг-текст отчёта не должен содержать длительностей (покрыто задачей A2).
- Дело в другом дне, чем запись (`occurredAt` был) — теперь всегда день записи; сортировка внутри дня по времени записи (покрыто задачей A2).

---

### Task A1: Модель и экстрактор

**Files:**
- Modify: `WeeklyWins/Events/Event.swift:28-29`
- Modify: `WeeklyWins/Events/EventExtractor.swift:40-61` (и приватные помощники длительностей ниже по файлу)
- Test: `WeeklyWinsTests/EventExtractionTests.swift`

**Interfaces:**
- Produces: `DiaryEvent` без полей `occurredAt`, `duration`; инициализатор без них. Все остальные поля и поведение экстрактора без изменений.

- [ ] **Step 1: Обновить тесты под новое поведение**

В `EventExtractionTests.swift`:
- Тесты, чьё единственное назначение — значения длительностей (`testClockStyleDurationRequiresAnExplicitDurationVerb`, `testDecimalDurationsAndClockTimesStayInOneEvent`, `testCompoundAndWordDurationsAreSummedWithinOnePhrase`, `testRelativeAndClockReferencesDoNotBecomeDurations`, `testAmbiguousOrUnsupportedQuantitiesStayUnknown`, `testClockTimesAreNotDurationsAndNegativesAreNotCompleted`, `testSplitsSequenceAndReadsExplicitDuration`, `testPluralMeetingDescriptionKeepsTotalDurationUnknown`, `testStandaloneDurationDescriptionCreatesAnEvent`, `testKnownOrConflictingDurationClarificationKeepsOneEvent`, `testRepeatedClarificationKeepsDurationConflictUnknown`) — удалить или переписать на утверждение числа дел и исходного текста без значений (выбор за исполнителем: если сценарий проверяет сегментацию — переписать, если только значение — удалить).
- Тесты слияния уточнений (`testUserMeetingLinksDurationClarificationAndRetainsPendingFollowUp`, `testClarificationTargetsMatchingMeetingAndPreservesOtherTask`, `testIncidentalFollowUpMentionDoesNotReceiveMeetingDuration`, `testUserServiceNotesKeepUnknownDurationAndOriginalWording`) — убрать все сравнения `duration`, оставить утверждения на число дел и `sourceText`.
- Добавить: `testDurationMentionMergesIntoMentionedEventWithoutValue` — экстракт `("обсудил план с Анной. встреча заняла два часа")` → 1 дело, текст содержит обе фразы.
- Во всём файле удалить использования `occurredAt`/`duration` у `DiaryEvent`.

- [ ] **Step 2: Запустить тесты, убедиться в падении**

Run: команда тестов из Global Constraints
Expected: компиляция тестового таргета падает (полей нет) либо тесты FAIL.

- [ ] **Step 3: Удалить поля и значения длительностей**

- `Event.swift`: удалить `occurredAt` и `duration` из `DiaryEvent` и инициализатора.
- `EventExtractor.swift`: удалить `conflictingDurations`, присвоение `events[index].duration` и `duration:` при создании события; удалить `explicitDuration(in:)`; в `durationClarification`/`clockDurationClarification` сохранить только сигнатуру предиката слияния (можно упростить возвращаемое значение до `String?` субъекта — решение исполнителя, тело не должно больше вычислять `TimeInterval`).

- [ ] **Step 4: Запустить тесты**

Run: команда тестов
Expected: PASS (таргет `WeeklyWinsTests`; таргет приложения может не компилироваться — чинится в A3).

- [ ] **Step 5: Commit**

```bash
git add WeeklyWins/Events/Event.swift WeeklyWins/Events/EventExtractor.swift WeeklyWinsTests/EventExtractionTests.swift
git commit -m "refactor: drop event time and duration from model and extractor"
```

### Task A2: Отчёты

**Files:**
- Modify: `WeeklyWins/Reports/ReportQuery.swift:26,97-150,186-188`
- Test: `WeeklyWinsTests/ReportTests.swift`

**Interfaces:**
- Consumes: `DiaryEvent` без `occurredAt`/`duration` (Task A1).
- Produces: `ReportEntry.date` — `let date: Date { recording.recordedAt }`; `shareText` без строки «Известная длительность» и хвостов «(N мин)»; `knownDuration(_:)` и `durationText(_:)` удалены.

- [ ] **Step 1: Обновить ReportTests**

- Убрать из конструкторов `DiaryEvent` аргументы `occurredAt`/`duration`; `testEventEditsAndDeletionReachAllReportPeriodsAfterReload` — убрать `duration` у событий и `knownDuration`-проверки, проверять `map(\.id)` и категорию (как сейчас).
- `testUserNotesPersistAndReportOneCompletedMeetingHour` в `EventExtractionTests.swift` — переименовать в `testUserNotesPersistAndReportCompletedMeeting`, убрать длительности.

- [ ] **Step 2: Запустить — ожидаем FAIL/ошибки компиляции**

Run: команда тестов. Expected: FAIL.

- [ ] **Step 3: Изменить ReportQuery**

- `ReportEntry.date` → `recording.recordedAt` (убрать ветвление).
- В `shareText` удалить блок `let known = knownDuration(entries)` и строку «Известная длительность».
- В `entryLine(_:)` удалить ветку с `entry.event.duration`.
- Удалить `knownDuration(_:)` и `durationText(_:)`.

- [ ] **Step 4: Запустить тесты**

Run: команда тестов. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WeeklyWins/Reports/ReportQuery.swift WeeklyWinsTests/ReportTests.swift WeeklyWinsTests/EventExtractionTests.swift
git commit -m "refactor: remove durations from report query and share text"
```

### Task A3: Экраны и тема

**Files:**
- Modify: `WeeklyWins/Reports/ReportView.swift:369-370,461-471`
- Modify: `WeeklyWins/Events/EventDetailView.swift:41-47,155-164`
- Modify: `WeeklyWins/Events/EventReviewView.swift:111-113,199-200,218-235`
- Modify: `WeeklyWins/Design/StudioTheme.swift:16-21`

**Interfaces:**
- Produces: карточка ленты с метаданными «Запись 9:41 · Работа» (`timestamp` всегда с префиксом «Запись»); `StudioTheme.duration(_:)` удалён.

- [ ] **Step 1: Запустить сборку, собрать список ошибок**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WeeklyWins.xcodeproj -scheme WeeklyWins -destination 'platform=iOS Simulator,id=01FDA22D-80AB-4612-B93C-C63DFD9ABBAB' -derivedDataPath /private/tmp/weeklywins-derived CODE_SIGNING_ALLOWED=NO build`
Expected: ошибки компиляции только в файлах этой задачи и остальных тестах.

- [ ] **Step 2: Исправить экраны**

- `ReportView.eventDetails`: `let timestamp = "Запись \(entry.date.formatted(.dateTime.hour().minute()))"`; метаданные — `[timestamp, entry.event.category.title]`.
- `EventDetailView`: удалить `dateFormat`/строку времени и `LabeledContent("Длительность", …)`, удалить тумблеры и пикеры времени/длительности (оставить категорию и «Сделано»).
- `EventReviewView`: убрать `duration`-хвост в подписи, тумблеры и степпер длительности/времени, удалить `proposal.duration/occurredAt = nil`.
- `StudioTheme`: удалить `duration(_:)` после устранения последнего использования.

- [ ] **Step 3: Починить остальные тесты**

`AutomaticTranscriptionTests.swift`, `RecordingServiceTests.swift`, `RecordingManagementTests.swift`, `RecordingTests.swift`, `TranscriptionTests.swift` — править только обращения к `DiaryEvent.occurredAt/duration`; `Recording.duration` оставить.

- [ ] **Step 4: Полный прогон тестов**

Run: команда тестов. Expected: PASS (фикстурные UI-тесты skipped).

- [ ] **Step 5: Commit**

```bash
git add WeeklyWins/ WeeklyWinsTests/
git commit -m "refactor: remove event time and duration from UI and theme"
```

### Task A4: Документы дизайна

**Files:**
- Modify: `docs/design/approved-design.md` (строка про «сумму известных длительностей по категориям» в описании Отчётов)
- Modify: `docs/design/layout-options.md` (упоминания длительности/времени дела; длительность аудио оставить)

- [ ] **Step 1: Привести документы в соответствие** — убрать длительность дела и время дела, сохранить длительность аудио в списке записей.

- [ ] **Step 2: Commit**

```bash
git add docs/design/
git commit -m "docs: align design docs with removed event time and duration"
```
