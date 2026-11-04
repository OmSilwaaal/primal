import SwiftUI

/// A nutrient's short name (or a group and its score) as a capsule: a dark translucent fill with a light hairline,
/// white semibold text. Low ones are Ember-filled with a brighter Ember border. Solid fills under Reduce
/// Transparency. The Ember fill is kept at about half strength so white text stays above 4.5:1.
struct NutrientPill: View {
    let model: PillModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(model.text)
            .font(.ui(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .grained(0.25)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background {
                Capsule().fill(fill)
            }
            .overlay {
                Capsule().strokeBorder(model.isLow ? Color.ncEmber.opacity(0.95) : Color.white.opacity(0.24), lineWidth: 1)
            }
            .accessibilityLabel(model.isLow ? "\(model.text), low" : model.text)
    }

    private var fill: Color {
        if model.isLow { return reduceTransparency ? Color(hex: "#7A3B2C") : Color.ncEmber.opacity(0.5) }
        return reduceTransparency ? Color(hex: "#1C1F1C") : Color.black.opacity(0.3)
    }
}

#if DEBUG
#Preview("Pills") {
    HStack {
        NutrientPill(model: PillModel(id: "a", text: "Prot", isLow: false))
        NutrientPill(model: PillModel(id: "b", text: "D", isLow: true))
        NutrientPill(model: PillModel(id: "c", text: "Coming soon", isLow: false))
    }
    .padding()
    .background(Color(hex: "#0D1710"))
}
#endif
