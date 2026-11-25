import SwiftUI

struct EventDetailView: View {
    let entry: ReportEntry
    @ObservedObject var service: RecordingService
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var textFocused: Bool
    @State private var draft: DiaryEvent?
    @State private var baseline: DiaryEvent?
    @State private var source: Source?
    @State private var showCategoryPicker = false
    @State private var showFragment = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var deletedEvent: RecordingService.DeletedEvent?

    private enum Source: String, Identifiable {
        case playback, editing
        var id: Self { self }
    }

    private let drafts = EventDraftStore()
    private let dateFormat = Date.FormatStyle.dateTime.day().month(.wide).year().hour().minute()
        .locale(Locale(identifier: "ru_RU"))

    private var recording: Recording? { service.recordings.first { $0.id == entry.recording.id } }
    private var event: DiaryEvent? { recording?.events?.first { $0.id == entry.event.id } }
    private var hasChanges: Bool { draft != baseline }

    var body: some View {
        Group {
            if let event {
                details(event)
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView("Событие удалено", systemImage: "trash")
                    if let deletedEvent {
                        Button("Отменить удаление") { restore(deletedEvent) }
                    }
                    if let error { Text(error).foregroundStyle(StudioTheme.coral) }
                }
            }
        }
        .scrollContentBackground(.hidden).background(StudioTheme.background)
        .navigationTitle("Событие").navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(hasChanges)
        .toolbar {
            if draft != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Удалить событие", role: .destructive) {
                            textFocused = false
                            confirmDelete = true
                        }
                        .accessibilityIdentifier("event-editor-delete")
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Действия события")
                    .accessibilityIdentifier("event-editor-actions")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if draft != nil { saveControl }
        }
        .sheet(item: $source) { source in
            if let recording {
                TranscriptView(recording: recording, recordingService: service, startEditing: source == .editing)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persistDraft() }
        }
        .confirmationDialog("Закрыть редактор?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Сохранить изменения", action: save)
            Button("Отбросить изменения", role: .destructive, action: endEditing)
        }
        .confirmationDialog("Удалить событие?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить событие", role: .destructive) {
                if let event { delete(event) }
            }
            .accessibilityIdentifier("confirm-event-deletion")
        }
    }

    private func details(_ event: DiaryEvent) -> some View {
        List {
            Section {
                if let draft {
                    TextField("Что сделали", text: Binding(
                        get: { self.draft?.text ?? draft.text },
                        set: { self.draft?.text = $0 }
                    ), axis: .vertical)
                    .focused($textFocused)
                    .accessibilityIdentifier("event-editor-title")
                } else {
                    Button { beginEditing(event) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(event.text).font(.title2.weight(.semibold))
                                .foregroundStyle(StudioTheme.text)
                            Spacer(minLength: 4)
                            Image(systemName: "pencil")
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Редактировать текст события")
                    .accessibilityIdentifier("edit-event")
                }

                let category = draft?.category ?? event.category
                Button { showCategoryPicker = true } label: {
                    Label(category.title, systemImage: categoryIcon(category))
                        .foregroundStyle(StudioTheme.categoryColor(category))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("event-category")
                .confirmationDialog("Категория", isPresented: $showCategoryPicker, titleVisibility: .visible) {
                    ForEach(EventCategory.allCases) { option in
                        Button(option.title) { selectCategory(option, for: event) }
                    }
                    Button("Отмена", role: .cancel) {}
                }
            }.listRowBackground(StudioTheme.surface)

            Section {
                let date = entry.recording.recordedAt.formatted(dateFormat)
                Text("Запись \(date)")
                    .foregroundStyle(StudioTheme.secondary)
                    .accessibilityLabel("Время записи")
                    .accessibilityValue(date)
                    .accessibilityIdentifier("event-time")
                Button("Изменить расшифровку") { source = .editing }
                    .disabled(service.transcribingRecordingIDs.contains(event.recordingID))
                    .accessibilityIdentifier("edit-event-transcript")
                DisclosureGroup("Источник", isExpanded: $showFragment) {
                    Text(event.sourceText).foregroundStyle(StudioTheme.secondary)
                    Button("Открыть аудиозапись и текст") { source = .playback }
                }
            }.listRowBackground(StudioTheme.surface)

            if draft == nil {
                Section {
                    Button("Удалить событие", role: .destructive) { delete(event) }
                }.listRowBackground(StudioTheme.surface)
            }
            if let error { Text(error).foregroundStyle(StudioTheme.coral) }
        }
    }

    private func categoryIcon(_ category: EventCategory) -> String {
        switch category {
        case .work: "briefcase"
        case .home: "house"
        case .unclassified: "tag"
        case .hobby: "paintpalette"
        }
    }

    private func beginEditing(_ event: DiaryEvent) {
        error = nil
        baseline = event
        draft = drafts.load(for: event) ?? event
        textFocused = true
    }

    private func cancelEditing() {
        textFocused = false
        if hasChanges { confirmDiscard = true }
        else { endEditing() }
    }

    private func endEditing() {
        if let draft { drafts.remove(id: draft.id) }
        resetEditing()
    }

    private func resetEditing() {
        textFocused = false
        baseline = nil
        draft = nil
        error = nil
    }

    private func selectCategory(_ category: EventCategory, for event: DiaryEvent) {
        if draft != nil {
            draft?.category = category
        } else {
            guard event.category != category else { return }
            var updated = event
            updated.category = category
            do { try save(updated, replacing: event) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        guard let draft, let baseline else { return }
        do {
            try save(draft, replacing: baseline)
            endEditing()
        } catch { self.error = error.localizedDescription }
    }

    private func save(_ draft: DiaryEvent, replacing baseline: DiaryEvent) throws {
        guard let recording, var events = recording.events,
              let index = events.firstIndex(where: { $0.id == baseline.id }) else {
            throw RecordingStoreError.recordingNotFound
        }
        guard events[index] == baseline else { throw EventEditingError.conflictingChanges }
        events[index] = draft
        try service.saveEvents(recordingID: recording.id, events: events, expectedEvents: recording.events)
    }

    private func persistDraft() {
        guard let draft, let baseline, event != nil else { return }
        do {
            if hasChanges { try drafts.save(draft, baseline: baseline) }
            else { drafts.remove(id: draft.id) }
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ event: DiaryEvent) {
        do {
            deletedEvent = try service.deleteEvent(baseline ?? event, editorDraft: draft)
            resetEditing()
        } catch { self.error = error.localizedDescription }
    }

    private func restore(_ deletion: RecordingService.DeletedEvent) {
        do {
            try service.restoreEvent(deletion)
            deletedEvent = nil
        } catch { self.error = error.localizedDescription }
    }

    private var saveControl: some View {
        let canSave = hasChanges && draft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return VStack(alignment: .leading, spacing: 8) {
            Button(action: save) {
                Text("Сохранить")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.background)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(StudioTheme.mint, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.55)
            .accessibilityIdentifier("save-event")
            Button("Отмена", action: cancelEditing)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(StudioTheme.background)
    }

}
