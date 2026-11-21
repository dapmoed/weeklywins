# Единое расположение кнопки записи — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Кнопка записи на «Сегодня» и «Записи» в одной позиции (эталон — «Записи»: 40 pt от левого края, 40 pt над панелью вкладок); кнопка «Поделиться» на «Отчётах» симметрична справа (40/40).

**Architecture:** Достаточно изменить константы отступов: `dayRecordInset` 20 → 40 в `ReportView` и padding оверлея «Поделиться» 20 → 40 по trailing/bottom. На «Записи» ничего не меняется.

**Tech Stack:** SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-21-unify-record-button-design.md`

## Global Constraints

- Размер (48), цвет и поведение кнопок не меняются.
- Панель вкладок рисуется в `StudioRootView` под всеми вкладками — линия «над панелью» общая.
- Команда тестов и правила коммитов — как в плане `2026-11-21-remove-event-time-duration.md`.

## Review Focus

- Нижний отступ прокрутки на «Сегодня» должен вырасти вместе с кнопкой, иначе последняя карточка не прокрутится выше кнопки (проверяется скриншотом).
- Коралловая панель записи и панель undo не перекрывают кнопку.

---

### Task C1: Отступы кнопок

**Files:**
- Modify: `WeeklyWins/Reports/ReportView.swift:29,292,302-303,167` (share overlay padding)

**Interfaces:**
- Produces: нет новых API.

- [ ] **Step 1: Снять базовые скриншоты** — «Сегодня» и «Записи» с кнопкой, сохранить в `shots/quick-changes/`.

- [ ] **Step 2: Изменить отступы**

- `ReportView.dayRecordInset`: `20` → `40` (меняет и padding кнопки, и нижний contentMargins).
- В `reportsContent` оверлей «Поделиться»: `.padding(20)` → `.padding(.trailing, 40).padding(.bottom, 40)`.

- [ ] **Step 3: Сборка и тесты**

Run: build + команда тестов. Expected: PASS/SKIP как раньше.

- [ ] **Step 4: Скриншотная проверка** — обе вкладки: кнопка записи в одном углу с одинаковыми отступами; «Отчёты»: «Поделиться» зеркально справа на той же высоте. Сравнить с `shots/quick-changes/` базовыми.

- [ ] **Step 5: Commit**

```bash
git add WeeklyWins/Reports/ReportView.swift shots/quick-changes/
git commit -m "feat: unify record button placement, symmetric share button"
```
