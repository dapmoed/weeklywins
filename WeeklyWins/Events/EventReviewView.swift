import SwiftUI

struct EventReviewView: View {
    let recording: Recording
    @ObservedObject var service: RecordingService
    @State private var draft: EventReviewDraft
    @State private var errorMessage: String?
    @State private var confirmClose = false
    @State private var deletedEvent: DiaryEvent?
    @State private var deletedIndex = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let drafts = EventReviewDraftStore()

    init(recording: Recording, service: RecordingService) {
        self.recording = recording
        self.service = service
        let baseline = recording.events ?? []
        let events = recording.events ?? EventExtractor.extract(recording.transcript ?? "", recordingID: recording.id)
        _draft = State(initialValue: EventReviewDraftStore().load(recordingID: recording.id)
                       ?? EventReviewDraft(baseline: baseline, events: events))
    }

    private var hasChanges: Bool { draft.events != draft.baseline || draft.mergeProposal != nil }

    var body: some View {
        List {
            ForEach(draft.events) { event in
                Section {
                    DisclosureGroup {
                        ReviewEventFields(event: binding(for: event), defaultDate: recording.recordedAt)
                        DisclosureGroup("Исходный текст") { Text(event.sourceText) }
                        if draft.events.first?.id != event.id {
                            Button("Объединить с предыдущим") { prepareMerge(event.id) }
                        }
                        Button("Удалить событие", role: .destructive) { delete(event.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.text.isEmpty ? "Новое дело" : event.text)
                                .foregroundStyle(StudioTheme.text)
                            Text(event.category.title)
                                .font(.subheadline).foregroundStyle(StudioTheme.categoryColor(event.category))
                        }.padding(.vertical, 8)
                    }
                }.listRowBackground(StudioTheme.surface)
            }
            if deletedEvent != nil {
                Button("Отменить удаление") { undoDelete() }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(StudioTheme.coral) }
        }
        .scrollContentBackground(.hidden).background(StudioTheme.background)
        .navigationTitle("События").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Назад") {
                    if hasChanges { confirmClose = true }
                    else { drafts.remove(recordingID: recording.id); dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Button("Добавить дело") {
                    draft.events.append(DiaryEvent(recordingID: recording.id, sourceText: recording.transcript ?? "", text: ""))
                }.frame(maxWidth: .infinity, minHeight: 44)
                Button("Готово") { save() }
                    .buttonStyle(.borderedProminent).foregroundStyle(StudioTheme.background).frame(minHeight: 44)
            }.padding().background(StudioTheme.background)
        }
        .tint(StudioTheme.mint)
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: draft) { _, _ in persistDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persistDraft() }
        }
        .confirmationDialog("Сохранить изменения?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Сохранить и закрыть") { save() }
            Button("Отбросить изменения", role: .destructive) {
                drafts.remove(recordingID: recording.id)
                dismiss()
            }
            Button("Продолжить редактирование", role: .cancel) {}
        }
        .sheet(item: $draft.mergeProposal) { proposal in
            EventMergeView(event: Binding(
                get: { draft.mergeProposal ?? proposal },
                set: { draft.mergeProposal = $0 }
            ), defaultDate: recording.recordedAt) { merged in
                guard let id = draft.mergingEventID,
                      let index = draft.events.firstIndex(where: { $0.id == id }), index > 0 else { return }
                draft.events[index - 1] = merged
                draft.events.remove(at: index)
                draft.mergeProposal = nil
                draft.mergingEventID = nil
            }
        }
    }

    private func binding(for event: DiaryEvent) -> Binding<DiaryEvent> {
        Binding(
            get: { draft.events.first(where: { $0.id == event.id }) ?? event },
            set: { updated in
                guard let index = draft.events.firstIndex(where: { $0.id == event.id }) else { return }
                draft.events[index] = updated
            }
        )
    }

    private func persistDraft() {
        guard service.recordings.contains(where: { $0.id == recording.id && $0.deletedAt == nil }) else {
            drafts.remove(recordingID: recording.id)
            return
        }
        do {
            if hasChanges { try drafts.save(draft, recordingID: recording.id) }
            else { drafts.remove(recordingID: recording.id) }
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        do {
            try service.saveEvents(recordingID: recording.id, events: draft.events, expectedEvents: draft.baseline)
            drafts.remove(recordingID: recording.id)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ id: UUID) {
        guard let index = draft.events.firstIndex(where: { $0.id == id }) else { return }
        deletedIndex = index
        deletedEvent = draft.events.remove(at: index)
    }

    private func undoDelete() {
        guard let deletedEvent else { return }
        draft.events.insert(deletedEvent, at: min(deletedIndex, draft.events.count))
        self.deletedEvent = nil
    }

    private func prepareMerge(_ id: UUID) {
        guard let index = draft.events.firstIndex(where: { $0.id == id }), index > 0 else { return }
        var proposal = draft.events[index - 1]
        let next = draft.events[index]
        proposal.text += ". " + next.text
        proposal.sourceText += ". " + next.sourceText
        if proposal.category != next.category { proposal.category = .unclassified }
        if next.completion == .notCompleted { proposal.completion = .notCompleted }
        proposal.duration = nil
        proposal.occurredAt = nil
        draft.mergingEventID = id
        draft.mergeProposal = proposal
    }
}

private struct ReviewEventFields: View {
    @Binding var event: DiaryEvent
    let defaultDate: Date

    var body: some View {
        TextField("Дело", text: $event.text, axis: .vertical)
            .accessibilityIdentifier("review-event-text")
        Picker("Категория", selection: $event.category) {
            ForEach(EventCategory.allCases) { Text($0.title).tag($0) }
        }
        Picker("Статус", selection: $event.completion) {
            ForEach(EventCompletion.allCases) { Text($0.title).tag($0) }
        }
        Toggle("Указать время дела", isOn: Binding(
            get: { event.occurredAt != nil },
            set: { event.occurredAt = $0 ? defaultDate : nil }
        ))
        if event.occurredAt != nil {
            DatePicker("Когда", selection: Binding(
                get: { event.occurredAt ?? defaultDate }, set: { event.occurredAt = $0 }
            ))
        }
        Toggle("Указать длительность", isOn: Binding(
            get: { event.duration != nil }, set: { event.duration = $0 ? 60 : nil }
        ))
        if event.duration != nil {
            TextField("Минуты", value: Binding(
                get: { (event.duration ?? 60) / 60 },
                set: { event.duration = max(0, $0) * 60 }
            ), format: .number).keyboardType(.decimalPad)
        }
    }
}

private struct EventMergeView: View {
    @Binding var event: DiaryEvent
    let defaultDate: Date
    let onConfirm: (DiaryEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ReviewEventFields(event: $event, defaultDate: defaultDate)
                } footer: {
                    Text("Проверьте категорию и статус. Время и длительность объединённого дела можно указать заново.")
                }.listRowBackground(StudioTheme.surface)
                Section("Исходный текст") { Text(event.sourceText) }
                    .listRowBackground(StudioTheme.surface)
            }
            .scrollContentBackground(.hidden).background(StudioTheme.background)
            .navigationTitle("Объединить дела").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Объединить") { onConfirm(event) }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(StudioTheme.background)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding().background(StudioTheme.background)
            }
        }.tint(StudioTheme.mint).preferredColorScheme(.dark)
    }
}
