import SwiftUI
import SwiftData

struct BatchEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]

    let batch: SourceBatch?
    var preset: RawSpecies = .beef
    var onCreate: ((SourceBatch) -> Void)? = nil

    @State private var label = ""
    @State private var species: RawSpecies = .beef
    @State private var category: CutCategory = .muscle
    @State private var organ: Organ = .liver
    @State private var ground = false
    @State private var supplierName = ""
    @State private var rearing: Rearing = .unknown
    @State private var lot = ""
    @State private var purchase = Date()
    @State private var hasPack = false
    @State private var pack = Date()
    @State private var hasSellBy = false
    @State private var sellBy = Date().addingTimeInterval(5 * 86400)
    @State private var weight = ""
    @State private var price = ""
    @State private var notes = ""
    @State private var frozen = false
    @State private var frozenAt = Date()
    @State private var temp = -18.0
    @State private var thawed = false
    @State private var thawedAt = Date()
    @State private var thawMethod: ThawMethod = .fridge
    @State private var loaded = false

    private var freezeResult: FreezeRules.Result? {
        guard frozen else { return nil }
        let end = thawed ? thawedAt : Date()
        return FreezeRules.evaluate(species: species, tempC: temp, hours: max(0, end.timeIntervalSince(frozenAt) / 3600))
    }

    var body: some View {
        RawScreen(title: batch == nil ? "New batch" : "Batch") {
            if let flag = batch?.recallFlag, !flag.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.ncError)
                    Text("Possible recall match — \(flag). Check the original notice before eating.")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ncError.opacity(0.14), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            RawCard(title: "Product") {
                VStack(alignment: .leading, spacing: 12) {
                    RawField(title: "Name", text: $label)
                    FlowLayout(spacing: 8) {
                        ForEach(RawSpecies.allCases) { s in Chip(label: s.label, selected: s == species) { species = s } }
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(CutCategory.allCases) { c in Chip(label: c.label, selected: c == category) { category = c } }
                    }
                    if category == .organ {
                        FlowLayout(spacing: 8) {
                            ForEach(Organ.allCases) { o in Chip(label: o.label, selected: o == organ) { organ = o } }
                        }
                    }
                    Toggle(isOn: $ground) { Text("Ground / minced").font(.system(size: 14, weight: .medium)).foregroundColor(.ncPrimary) }.tint(.ncIndigo)
                    FlowLayout(spacing: 8) {
                        ForEach(Rearing.allCases) { r in Chip(label: r.label, selected: r == rearing) { rearing = r } }
                    }
                }
            }

            RawCard(title: "Source & label") {
                VStack(alignment: .leading, spacing: 12) {
                    RawField(title: "Farm or brand", text: $supplierName)
                    if !suppliers.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) { ForEach(suppliers) { s in Chip(label: s.name, selected: supplierName == s.name) { supplierName = s.name } } }
                        }
                    }
                    RawField(title: "Lot number", text: $lot)
                    DatePicker("Purchased", selection: $purchase, displayedComponents: .date).foregroundColor(.ncPrimary)
                    Toggle("Pack date", isOn: $hasPack).tint(.ncIndigo).foregroundColor(.ncPrimary)
                    if hasPack { DatePicker("Packed", selection: $pack, displayedComponents: .date).foregroundColor(.ncPrimary) }
                    Toggle("Sell-by date", isOn: $hasSellBy).tint(.ncIndigo).foregroundColor(.ncPrimary)
                    if hasSellBy { DatePicker("Sell by", selection: $sellBy, displayedComponents: .date).foregroundColor(.ncPrimary) }
                }
            }

            RawCard(title: "Weight & price") {
                HStack(spacing: 12) {
                    RawField(title: "Total grams", text: $weight, keyboard: .decimalPad)
                    RawField(title: "Price per lb ($)", text: $price, keyboard: .decimalPad)
                }
            }

            RawCard(title: "Freezer log") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Frozen", isOn: $frozen.animation()).tint(.ncIndigo).foregroundColor(.ncPrimary)
                    if frozen {
                        DatePicker("Frozen on", selection: $frozenAt, displayedComponents: .date).foregroundColor(.ncPrimary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { FieldLabel(text: "Freezer temp"); Spacer(); Text("\(Int(temp)) °C").font(.system(size: 13, weight: .semibold)).foregroundColor(.ncPrimary) }
                            Slider(value: $temp, in: -40...(-5), step: 1).tint(.ncIndigo)
                        }
                        Toggle("Thawed", isOn: $thawed.animation()).tint(.ncIndigo).foregroundColor(.ncPrimary)
                        if thawed {
                            DatePicker("Thawed on", selection: $thawedAt).foregroundColor(.ncPrimary)
                            FlowLayout(spacing: 8) {
                                ForEach(ThawMethod.allCases.filter { $0 != .none }) { t in Chip(label: t.label, selected: t == thawMethod) { thawMethod = t } }
                            }
                        }
                        if let r = freezeResult {
                            HStack(alignment: .top, spacing: 8) {
                                if r.effective { Tag(text: "Parasite-mitigated", color: .ncGreen) }
                                Text(r.note).font(.system(size: 13)).foregroundColor(.ncSecondary)
                            }
                        }
                    }
                }
            }

            RawField(title: "Notes", text: $notes)

            Button("Save batch") { save() }.buttonStyle(.primal)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(label.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            if let batch {
                Button("Delete batch") { context.delete(batch); try? context.save(); dismiss() }
                    .buttonStyle(.primalSecondary).foregroundColor(.ncError)
            }
            Disclaimer()
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { if batch == nil { Button("Cancel") { dismiss() } } } }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let b = batch else { species = preset; return }
        label = b.label; species = b.speciesEnum
        category = CutCategory(rawValue: b.cutCategory) ?? .muscle
        organ = Organ(rawValue: b.organType) ?? .liver
        ground = b.isGround; supplierName = b.supplierName; rearing = Rearing(rawValue: b.rearing) ?? .unknown
        lot = b.lotNumber; purchase = b.purchaseDate
        if let p = b.packDate { hasPack = true; pack = p }
        if let s = b.sellByDate { hasSellBy = true; sellBy = s }
        weight = b.totalWeightG > 0 ? String(Int(b.totalWeightG)) : ""
        price = b.pricePerLb > 0 ? String(b.pricePerLb) : ""
        notes = b.notes
        if let f = b.frozenAt { frozen = true; frozenAt = f; temp = b.freezerTempC }
        if let t = b.thawedAt { thawed = true; thawedAt = t; thawMethod = ThawMethod(rawValue: b.thawMethod) ?? .fridge }
    }

    private func save() {
        let b = batch ?? SourceBatch()
        b.label = label.trimmingCharacters(in: .whitespaces)
        b.species = species.rawValue
        b.cutCategory = category.rawValue
        b.organType = category == .organ ? organ.rawValue : ""
        b.isGround = ground
        b.supplierName = supplierName.trimmingCharacters(in: .whitespaces)
        b.rearing = rearing.rawValue
        b.lotNumber = lot.trimmingCharacters(in: .whitespaces)
        b.purchaseDate = purchase
        b.packDate = hasPack ? pack : nil
        b.sellByDate = hasSellBy ? sellBy : nil
        b.totalWeightG = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
        b.pricePerLb = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
        b.notes = notes
        b.frozenAt = frozen ? frozenAt : nil
        b.freezerTempC = temp
        b.thawedAt = frozen && thawed ? thawedAt : nil
        b.thawMethod = frozen && thawed ? thawMethod.rawValue : ThawMethod.none.rawValue
        if batch == nil { context.insert(b) }
        let name = b.supplierName
        if !name.isEmpty && !suppliers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            let s = Supplier(); s.name = name; context.insert(s)
        }
        try? context.save()
        Haptics.success()
        onCreate?(b)
        dismiss()
    }
}

