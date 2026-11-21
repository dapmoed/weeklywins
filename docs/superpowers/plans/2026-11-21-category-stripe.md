# Кромка категории в ленте дня — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Цветная кромка 6 pt в цвете категории по левому краю карточек дел ленты дня.

**Architecture:** Кромка — `Rectangle` шириной 6 в `.background(alignment: .leading)` строки дела, обрезается существующим `clipShape(RoundedRectangle(cornerRadius: 16))`, поэтому повторяет скругление автоматически. Текст сдвигается за счёт того, что кромка занимает левые 6 pt строки; визуальный зазор до текста сохраняется прежним (~12 pt).

**Tech Stack:** SwiftUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-21-category-stripe-design.md`

## Global Constraints

- Палитра: только `StudioTheme.categoryColor(_:)` (мята/песок/серый), новых цветов нет.
- Форма карточки, шрифты, отступы текста не меняются (кроме занятой кромкой площади).
- Команда тестов и правила коммитов — как в плане `2026-11-21-remove-event-time-duration.md`.
- Выполняется ПОСЛЕ удаления времени/длительности (та же функция `dayEventRow`).

## Review Focus

- Свайп на удаление: кромка уезжает вместе с карточкой, кнопка «Удалить» сзади не перекрывается (проверяется скриншотом и существующим UI-тестом свайпа).
- Dynamic Type ( accessibility-размеры): кромка фиксированной ширины не ломает вёрстку.
- Дела без категории: нейтральная серая кромка — заметна, но не кричит.

---

### Task B1: Кромка в dayEventRow

**Files:**
- Modify: `WeeklyWins/Reports/ReportView.swift:368-436`

**Interfaces:**
- Consumes: `StudioTheme.categoryColor(_:)`; `DiaryEvent.category`.
- Produces: нет новых API.

- [ ] **Step 1: Убедиться, что день ленты открывается в UI-тесте**

Запустить `ActionButtonUITests.testDaySwipeRevealsDeleteAndCanRestoreTheCard` (команда тестов). Expected: PASS или SKIP (нет фикстуры) — зафиксировать базовое состояние.

- [ ] **Step 2: Добавить кромку**

В `dayEventRow` после `.background(StudioTheme.surface)` (строка ~409) добавить:

```swift
.background(alignment: .leading) {
    Rectangle()
        .fill(StudioTheme.categoryColor(entry.event.category))
        .frame(width: 6)
}
```

(внутрь существующей цепочки, до `.offset` и `clipShape`, чтобы кромка жила внутри скруглённой формы).

- [ ] **Step 3: Сборка и тесты**

Run: build + команда тестов. Expected: PASS.

- [ ] **Step 4: Скриншотная проверка по AGENTS.md**

На симуляторе с фикстурой (см. `docs/device-test-session.md` / `RUN_REDESIGN_AUDIT_FIXTURE`) открыть «Сегодня», снять скриншот, сравнить с `docs/design/layout-a-today-approved-2026-11-20.png`: совпадают дата/вкладки/карточки; новое — только кромки. Проверить все три категории и свайп. Сохранить скриншот в `shots/`.

- [ ] **Step 5: Commit**

```bash
git add WeeklyWins/Reports/ReportView.swift shots/
git commit -m "feat: category-colored stripe on day feed cards"
```
