# Обмен расшифровками в JSON (выгрузка и импорт) — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** В «Настройках» выгрузка всех расшифровок в `weeklywins-transcripts.json` через лист «Поделиться» и импорт такого файла обратно с дедупликацией по UUID записи.

**Architecture:** Чистый DTO `TranscriptExport` (кодирование/декодирование, unit-тестируем), метод `RecordingStore.importRecordings` (дедупликация, создание записей без аудио) и тонкий UI-слой в `SettingsView` (шаринг временного файла, `fileImporter`, alert с итогами).

**Tech Stack:** Swift 5, SwiftUI (`ShareLink`/`UIActivityViewController` через representable, `.fileImporter`), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-21-transcripts-json-exchange-design.md`

## Global Constraints

- Формат файла — строго как в spec (ключи `app`, `exportedAt`, `recordings[].id/recordedAt/duration/transcript`; ISO 8601, UTF-8, отступы).
- Дедупликация — по `id` против активных (не удалённых) записей; записи без `id` — всегда новые.
- Без новых зависимостей; копирайт русский; iOS 26.
- Команда тестов и правила коммитов — как в плане `2026-11-21-remove-event-time-duration.md`.

## Review Focus

- Файл старого формата без `id` — импортируется как новые записи, без падения (D2).
- Запись с `transcript: null` — не уходит в автоперерасшифровку (D2).
- Повторный импорт того же файла — всё пропускается, alert «0 / M» (D2).
- Повреждённый JSON — alert об ошибке, состояние не меняется (D3).
- Записи очень большого объёма — файл пишется в temp, шеринг не держит данные в памяти (D3).

---

### Task D1: DTO TranscriptExport

**Files:**
- Create: `WeeklyWins/Recording/TranscriptExport.swift`
- Test: `WeeklyWinsTests/TranscriptExportTests.swift`

**Interfaces:**
- Produces:

```swift
struct TranscriptExport: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var id: UUID?
        var recordedAt: Date
        var duration: TimeInterval?
        var transcript: String?
    }
    var app: String
    var exportedAt: Date
    var recordings: [Entry]
    static func make(recordings: [Recording], exportedAt: Date = .now) -> TranscriptExport
    func fileData() throws -> Data
}
```

`make`: только активные (`deletedAt == nil`), сортировка по `recordedAt` по возрастанию, `app = "weeklywins"`. `fileData`: `JSONEncoder`, `outputFormatting = [.prettyPrinted, .sortedKeys]`, `dateEncodingStrategy = .iso8601`.

- [ ] **Step 1: Написать failing-тесты**

`WeeklyWinsTests/TranscriptExportTests.swift`:
- `testMakeIncludesActiveRecordingsOnlySortedAscending` — 3 записи (одна `deletedAt != nil`, порядок перемешан) → `recordings.count == 2`, даты по возрастанию.
- `testFileDataRoundTripsAndIncludesId` — decode обратно равен исходному; в сыром JSON есть строка `"id"`.
- `testDecodesLegacyFormatWithoutId` — JSON без поля `id` декодируется, `recordings[0].id == nil`.

- [ ] **Step 2: Запустить — ожидаем FAIL** (тип не существует).

- [ ] **Step 3: Реализовать `TranscriptExport`** в `WeeklyWins/Recording/TranscriptExport.swift` по интерфейсу выше.

- [ ] **Step 4: Тесты PASS**, затем commit:

```bash
git add WeeklyWins/Recording/TranscriptExport.swift WeeklyWinsTests/TranscriptExportTests.swift
git commit -m "feat: transcript export DTO with round-trip tests"
```

### Task D2: Импорт в RecordingStore

**Files:**
- Modify: `WeeklyWins/Recording/RecordingStore.swift` (новый метод рядом с `beginRecording`)
- Modify: `WeeklyWins/Recording/RecordingService.swift` (пасsthrough)
- Test: `WeeklyWinsTests/TranscriptImportTests.swift`

**Interfaces:**
- Consumes: `TranscriptExport.Entry` (Task D1).
- Produces:

```swift
struct ImportSummary: Equatable { var imported: Int; var skippedDuplicates: Int }
// RecordingStore:
func importRecordings(_ entries: [TranscriptExport.Entry]) throws -> ImportSummary
// RecordingService:
func importTranscriptEntries(_ entries: [TranscriptExport.Entry]) throws -> ImportSummary
```

Правила: пропуск при совпадении `id` с активной записью (`deletedAt == nil`); `id == nil` → свежий UUID; `transcript != nil` → `processingState = .completed`, `transcriptUpdatedAt = .now`, события через `EventExtractor.extract(transcript, recordingID:)`; `transcript == nil` → `processingState = .failed`, `errorMessage = "Аудио недоступно"`, `automaticTranscriptionPending = false`; `state = .saved`, `fileName = "recording-<uuid>.m4a"`; append → sort → persist с откатом при ошибке.

- [ ] **Step 1: Failing-тесты в `TranscriptImportTests.swift`** (временный каталог-хранилище, как в `ReportTests`):
- `testSkipsEntriesWithExistingActiveID` — 2 записи, одна с существующим id → `imported == 1, skippedDuplicates == 1`, в `store.recordings` не дублируется.
- `testImportWithoutIDAssignsFreshUUID` — `id: nil` → появляется запись с новым id, `imported == 1`.
- `testImportWithTranscriptExtractsEvents` — у импортированной записи `events` непустые, `processingState == .completed`.
- `testImportWithoutTranscriptMarksFailed` — `processingState == .failed`, `automaticTranscriptionPending != true`.
- `testDeletedRecordingWithSameIDCanBeRestored` — id совпадает с удалённой (`deletedAt != nil`) → импортируется.
- `testImportedRecordingsPersist` — новый `RecordingStore(directory:)` видит импортированные.

- [ ] **Step 2: Запустить — FAIL** (метода нет).
- [ ] **Step 3: Реализовать** `RecordingStore.importRecordings` и пасsthrough в `RecordingService`.
- [ ] **Step 4: Тесты PASS**, commit:

```bash
git add WeeklyWins/Recording/RecordingStore.swift WeeklyWins/Recording/RecordingService.swift WeeklyWinsTests/TranscriptImportTests.swift
git commit -m "feat: import transcript entries with duplicate protection"
```

### Task D3: UI в Настройках

**Files:**
- Create: `WeeklyWins/Settings/ShareSheet.swift` (`UIActivityViewController` representable)
- Modify: `WeeklyWins/Settings/SettingsView.swift` (секция «Данные»)

**Interfaces:**
- Consumes: `TranscriptExport.make`/`fileData` (D1), `RecordingService.importTranscriptEntries` (D2).
- Produces: кнопки с идентификаторами `settings-export-transcripts`, `settings-import-transcripts`.

- [ ] **Step 1: Реализовать `ShareSheet`** (UIViewControllerRepresentable, принимает `URL`).

- [ ] **Step 2: Добавить секцию «Данные» в `SettingsView`** между «Настроить кнопку действия» и «Версия и сборка»:
- Кнопка «Выгрузить расшифровки (JSON)»: собрать `TranscriptExport.make(recordings:)`, записать `weeklywins-transcripts.json` в `temporaryDirectory`, показать `ShareSheet` через `.sheet(item:)`.
- Кнопка «Импортировать расшифровки (JSON)»: `.fileImporter(allowedContentTypes: [.json])`; чтение через `startAccessingSecurityScopedResource`; decode → `importTranscriptEntries` → alert «Импортировано записей: N. Пропущено дублей: M.»; ошибка decode/чтения → alert «Не удалось прочитать файл».

- [ ] **Step 3: Сборка + тесты** — build, команда тестов. Expected: PASS/SKIP.

- [ ] **Step 4: Ручная проверка на симуляторе** — выгрузка открывает лист «Поделиться» с файлом; сохранить файл, импортировать его обратно → alert «0 / N»; импорт испорченного файла → alert об ошибке.

- [ ] **Step 5: Commit**

```bash
git add WeeklyWins/Settings/
git commit -m "feat: export and import transcripts from Settings"
```
