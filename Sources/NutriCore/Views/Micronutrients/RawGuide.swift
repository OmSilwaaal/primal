import SwiftUI

/// The Raw card's guide: why raw meat is worth eating, how long people have eaten it, the water-soluble vitamins that
/// cooking takes from it, and how to eat it safely. General information, in line with the Health & Safety Policy —
/// no claims to treat or prevent anything.
enum RawGuide {
    /// The three lines on the card.
    static let facts: [(icon: String, title: String, line: String)] = [
        ("clock.arrow.circlepath", "Eaten for millions of years", "Long before fire, our ancestors ate their meat raw."),
        ("drop", "Keeps water-soluble vitamins", "B vitamins and vitamin C leach out and break down in cooking."),
        ("heart", "Nose to tail", "Raw liver and heart are among the most nutrient-dense foods."),
    ]

    struct Section: Identifiable {
        let title: String
        let paragraphs: [String]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Why raw", paragraphs: [
            "Meat is one of the most complete foods there is: complete protein, B12 that plants don't provide, iron and zinc in forms the body absorbs readily, and fats that carry vitamins A, D and K2.",
            "Eating it raw keeps everything it has. Heat changes proteins and fats, and cooking draws water — and what's dissolved in it — out into the pan.",
            "Organs go further still: liver carries vitamin A, B12, folate and copper, and heart carries CoQ10 and B vitamins, in amounts few other foods match.",
        ]),
        Section(title: "Water-soluble vitamins", paragraphs: [
            "Thiamin (B1), riboflavin (B2), niacin (B3), B6, folate (B9), B12 and vitamin C dissolve in water. The body stores little of most of them, so they need to come in steadily.",
            "Cooking loses part of them two ways: they run out with the juices, and heat breaks some of them down. USDA's nutrient retention tables show cooked meat keeping noticeably less thiamin, B6 and folate than raw, and longer, wetter cooking loses more.",
            "Raw meat loses none: every milligram is still there when you eat it. Raw organs even carry some vitamin C, which is how peoples of the far North stayed free of scurvy on little plant food.",
        ]),
        Section(title: "How our ancestors ate", paragraphs: [
            "Cut marks on animal bones show our ancestors eating meat at least 2.5 million years ago. Fire came much later: regular, everyday cooking appears in the record only in the last few hundred thousand years.",
            "For most of human history, then, meat was eaten fresh and raw — organs often first, as the most prized parts.",
            "Raw meat and fish are still eaten the world over: Inuit raw seal, whale and frozen fish; Ethiopian kitfo; Korean yukhoe; Japanese sashimi; Lebanese kibbeh nayyeh; Italian carpaccio and French steak tartare.",
        ]),
        Section(title: "Eating it safely", paragraphs: [
            "Raw meat and fish can carry bacteria and parasites. Choose very fresh meat from a source you trust, keep it cold, use clean boards and knives, and freeze fish and wild game first where that's advised.",
            "Raw animal foods aren't recommended during pregnancy, for young children or older adults, or with a weakened immune system. Talk to a doctor first if any of these apply.",
        ]),
    ]

    /// The water-soluble vitamins, with how much of each a raw meal gave (by `NutrientInfo.amount` ids).
    static let waterSoluble: [(id: String, name: String, unit: String)] = [
        ("b1", "Thiamin (B1)", "mg"), ("b2", "Riboflavin (B2)", "mg"), ("b3", "Niacin (B3)", "mg"),
        ("b6", "Vitamin B6", "mg"), ("fol", "Folate (B9)", "mcg"), ("b12", "Vitamin B12", "mcg"), ("vc", "Vitamin C", "mg"),
    ]
}

/// The card's face for Raw: three short facts, each with an icon.
struct RawFactsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(RawGuide.facts, id: \.title) { fact in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: fact.icon).font(.ui(size: 16, weight: .medium)).foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .liquidGlassPanel(in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.title).font(.ui(size: 16, weight: .semibold)).foregroundColor(.white)
                        Text(fact.line).font(.ui(size: 14)).foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Raw sheet: today's raw share and organ meat, the water-soluble vitamins raw food gave today, then the guide.
struct RawGuideSheet: View {
    let summary: DataGroupSummary
    let meals: [MealEntry]

    var body: some View {
        let raw = summary.items.first { $0.id == "raw" }
        let organ = summary.items.first { $0.id == "org" }
        let rawMeals = meals.filter(\.isRawFood)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    stat("Eaten raw", raw.map { $0.goal > 0 ? "\(Int(($0.current / $0.goal * 100).rounded()))%" : "—" } ?? "—",
                         raw.map { "\(Int($0.current)) of \(Int($0.goal)) g today" } ?? "")
                    stat("Organ meat", organ.map { "\(Int($0.current)) g" } ?? "0 g", "of about 50 g a day")
                }

                card {
                    Text("Water-soluble vitamins from raw food today").font(.ui(size: 17, weight: .semibold)).foregroundColor(.white)
                    if rawMeals.isEmpty {
                        Text("Log something raw — a steak, liver, egg yolks — to see the B vitamins and vitamin C it kept.")
                            .font(.ui(size: 15)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(RawGuide.waterSoluble, id: \.id) { v in
                            let amount = rawMeals.reduce(0) { $0 + NutrientInfo.amount(v.id, in: $1) }
                            HStack {
                                Text(v.name).font(.ui(size: 15)).foregroundColor(.white)
                                Spacer()
                                Text(amount > 0 ? "\(NutrientRow.dec(amount)) \(v.unit)" : "—")
                                    .font(.ui(size: 15, weight: .semibold)).foregroundColor(.white).monospacedDigit()
                            }
                            .frame(minHeight: 30)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                ForEach(RawGuide.sections) { section in
                    card {
                        Text(section.title).font(.ui(size: 19, weight: .bold)).foregroundColor(.white)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.paragraphs, id: \.self) { p in
                            Text(p).font(.ui(size: 16)).foregroundColor(.white.opacity(0.88)).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("General information, not medical advice. See the Health & Safety Policy in Settings.")
                    .font(.ui(size: 13)).foregroundColor(Mono.label).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 30)
        }
    }

    private func stat(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.ui(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.75))
            Text(value).font(.display(30)).foregroundColor(.white)
            Text(detail).font(.ui(size: 13)).foregroundColor(.white.opacity(0.7)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)) }
        .accessibilityElement(children: .combine)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.05)) }
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
    }
}
