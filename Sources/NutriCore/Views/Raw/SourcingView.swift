import SwiftUI
import SwiftData
import Charts

struct SourcingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @Query(sort: \SourceBatch.purchaseDate, order: .reverse) private var batches: [SourceBatch]
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]

    private struct DaySpend: Identifiable { let id = UUID(); let day: Date; let amount: Double }

    private var costed: [MealEntry] { meals.filter { $0.costUSD > 0 } }
    private var spend30: [DaySpend] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date())) ?? Date()
        let g = Dictionary(grouping: costed.filter { $0.date >= start }) { cal.startOfDay(for: $0.date) }
        return (0..<30).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return DaySpend(day: d, amount: g[d]?.totalCost ?? 0)
        }
    }

    var body: some View {
        let month = spend30.reduce(0) { $0 + $1.amount }
        let week = spend30.suffix(7).reduce(0) { $0 + $1.amount }
        let protein = costed.reduce(0) { $0 + $1.protein }
        let allCost = costed.totalCost
        RawScreen(title: "Sourcing & cost") {
            HStack(spacing: 8) {
                StatTile(title: "7 days", value: money(week))
                StatTile(title: "30 days", value: money(month))
                StatTile(title: "Per g protein", value: protein > 0 ? String(format: "$%.3f", allCost / protein) : "—")
            }
            RawCard(title: "Daily spend", trailing: "30 days") {
                if costed.isEmpty {
                    Text("Costs appear when you log food from a batch that has a price per lb.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                } else {
                    Chart(spend30) { BarMark(x: .value("Day", $0.day, unit: .day), y: .value("Spend", $0.amount)).foregroundStyle(Color.ncPrimary) }
                        .frame(height: 140)
                }
            }

            RawCard(title: "Suppliers") {
                VStack(spacing: 12) {
                    if suppliers.isEmpty { Text("Suppliers are added when you log a farm or brand.").font(.system(size: 13)).foregroundColor(.ncSecondary) }
                    ForEach(suppliers) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(s.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                                Spacer()
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { n in
                                        Image(systemName: n <= s.rating ? "star.fill" : "star").font(.system(size: 14))
                                            .foregroundColor(n <= s.rating ? .ncOrange : .ncOutline)
                                            .onTapGesture { Haptics.selection(); s.rating = (s.rating == n ? 0 : n); try? context.save() }
                                    }
                                }
                            }
                            TextField("Notes", text: Binding(get: { s.notes }, set: { s.notes = $0; try? context.save() }))
                                .font(.system(size: 12)).foregroundColor(.ncSecondary)
                            let sb = batches.filter { $0.supplierName == s.name }
                            if !sb.isEmpty { Text("\(sb.count) purchase(s)").font(.system(size: 11)).foregroundColor(.ncSecondary) }
                        }
                    }
                }
            }

            RawCard(title: "Purchase history") {
                VStack(spacing: 10) {
                    if batches.isEmpty { Text("No batches yet.").font(.system(size: 13)).foregroundColor(.ncSecondary) }
                    ForEach(batches.prefix(15)) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.label.isEmpty ? b.speciesEnum.label : b.label).font(.system(size: 13, weight: .medium)).foregroundColor(.ncPrimary)
                                Text(b.purchaseDate.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundColor(.ncSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if b.pricePerLb > 0 { Text(String(format: "$%.2f/lb", b.pricePerLb)).font(.system(size: 13, weight: .semibold)).foregroundColor(.ncPrimary) }
                                if b.pricePerLb > 0 && b.totalWeightG > 0 {
                                    Text(money(b.totalWeightG / 453.592 * b.pricePerLb)).font(.system(size: 11)).foregroundColor(.ncSecondary)
                                }
                            }
                        }
                    }
                }
            }

            NavigationLink { PlacesMapView() } label: {
                NavRow(icon: "map", title: "Find butchers & farms", detail: "Nearby sources on the map")
            }.buttonStyle(.plain)
        }
    }
    private func money(_ v: Double) -> String { String(format: "$%.2f", v) }
}

struct DietModeView: View {
    @AppStorage(RawSettings.modeKey) private var modeRaw = DietMode.rawCarnivore.rawValue
    @AppStorage(RawSettings.startKey) private var startInterval = 0.0

    var body: some View {
        RawScreen(title: "Diet mode") {
            ForEach(DietMode.allCases) { m in
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { modeRaw = m.rawValue }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: modeRaw == m.rawValue ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(modeRaw == m.rawValue ? .ncPrimary : .ncOutline).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.label).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                            Text(m.blurb).font(.system(size: 12)).foregroundColor(.ncSecondary)
                            Text("Fat \(Int(m.fatRange.lowerBound))–\(Int(m.fatRange.upperBound))% of calories · carbs under ~\(Int(m.carbCap)) g")
                                .font(.system(size: 11)).foregroundColor(.ncSecondary)
                        }
                        Spacer()
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: 3)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(modeRaw == m.rawValue ? Color.ncPrimary.opacity(0.6) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            RawCard(title: "Start date") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("I know when I started", isOn: Binding(get: { startInterval > 0 }, set: { startInterval = $0 ? Date().timeIntervalSince1970 : 0 }))
                        .tint(.ncIndigo).foregroundColor(.ncPrimary)
                    if startInterval > 0 {
                        DatePicker("Started", selection: Binding(get: { Date(timeIntervalSince1970: startInterval) }, set: { startInterval = $0.timeIntervalSince1970 }),
                                   in: ...Date(), displayedComponents: .date).foregroundColor(.ncPrimary)
                    }
                    Text("Used for the adaptation tracker and the before/after line on lab charts.").font(.system(size: 12)).foregroundColor(.ncSecondary)
                }
            }
            Disclaimer(text: "Targets shift with your mode as general references. They are not personalised medical advice.")
        }
    }
}
