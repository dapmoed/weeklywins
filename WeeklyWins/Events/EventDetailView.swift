import SwiftUI

struct EventDetailView: View {
    let entry: ReportEntry
    @ObservedObject var service: RecordingService
    @State private var editing = false
    @State private var showSource = false
    @State private var error: String?
    @State private var deletedEvent: DiaryEvent?

    private var recording: Recording? { service.recordings.first { $0.id == entry.recording.id } }
    private var event: DiaryEvent? { recording?.events?.first { $0.id == entry.event.id } }

    var body: some View {
        Group {
            if let event {
                List {
                    Section {
                        Text(event.text).font(.title2.weight(.semibold))
                        Label(event.category.title, systemImage: event.category == .home ? "house" : "briefcase")
                            .foregroundStyle(StudioTheme.categoryColor(event.category))
                        LabeledContent("Статус", value: event.completion.title)
                    }
                    Section("Когда и сколько") {
                        LabeledContent("Время дела", value: event.occurredAt?.formatted(date: .abbreviated, time: .shortened) ?? "Не указано")
                        LabeledContent("Длительность", value: StudioTheme.duration(event.duration))
                    }
                    Section("Источник") {
                        Text(event.sourceText).foregroundStyle(StudioTheme.secondary)
                        Button("Открыть аудиозапись и текст") { showSource = true }
                        Text("Записано \(entry.recording.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(StudioTheme.secondary)
                    }
                    Section {
                        Button("Изменить") { editing = true }.accessibilityIdentifier("edit-event")
                        Button("Удалить событие", role: .destructive) { delete(event) }
                    }
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
            if let event { EventEditorView(event: event, service: service) }
        }
    }

    private func delete(_ event: DiaryEvent) {
        do {
            try service.saveEvents(recordingID: event.recordingID, events: (recording?.events ?? []).filter { $0.id != event.id })
            deletedEvent = event
        } catch { self.error = error.localizedDescription }
    }

    private func restore(_ event: DiaryEvent) {
        do {
            var events = recording?.events ?? []
            if !events.contains(where: { $0.id == event.id }) { events.append(event) }
            try service.saveEvents(recordingID: event.recordingID, events: events)
            deletedEvent = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct EventEditorView: View {
    @State private var event: DiaryEvent
    @ObservedObject var service: RecordingService
    @State private var error: String?
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let drafts = EventDraftStore()
    @State private var baseline: DiaryEvent

    init(event: DiaryEvent, service: RecordingService) {
        self.service = service
        _baseline = State(initialValue: event)
        _event = State(initialValue: EventDraftStore().load(for: event) ?? event)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Дело") { TextField("Что сделали", text: $event.text, axis: .vertical) }
                Section {
                    Picker("Категория", selection: $event.category) {
                        ForEach(EventCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Статус", selection: $event.completion) {
                        ForEach(EventCompletion.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Необязательные сведения") {
                    Toggle("Указать время дела", isOn: Binding(get: { event.occurredAt != nil }, set: { event.occurredAt = $0 ? .now : nil }))
                    if event.occurredAt != nil {
                        DatePicker("Когда", selection: Binding(get: { event.occurredAt ?? .now }, set: { event.occurredAt = $0 }))
                    }
                    Toggle("Указать длительность", isOn: Binding(get: { event.duration != nil }, set: { event.duration = $0 ? 60 : nil }))
                    if event.duration != nil {
                        TextField("Минуты", value: Binding(get: { (event.duration ?? 0) / 60 }, set: { event.duration = max(0, $0) * 60 }), format: .number)
                            .keyboardType(.decimalPad)
                    }
                }
                if let error { Text(error).foregroundStyle(StudioTheme.coral) }
            }
            .scrollContentBackground(.hidden).background(StudioTheme.background)
            .navigationTitle("Изменить событие").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { confirmDiscard = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .interactiveDismissDisabled()
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    do { try drafts.save(event, baseline: baseline) }
                    catch { self.error = error.localizedDescription }
                }
            }
            .confirmationDialog("Закрыть редактор?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Сохранить изменения") { save() }
                Button("Отбросить изменения", role: .destructive) { drafts.remove(id: event.id); dismiss() }
            }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }

    private func save() {
        do {
            guard let recording = service.recordings.first(where: { $0.id == event.recordingID }),
                  let index = recording.events?.firstIndex(where: { $0.id == event.id }) else { throw RecordingStoreError.recordingNotFound }
            var events = recording.events ?? []
            guard events[index] == baseline else { throw EventEditingError.conflictingChanges }
            events[index] = event
            try service.saveEvents(recordingID: event.recordingID, events: events)
            drafts.remove(id: event.id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
