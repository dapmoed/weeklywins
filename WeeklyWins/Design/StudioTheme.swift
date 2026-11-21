import SwiftUI

enum StudioTheme {
    static let background = Color(red: 17/255, green: 21/255, blue: 21/255)
    static let surface = Color(red: 29/255, green: 36/255, blue: 36/255)
    static let text = Color(red: 243/255, green: 246/255, blue: 244/255)
    static let secondary = Color(red: 181/255, green: 191/255, blue: 186/255)
    static let mint = Color(red: 182/255, green: 229/255, blue: 206/255)
    static let coral = Color(red: 1, green: 123/255, blue: 107/255)
    static let sand = Color(red: 233/255, green: 200/255, blue: 137/255)
    static let hobby = Color(red: 197/255, green: 163/255, blue: 255/255)
    static let neutralCategorySurface = Color(red: 48/255, green: 58/255, blue: 54/255)

    static func categoryColor(_ category: EventCategory) -> Color {
        switch category {
        case .unclassified: secondary
        case .work: mint
        case .home: sand
        case .hobby: hobby
        }
    }

}

struct CategoryFilter: View {
    @Binding var category: EventCategory?
    var compact = false
    private let categories: [EventCategory] = [.work, .home, .hobby, .unclassified]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if compact {
                ViewThatFits(in: .horizontal) {
                    pills(spacing: 6, padding: 12)
                        .fixedSize(horizontal: true, vertical: false)
                    categoryMenu
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    pills(spacing: 10, padding: 22)
                }
            }
            if let category {
                HStack {
                    Text(category.title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("Сбросить") { self.category = nil }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("reset-category-filter")
                }
                .font(.subheadline)
                .foregroundStyle(StudioTheme.secondary)
            }
        }
    }

    private func pills(spacing: CGFloat, padding: CGFloat) -> some View {
        HStack(spacing: spacing) {
            pill("Все", value: nil, padding: padding)
            ForEach(categories) { pill($0.title, value: $0, padding: padding) }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker("Категория", selection: $category) {
                Text("Все").tag(nil as EventCategory?)
                ForEach(categories) { option in
                    Text(option.title).tag(Optional(option))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(category?.title ?? "Все категории")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .foregroundStyle(StudioTheme.background)
            .background(StudioTheme.mint, in: RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityLabel("Категория")
        .accessibilityValue(category?.title ?? "Все")
    }

    private func pill(_ title: String, value: EventCategory?, padding: CGFloat) -> some View {
        Button { category = value } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, padding).frame(minHeight: 44)
                .foregroundStyle(category == value ? StudioTheme.background : StudioTheme.text)
                .background(category == value ? StudioTheme.mint : StudioTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == value ? .isSelected : [])
    }
}
