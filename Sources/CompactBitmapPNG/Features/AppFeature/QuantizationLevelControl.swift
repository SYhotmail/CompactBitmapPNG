import SwiftUI

/// A segmented-style control where tapping the already-selected segment deselects it,
/// which SwiftUI's built-in `Picker(selection:)` doesn't support since it always requires
/// a non-nil selection.
struct QuantizationLevelControl: View {
    @Binding var selection: QuantizationLevel?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(QuantizationLevel.allCases) { level in
                let isSelected = selection == level

                Button {
                    selection = isSelected ? nil : level
                } label: {
                    Text(level.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.accentColor : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: 280)
    }
}
