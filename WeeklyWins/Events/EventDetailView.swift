import SwiftUI

struct EventDetailView: View {
    let entry: ReportEntry
    @ObservedObject var service: RecordingService
    @State private var editing = false
    @State private var showSource = false
    @State private var error: String?
    @State private var deletedEvent: RecordingService.DeletedEvent?

    private let dateFormat = Date.FormatStyle.dateTime.day().month(.wide).year().hour().minute()
        .locale(Locale(identifier: "ru_RU"))

    private var recording: Recording? { service.recordings.first { $0.id == entry.recording.id } }
    private var event: DiaryEvent? { recording?.events?.first { $0.id == entry.event.id } }

    var body: some View {
        Group {
            if let event {
                List {
                    Section {
                        Text(event.text).font(.title2.weight(.semibold))
                        Label(event.category.title, systemImage: categoryIcon(event.category))
                            .foregroundStyle(StudioTheme.categoryColor(event.category))
                        LabeledContent("Статус", value: event.completion.title)
                    }.listRowBackground(StudioTheme.surface)
                    Section("Когда и сколько") {
                        let time = event.occurredAt?.formatted(dateFormat) ?? "Не указано"
                        LabeledContent("Время дела", value: time)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Время дела")
                            .accessibilityValue(time)
                            .accessibilityIdentifier("event-time")
                        LabeledContent("Длительность", value: StudioTheme.duration(event.duration))
                    }.listRowBackground(StudioTheme.surface)
                    Section("Источник") {
                        Text(event.sourceText).foregroundStyle(StudioTheme.secondary)
                        Button("Открыть аудиозапись и текст") { showSource = true }
                        Text("Записано \(entry.recording.recordedAt.formatted(dateFormat))")
                            .font(.footnote).foregroundStyle(StudioTheme.secondary)
                    }.listRowBackground(StudioTheme.surface)
                    Section {
                        Button("Изменить") { editing = true }.accessibilityIdentifier("edit-event")
                        Button("Удалить событие", role: .destructive) {
                            do { try delete(event) }
                            catch { self.error = error.localizedDescription }
                        }
                    }.listRowBackground(StudioTheme.surface)
                    if let error { Text(error).foregroundStyle(StudioTheme.coral) }
                }
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
        .sheet(isPresented: $showSource) {
            TranscriptView(recording: recording ?? entry.recording, recordingService: service)
        }
        .sheet(isPresented: $editing) {
            if let event {
                EventEditorView(event: event, service: service) { draft, baseline in
                    try delete(baseline, editorDraft: draft)
                }
            }
        }
    }

    private func categoryIcon(_ category: EventCategory) -> String {
        switch category {
        case .work: "briefcase"
        case .home: "house"
        case .unclassified: "tag"
        }
    }

    private func delete(_ event: DiaryEvent, editorDraft: DiaryEvent? = nil) throws {
        deletedEvent = try service.deleteEvent(event, editorDraft: editorDraft)
    }

    private func restore(_ deletion: RecordingService.DeletedEvent) {
        do {
            try service.restoreEvent(deletion)
            deletedEvent = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct EventEditorView: View {
    @State private var event: DiaryEvent
    @ObservedObject var service: RecordingService
    let onDelete: (DiaryEvent, DiaryEvent) throws -> Void
    @State private var error: String?
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var isClosing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let drafts = EventDraftStore()
    @State private var baseline: DiaryEvent

    init(event: DiaryEvent, service: RecordingService, onDelete: @escaping (DiaryEvent, DiaryEvent) throws -> Void) {
        self.service = service
        self.onDelete = onDelete
        _baseline = State(initialValue: event)
        _event = State(initialValue: EventDraftStore().load(for: event) ?? event)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Дело") {
                    TextField("Что сделали", text: $event.text, axis: .vertical)
                        .accessibilityIdentifier("event-editor-title")
                }.listRowBackground(StudioTheme.surface)
                Section {
                    Picker("Категория", selection: $event.category) {
                        ForEach(EventCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Статус", selection: $event.completion) {
                        ForEach(EventCompletion.allCases) { Text($0.title).tag($0) }
                    }
                }.listRowBackground(StudioTheme.surface)
                Section("Необязательные сведения") {
                    Toggle("Указать время дела", isOn: Binding(get: { event.occurredAt != nil }, set: { event.occurredAt = $0 ? .now : nil }))
                    if event.occurredAt != nil {
                        DatePicker("Когда", selection: Binding(get: { event.occurredAt ?? .now }, set: { event.occurredAt = $0 }))
                    }
                    Toggle("Указать длительность", isOn: Binding(get: { event.duration != nil }, set: { event.duration = $0 ? 60 : nil }))
                    if event.duration != nil {
                        LabeledContent("Минуты") {
                            TextField("Минуты", value: Binding(
                                get: { (event.duration ?? 0) / 60 },
                                set: { event.duration = max(0, $0) * 60 }
                            ), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("event-duration-minutes")
                        }
                    }
                }.listRowBackground(StudioTheme.surface)
            }
            .scrollContentBackground(.hidden).background(StudioTheme.background)
            .navigationTitle("Изменить событие").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { confirmDiscard = true } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Удалить событие", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("event-editor-delete")
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Действия события")
                    .accessibilityIdentifier("event-editor-actions")
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveControl
            }
            .interactiveDismissDisabled()
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background, !isClosing,
                      service.recordings.first(where: { $0.id == event.recordingID })?
                        .events?.contains(where: { $0.id == event.id }) == true else { return }
                do {
                    if event == baseline { drafts.remove(id: event.id) }
                    else { try drafts.save(event, baseline: baseline) }
                } catch { self.error = error.localizedDescription }
            }
            .confirmationDialog("Закрыть редактор?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Сохранить изменения") { save() }
                Button("Отбросить изменения", role: .destructive, action: closeEditor)
            }
            .confirmationDialog("Удалить событие?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить событие", role: .destructive) {
                    do {
                        try onDelete(event, baseline)
                        closeEditor()
                    } catch { self.error = error.localizedDescription }
                }
                .accessibilityIdentifier("confirm-event-deletion")
            }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }

    private var saveControl: some View {
        let canSave = !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(StudioTheme.coral)
            }
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(StudioTheme.background)
    }

    private func closeEditor() {
        isClosing = true
        drafts.remove(id: event.id)
        dismiss()
    }

    private func save() {
        do {
            guard let recording = service.recordings.first(where: { $0.id == event.recordingID }),
                  let index = recording.events?.firstIndex(where: { $0.id == event.id }) else { throw RecordingStoreError.recordingNotFound }
            var events = recording.events ?? []
            guard events[index] == baseline else { throw EventEditingError.conflictingChanges }
            events[index] = event
            try service.saveEvents(recordingID: event.recordingID, events: events)
            closeEditor()
        } catch { self.error = error.localizedDescription }
    }
}
