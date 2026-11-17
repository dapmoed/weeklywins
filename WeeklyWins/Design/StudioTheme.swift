import SwiftUI

enum StudioTheme {
    static let background = Color(red: 17/255, green: 21/255, blue: 21/255)
    static let surface = Color(red: 29/255, green: 36/255, blue: 36/255)
    static let text = Color(red: 243/255, green: 246/255, blue: 244/255)
    static let secondary = Color(red: 181/255, green: 191/255, blue: 186/255)
    static let mint = Color(red: 182/255, green: 229/255, blue: 206/255)
    static let coral = Color(red: 1, green: 123/255, blue: 107/255)
    static let sand = Color(red: 233/255, green: 200/255, blue: 137/255)

    static func categoryColor(_ category: EventCategory) -> Color {
        category == .home ? sand : category == .work ? mint : secondary
    }

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "Без длительности" }
        let minutes = Int(max(0, seconds) / 60)
        if minutes >= 60 { return "\(minutes / 60) ч \(minutes % 60) мин" }
        return "\(minutes) мин"
    }
}

struct CategoryFilter: View {
    @Binding var category: EventCategory?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                pill("Все", value: nil)
                ForEach([EventCategory.work, .home, .unclassified]) { pill($0.title, value: $0) }
            }
        }
    }

    private func pill(_ title: String, value: EventCategory?) -> some View {
        Button { category = value } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 22).frame(minHeight: 44)
                .foregroundStyle(category == value ? StudioTheme.background : StudioTheme.text)
                .background(category == value ? StudioTheme.mint : StudioTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == value ? .isSelected : [])
    }
}
