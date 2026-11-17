import SwiftUI

struct EventReviewView: View {
    let recording: Recording
    @ObservedObject var service: RecordingService
    @State private var events: [DiaryEvent]
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(recording: Recording, service: RecordingService) {
        self.recording = recording
        self.service = service
        _events = State(initialValue: recording.events ?? EventExtractor.extract(recording.transcript ?? "", recordingID: recording.id))
    }

    var body: some View {
        List {
            ForEach($events) { $event in
                Section {
                    TextField("Дело", text: $event.text, axis: .vertical)
                    Picker("Категория", selection: $event.category) {
                        ForEach(EventCategory.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Статус", selection: $event.completion) {
                        ForEach(EventCompletion.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Время дела известно", isOn: Binding(
                        get: { event.occurredAt != nil },
                        set: { event.occurredAt = $0 ? recording.recordedAt : nil }
                    ))
                    if event.occurredAt != nil {
                        DatePicker("Когда", selection: Binding(
                            get: { event.occurredAt ?? recording.recordedAt },
                            set: { event.occurredAt = $0 }
                        ))
                    }
                    Toggle("Длительность известна", isOn: Binding(
                        get: { event.duration != nil },
                        set: { event.duration = $0 ? 60 : nil }
                    ))
                    if event.duration != nil {
                        TextField("Минуты", value: Binding(
                            get: { (event.duration ?? 60) / 60 },
                            set: { event.duration = max(0, $0) * 60 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                    }
                    DisclosureGroup("Исходный текст") { Text(event.sourceText) }
                    if events.first?.id != event.id {
                        Button("Объединить с предыдущим") { mergeWithPrevious(event.id) }
                    }
                }
            }
            .onDelete { events.remove(atOffsets: $0) }
            Section {
                Button("Добавить дело") {
                    events.append(DiaryEvent(recordingID: recording.id, sourceText: recording.transcript ?? "", text: ""))
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("События")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сохранить") {
                    do {
                        try service.saveEvents(recordingID: recording.id, events: events.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func mergeWithPrevious(_ id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }), index > 0 else { return }
        events[index - 1].text += ". " + events[index].text
        events[index - 1].sourceText += ". " + events[index].sourceText
        events[index - 1].duration = nil
        events[index - 1].occurredAt = nil
        events.remove(at: index)
    }
}