// MARK: - Safety hub: batches, freezer, recalls
struct SafetyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SourceBatch.purchaseDate, order: .reverse) private var batches: [SourceBatch]
    @Query(sort: \MealEntry.date, order: .reverse) private var meals: [MealEntry]
    @StateObject private var recalls = RecallService.shared
    @State private var showNew = false

    private var highRisk: [MealEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        return meals.filter { $0.date >= cutoff && $0.riskScore >= 40 }.prefix(5).map { $0 }
    }

    var body: some View {
        RawScreen(title: "Food safety") {
            RawCard(title: "Recall check", trailing: recalls.lastChecked.map { "Checked \($0.formatted(date: .omitted, time: .shortened))" }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Compares your logged lot numbers with USDA FSIS and openFDA recall data. No match found is not a clearance.")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    let flagged = batches.filter { !$0.recallFlag.isEmpty }
                    ForEach(flagged) { b in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.ncError)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.label).font(.system(size: 13, weight: .semibold)).foregroundColor(.ncPrimary)
                                Text(b.recallFlag).font(.system(size: 13)).foregroundColor(.ncSecondary)
                            }
                        }
                    }
                    Button {
                        Task { await recalls.check(batches: batches, context: context) }
                    } label: {
                        HStack { if recalls.isChecking { ProgressView().tint(.ncPrimary) }; Text(recalls.isChecking ? "Checking…" : "Check my lots") }
                    }
                    .buttonStyle(.primalSecondary)
                    if !recalls.fsisAvailable && recalls.lastChecked != nil {
                        Text("USDA FSIS feed unreachable right now; only openFDA was checked.").font(.system(size: 12)).foregroundColor(.ncOrange)
                    }
                }
            }

            if !highRisk.isEmpty {
                RawCard(title: "Recent higher-risk meals") {
                    VStack(spacing: 10) {
                        ForEach(highRisk) { m in
                            HStack {
                                Text(m.foodName).font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary).lineLimit(1)
                                Spacer()
                                Tag(text: "\(Int(m.riskScore))", color: m.riskScore >= 65 ? .ncError : .ncOrange)
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Batches & freezer").font(.system(size: 16, weight: .bold)).foregroundColor(.ncPrimary)
                Spacer()
                Button { showNew = true } label: { Label("New", systemImage: "plus").font(.system(size: 13, weight: .semibold)) }
                    .foregroundColor(.ncIndigo)
            }
            .padding(.top, 6)

            if batches.isEmpty {
                RawCard { Text("No batches yet. Add a pack to track its lot number, freezer history and cost.")
                    .font(.system(size: 13)).foregroundColor(.ncSecondary) }
            }
            ForEach(batches) { b in
                NavigationLink { BatchEditView(batch: b) } label: { BatchRow(batch: b, meals: meals) }.buttonStyle(.plain)
            }

            Disclaimer()
        }
        .sheet(isPresented: $showNew) { NavigationStack { BatchEditView(batch: nil) } }
        .task { await recalls.refreshFSIS() }
    }
}

