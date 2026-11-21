import SwiftUI

struct EventReviewView: View {
    let recording: Recording
    @ObservedObject var service: RecordingService
    @State private var draft: EventReviewDraft
    @State private var errorMessage: String?
    @State private var confirmClose = false
    @State private var restoredEventID: UUID?
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

    private var hasChanges: Bool {
        draft.events != draft.baseline || draft.mergeProposal != nil || draft.hasDeletedEvents
    }

    private var mergingIndex: Int? {
        guard let id = draft.mergingEventID,
              let index = draft.events.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return index
    }

    var body: some View {
        ScrollViewReader { scroll in
            eventList
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .onChange(of: restoredEventID) { _, id in
                    if let id {
                        scroll.scrollTo(id, anchor: .center)
                        restoredEventID = nil
                    }
                }
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
            ), sourceTexts: mergeSources(fallback: proposal.sourceText)) { merged in
                guard let id = draft.mergingEventID else { return }
                draft.confirmMerge(merged, mergingEventID: id)
            }
        }
    }

    private var eventList: some View {
        List {
            ForEach(draft.events) { event in
                Section {
                    DisclosureGroup {
                        ReviewEventFields(event: binding(for: event))
                        DisclosureGroup("Исходный текст") { Text(event.sourceText) }
                        if draft.events.first?.id != event.id {
                            Button("Объединить с предыдущим") { prepareMerge(event.id) }
                        }
                        Button("Удалить событие", role: .destructive) {
                            draft.deleteEvent(id: event.id)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.text.isEmpty ? "Новое дело" : event.text)
                                .foregroundStyle(StudioTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            metadata(for: event)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(StudioTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudioTheme.categorySurfaceColor(event.category))
                        }.padding(.vertical, 8)
                    }.id(event.id)
                }.listRowBackground(StudioTheme.surface)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(StudioTheme.coral) }
        }
    }

    private func metadata(for event: DiaryEvent) -> Text {
        let status = event.completion == .notCompleted ? " · \(event.completion.title)" : ""
        return Text("\(event.category.title)\(status)")
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if draft.hasDeletedEvents {
                Button {
                    restoredEventID = draft.undoDeletion()
                } label: {
                    Label("Отменить удаление", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.mint)
                .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("review-undo-deletion")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    addButton
                    doneButton
                }
                VStack(spacing: 8) {
                    addButton
                    doneButton
                }
            }
        }.padding().background(StudioTheme.background)
    }

    private var addButton: some View {
        Button("Добавить дело") {
            draft.addEvent(DiaryEvent(recordingID: recording.id, sourceText: recording.transcript ?? "", text: ""))
        }.frame(maxWidth: .infinity, minHeight: 44)
    }

    private var doneButton: some View {
        Button("Готово") { save() }
            .buttonStyle(.borderedProminent).foregroundStyle(StudioTheme.background).frame(minHeight: 44)
    }

    private func mergeSources(fallback: String) -> [String] {
        guard let index = mergingIndex else { return [fallback] }
        return draft.events[(index - 1)...index].map(\.sourceText)
    }

    private func binding(for event: DiaryEvent) -> Binding<DiaryEvent> {
        Binding(
            get: { draft.events.first(where: { $0.id == event.id }) ?? event },
            set: { draft.updateEvent($0) }
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

    private func prepareMerge(_ id: UUID) {
        guard let index = draft.events.firstIndex(where: { $0.id == id }), index > 0 else { return }
        var proposal = draft.events[index - 1]
        let next = draft.events[index]
        proposal.text += ". " + next.text
        proposal.sourceText += ". " + next.sourceText
        if proposal.category != next.category { proposal.category = .unclassified }
        if next.completion == .notCompleted { proposal.completion = .notCompleted }
        draft.mergingEventID = id
        draft.mergeProposal = proposal
    }
}

private struct ReviewEventFields: View {
    @Binding var event: DiaryEvent

    var body: some View {
        TextField("Дело", text: $event.text, axis: .vertical)
            .accessibilityIdentifier("review-event-text")
        Picker("Категория", selection: $event.category) {
            ForEach(EventCategory.allCases) { Text($0.title).tag($0) }
        }
        Picker("Статус", selection: $event.completion) {
            ForEach(EventCompletion.allCases) { Text($0.title).tag($0) }
        }
    }
}

private struct EventMergeView: View {
    @Binding var event: DiaryEvent
    let sourceTexts: [String]
    let onConfirm: (DiaryEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Исходные фрагменты") {
                    ForEach(sourceTexts.indices, id: \.self) { index in
                        Text(sourceTexts[index])
                            .foregroundStyle(StudioTheme.secondary)
                            .accessibilityIdentifier("merge-source-\(index)")
                    }
                }.listRowBackground(StudioTheme.surface)
                Section {
                    ReviewEventFields(event: $event)
                } header: {
                    Text("Объединённое дело")
                } footer: {
                    Text("Проверьте категорию и статус объединённого дела.")
                }.listRowBackground(StudioTheme.surface)
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
