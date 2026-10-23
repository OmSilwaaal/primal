import SwiftUI
import SwiftData
import PhotosUI

/// Logs one raw/carnivore item with species, cut, preparation, source and cold-chain details.
/// Nutrition comes from USDA FoodData Central (organ-specific entries), with offline reference values as fallback.
struct RawLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SourceBatch.purchaseDate, order: .reverse) private var batches: [SourceBatch]
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]

    @State private var species: RawSpecies = .beef
    @State private var category: CutCategory = .muscle
    @State private var organ: Organ = .liver
    @State private var fat: FatType = .suet
    @State private var prep: Prep = .raw
    @State private var ground = false
    @State private var grams = "200"
    @State private var itemName = ""
    @State private var rearing: Rearing = .unknown
    @State private var supplierName = ""
    @State private var batchId: UUID?
    @State private var thaw: ThawMethod = .none
    @State private var outMin = 0.0
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var saving = false
    @State private var showNewBatch = false

    private var gramsValue: Double { Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var detail: String { category == .organ ? organ.rawValue : category == .fat ? fat.rawValue : "" }
    private var batch: SourceBatch? { batches.first { $0.id == batchId } }
    private var matching: [SourceBatch] { batches.filter { $0.species == species.rawValue } }

    private var assessment: RiskAssessment {
        RiskEngine.assess(species: species, category: category, organ: detail, ground: ground && category == .muscle,
                          prep: prep, batch: batch, outOfFridgeMin: outMin, thaw: thaw)
    }

    var body: some View {
        RawScreen(title: "Log raw food") {
            RawCard(title: "What is it?") {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Species")
                    FlowLayout(spacing: 8) {
                        ForEach(RawSpecies.mainGroup) { s in
                            Chip(label: s.label, icon: s.icon, selected: s == species) { select(s) }
                        }
                    }
                    FieldLabel(text: "Wild game")
                    FlowLayout(spacing: 8) {
                        ForEach(RawSpecies.gameGroup) { s in
                            Chip(label: s.label, selected: s == species) { select(s) }
                        }
                    }
                    if species.categories.count > 1 {
                        FieldLabel(text: "Category")
                        FlowLayout(spacing: 8) {
                            ForEach(species.categories) { c in
                                Chip(label: c.label, selected: c == category) { withAnimation(.smooth(duration: 0.3)) { category = c } }
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                    }
                    if category == .organ {
                        FlowLayout(spacing: 8) {
                            ForEach(species.organs) { o in
                                Chip(label: o.label, selected: o == organ) { organ = o }
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                    } else if category == .fat {
                        FlowLayout(spacing: 8) {
                            ForEach(species.fats) { f in
                                Chip(label: f.label, selected: f == fat) { fat = f }
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                    } else {
                        RawField(title: "Cut or item (optional)", text: $itemName)
                        if species.canBeGround {
                            Toggle(isOn: $ground) {
                                Text("Ground / minced").font(.ui(size: 14, weight: .medium)).foregroundColor(.ncPrimary)
                            }.tint(.ncIndigo)
                            .transition(.opacity)
                        }
                    }
                }
            }

            RawCard(title: "Preparation") {
                VStack(alignment: .leading, spacing: 12) {
                    FlowLayout(spacing: 8) {
                        ForEach(species.preps) { p in
                            Chip(label: p.label, selected: p == prep) { prep = p }
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    RawField(title: "Weight (grams)", text: $grams, keyboard: .decimalPad)
                }
            }

            RawCard(title: "Source") {
                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(text: "Raised")
                    FlowLayout(spacing: 8) {
                        ForEach(species.rearings) { r in
                            Chip(label: r.label, selected: r == rearing) { rearing = r }
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    RawField(title: "Farm or brand", text: $supplierName)
                    if !suppliers.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suppliers) { s in Chip(label: s.name, selected: supplierName == s.name) { supplierName = s.name } }
                            }
                        }
                    }
                    FieldLabel(text: "Batch")
                    FlowLayout(spacing: 8) {
                        Chip(label: "None", selected: batchId == nil) { batchId = nil }
                        ForEach(matching.prefix(6)) { b in
                            Chip(label: b.label.isEmpty ? "Batch" : b.label, selected: batchId == b.id) {
                                batchId = b.id
                                if supplierName.isEmpty { supplierName = b.supplierName }
                                rearing = Rearing(rawValue: b.rearing) ?? rearing
                                ground = b.isGround
                            }
                        }
                        Button { showNewBatch = true } label: {
                            Label("New batch", systemImage: "plus").font(.ui(size: 14, weight: .medium))
                                .foregroundColor(.ncPrimary).padding(.horizontal, 14).frame(minHeight: 44)
                                .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        }.buttonStyle(.plain)
                    }
                }
            }

            RawCard(title: "Cold chain") {
                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(text: "Thawed")
                    FlowLayout(spacing: 8) {
                        ForEach(ThawMethod.allCases) { t in Chip(label: t.label, selected: t == thaw) { thaw = t } }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            FieldLabel(text: "Time out of fridge")
                            Text(outMin == 0 ? "Not noted" : "\(Int(outMin)) min").font(.ui(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                        }
                        Spacer()
                        Stepper("", value: $outMin, in: 0...720, step: 15).labelsHidden()
                    }
                }
            }

            RawCard(title: "Photo (optional)") {
                HStack(spacing: 12) {
                    if let photoData, let img = UIImage(data: photoData) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Add photo" : "Change photo", systemImage: "photo")
                            .font(.ui(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.vitalisSecondary)
                    .frame(maxWidth: 180)
                }
            }

            RiskSummaryCard(assessment: assessment)

            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.ncOnPrimary) }
                    Text(saving ? "Looking up nutrition…" : "Log it")
                }
            }
            .buttonStyle(.vitalis)
            .disabled(saving || gramsValue <= 0)
            .opacity(gramsValue <= 0 ? 0.5 : 1)

        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        .sheet(isPresented: $showNewBatch) {
            NavigationStack {
                BatchEditView(batch: nil, preset: species) { created in
                    batchId = created.id
                    supplierName = created.supplierName
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                let w: CGFloat = 800
                let scale = min(1, w / max(img.size.width, 1))
                let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                let small = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
                photoData = small.jpegData(compressionQuality: 0.6)
            }
        }
    }

    /// Switches species and drops any choice that doesn't exist for it; the option chips animate in and out.
    private func select(_ s: RawSpecies) {
        withAnimation(.smooth(duration: 0.3)) {
            species = s
            if batch?.species != s.rawValue { batchId = nil }
            if !s.categories.contains(category) { category = .muscle }
            if !s.organs.contains(organ), let first = s.organs.first { organ = first }
            if !s.fats.contains(fat), let first = s.fats.first { fat = first }
            if !s.rearings.contains(rearing) { rearing = .unknown }
            if !s.preps.contains(prep) { prep = .raw }
            if !s.canBeGround { ground = false }
        }
    }

    private var displayName: String {
        let base: String
        switch category {
        case .organ: base = "\(species.label) \(organ.rawValue)"
        case .fat: base = "\(species.label) \(fat.rawValue)"
        case .muscle:
            let item = itemName.trimmingCharacters(in: .whitespaces)
            base = item.isEmpty ? "\(ground ? "Ground " : "")\(species.label)" : "\(species.label) \(item)"
        }
        return "\(base) (\(prep.label.lowercased()))"
    }

    private var usdaQuery: String {
        let word: String
        switch species {
        case .poultry: word = "chicken"
        case .fish: word = itemName.isEmpty ? "salmon" : itemName
        case .shellfish: word = itemName.isEmpty ? "oyster" : itemName
        case .deer: word = "game meat deer"
        case .elk: word = "game meat elk"
        case .bear: word = "game meat bear"
        case .otherGame: word = "game meat"
        default: word = species.rawValue
        }
        switch category {
        case .organ: return "\(word) \(organ == .marrow ? "bone marrow" : organ.rawValue) raw"
        case .fat: return fat == .suet ? "\(word) fat raw suet" : "\(word) tallow"
        case .muscle: return "\(word) \(ground ? "ground" : itemName) raw"
        }
    }

    private func save() {
        saving = true
        Task {
            let g = gramsValue
            var entry: MealEntry
            if let usda = await bestUSDAMatch() {
                entry = MealEntry(from: usda, servingSize: g)
                if species == .fish || species == .shellfish { /* USDA already has omega-3 */ }
                entry.hemeIron = entry.iron * (species == .poultry || species == .fish ? 0.3 : 0.4)
                let ref = ReferenceNutrition.lookup(species: species, category: category, organ: detail, ground: ground)
                entry.purines = ref.purines * g / 100
                // Fill gaps USDA doesn't carry for some entries (e.g. K2, iodine, choline) from reference values.
                if entry.choline == 0 { entry.choline = ref.choline * g / 100 }
                if entry.iodine == 0 { entry.iodine = ref.iodine * g / 100 }
                if entry.vitaminK2 == 0 { entry.vitaminK2 = ref.vitaminK2 * g / 100 }
                if entry.omega3 == 0 { entry.omega3 = ref.omega3 * g / 100 }
                if entry.omega6 == 0 { entry.omega6 = ref.omega6 * g / 100 }
            } else {
                entry = ReferenceNutrition.entry(species: species, category: category, organ: detail, ground: ground, grams: g)
            }
            entry.foodName = displayName
            entry.species = species.rawValue
            entry.cutCategory = category.rawValue
            entry.organType = detail
            entry.prep = prep.rawValue
            entry.isGround = ground && category == .muscle
            entry.rearing = rearing.rawValue
            entry.supplierName = supplierName.trimmingCharacters(in: .whitespaces)
            entry.batchId = batchId
            entry.thawMethod = thaw.rawValue
            entry.outOfFridgeMin = outMin
            entry.photoData = photoData
            entry.riskScore = assessment.score
            if let b = batch, b.pricePerLb > 0 { entry.costUSD = g / 453.592 * b.pricePerLb }

            // Remember new suppliers
            let name = entry.supplierName
            if !name.isEmpty && !suppliers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                let s = Supplier(); s.name = name; context.insert(s)
            }
            Haptics.success()
            MealLogger.log(entry, in: context)
            saving = false
            dismiss()
        }
    }

    private func bestUSDAMatch() async -> FoodSearchResult? {
        guard let foods = try? await USDAService.fetch(query: usdaQuery, dataTypes: ["Foundation", "SR Legacy"], pageSize: 15),
              !foods.isEmpty else { return nil }
        let firstWord = usdaQuery.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let organWord = category == .organ ? (organ == .marrow ? "marrow" : organ.rawValue) : nil
        let scored = foods.filter { f in
            let d = f.description.lowercased()
            guard d.contains(firstWord) || species == .fish || species == .shellfish else { return false }
            if let organWord, !d.contains(organWord) { return false }
            return f.caloriesPer100g > 0
        }
        return scored.first(where: { $0.description.lowercased().contains("raw") }) ?? scored.first
    }
}

// MARK: - Risk summary
struct RiskSummaryCard: View {
    let assessment: RiskAssessment
    @State private var expanded = false

    var body: some View {
        RawCard(title: "Pathogen risk", trailing: assessment.level.label, trailingColor: assessment.level.color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(assessment.score))")
                        .font(.ui(size: 40, weight: .bold).monospacedDigit()).foregroundColor(.ncPrimary)
                        .contentTransition(.numericText())
                    Text("/ 100").font(.ui(size: 13)).foregroundColor(.ncSecondary)
                    Spacer()
                    if assessment.parasiteMitigated { Tag(text: "Parasite-mitigated", color: .ncGreen) }
                }
                BandGauge(value: assessment.score / 100, color: assessment.level.color)

                ForEach(assessment.hardWarnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.ncError).font(.ui(size: 13))
                        Text(w).font(.ui(size: 13, weight: .medium)).foregroundColor(.ncPrimary)
                    }
                    .padding(10)
                    .background(Color.ncError.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                ForEach(assessment.notes, id: \.self) { n in
                    Text("• \(n)").font(.ui(size: 13)).foregroundColor(.ncSecondary)
                }
                if !assessment.mitigationNote.isEmpty {
                    Text(assessment.mitigationNote).font(.ui(size: 13)).foregroundColor(.ncSecondary)
                }
                if !assessment.pathogens.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(assessment.pathogens) { p in Tag(text: "\(p.name) · \(p.windowLabel)", color: .ncOrange) }
                    }
                }
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Hide how it's scored" : "How it's scored")
                        Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .font(.ui(size: 13, weight: .semibold)).foregroundColor(.ncIndigo)
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(assessment.factors) { f in
                            HStack { Text(f.label); Spacer(); Text(f.detail).foregroundColor(.ncSecondary) }
                                .font(.ui(size: 13)).foregroundColor(.ncPrimary)
                        }
                    }
                }
                Text("Risk information, not a safety clearance. Lower risk never means safe.")
                    .font(.ui(size: 12)).foregroundColor(.ncSecondary)
            }
        }
    }
}