private struct BatchRow: View {
    let batch: SourceBatch
    let meals: [MealEntry]
    private var used: Double { meals.filter { $0.batchId == batch.id }.reduce(0) { $0 + $1.servingSize } }
    private var assessment: RiskAssessment {
        RiskEngine.assess(species: batch.speciesEnum, category: CutCategory(rawValue: batch.cutCategory) ?? .muscle,
                          organ: batch.organType, ground: batch.isGround, prep: .raw, batch: batch,
                          outOfFridgeMin: 0, thaw: ThawMethod(rawValue: batch.thawMethod) ?? .none)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(batch.label.isEmpty ? "Batch" : batch.label).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                Spacer()
                if !batch.recallFlag.isEmpty { Tag(text: "Recall?", color: .ncError) }
                Tag(text: assessment.level.label, color: assessment.level.color)
            }
            HStack(spacing: 6) {
                Tag(text: batch.speciesEnum.label)
                if batch.isGround { Tag(text: "Ground") }
                if batch.isCurrentlyFrozen { Tag(text: "Frozen \(Int(batch.frozenHours / 24))d @ \(Int(batch.freezerTempC))°C", color: .ncSky) }
                if assessment.parasiteMitigated { Tag(text: "Parasite-mitigated", color: .ncGreen) }
            }
            HStack {
                if batch.totalWeightG > 0 {
                    Text("\(Int(max(0, batch.totalWeightG - used))) g left of \(Int(batch.totalWeightG)) g")
                }
                Spacer()
                if let s = batch.sellByDate { Text("Sell by \(s.formatted(date: .abbreviated, time: .omitted))") }
            }
            .font(.system(size: 13)).foregroundColor(.ncSecondary)
        }
        .padding(.vertical, 14)
        .glassCard(radius: 3)
    }
}
