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
                StatTile(title: "Protein/g", value: protein > 0 ? String(format: "$%.3f", allCost / protein) : "—")
            }
            RawCard(title: "Daily spend", trailing: "30 days", index: "01") {
                if costed.isEmpty {
                    Text("Costs appear when you log food from a batch that has a price per lb.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                } else {
                    Chart(spend30) { BarMark(x: .value("Day", $0.day, unit: .day), y: .value("Spend", $0.amount)).foregroundStyle(Color.ncPrimary) }
                        .frame(height: 140)
                }
            }

            RawCard(title: "Suppliers", index: "02") {
                VStack(spacing: 0) {
                    if suppliers.isEmpty { Text("Suppliers are added when you log a farm or brand.").font(.serif(16)).italic().foregroundColor(.ncSecondary) }
                    ForEach(suppliers) { s in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(s.name).font(.serif(20)).foregroundColor(.ncPrimary)
                                Spacer()
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { n in
                                        Image(systemName: n <= s.rating ? "star.fill" : "star").font(.system(size: 14))
                                            .foregroundColor(n <= s.rating ? .ncOrange : .ncOutline)
                                            .onTapGesture { Haptics.selection(); s.rating = (s.rating == n ? 0 : n); try? context.save() }
                                    }
                                }
                            }
                            TextField("", text: Binding(get: { s.notes }, set: { s.notes = $0; try? context.save() }),
                                      prompt: Text("Add a note").italic().foregroundColor(.ncSecondary))
                                .font(.system(size: 14)).foregroundColor(.ncPrimary)
                            let sb = batches.filter { $0.supplierName == s.name }
                            if !sb.isEmpty { Text("\(sb.count) purchase\(sb.count == 1 ? "" : "s")").serifCaps(10).foregroundColor(.ncSecondary) }
                        }
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) { Hairline(opacity: 0.1) }
                    }
                }
            }

            RawCard(title: "Purchase history", index: "03") {
                VStack(spacing: 0) {
                    if batches.isEmpty { Text("No batches yet.").font(.serif(16)).italic().foregroundColor(.ncSecondary) }
                    ForEach(batches.prefix(15)) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.label.isEmpty ? b.speciesEnum.label : b.label).font(.system(size: 16, weight: .medium)).foregroundColor(.ncPrimary)
                                Text(b.purchaseDate.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 13)).foregroundColor(.ncSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if b.pricePerLb > 0 { Text(String(format: "$%.2f/lb", b.pricePerLb)).font(.metric(15)).foregroundColor(.ncPrimary) }
                                if b.pricePerLb > 0 && b.totalWeightG > 0 {
                                    Text(money(b.totalWeightG / 453.592 * b.pricePerLb)).font(.system(size: 12)).foregroundColor(.ncSecondary)
                                }
                            }
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { Hairline(opacity: 0.1) }
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
            RawCard(title: "Way of eating", index: "01") {
                VStack(spacing: 0) {
                    ForEach(DietMode.allCases) { m in
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy) { modeRaw = m.rawValue }
                        } label: {
                            VStack(spacing: 0) {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(m.label).font(.serif(22)).foregroundColor(.ncPrimary)
                                        Text(m.blurb).font(.system(size: 14)).foregroundColor(.ncSecondary)
                                        Text("Fat \(Int(m.fatRange.lowerBound))–\(Int(m.fatRange.upperBound))% · carbs under ~\(Int(m.carbCap)) g")
                                            .serifCaps(10).foregroundColor(.ncSecondary)
                                    }
                                    Spacer()
                                    Rectangle()
                                        .fill(modeRaw == m.rawValue ? Color.ncPrimary : Color.clear)
                                        .frame(width: 16, height: 16)
                                        .overlay(Rectangle().stroke(Color.ncPrimary.opacity(modeRaw == m.rawValue ? 1 : 0.4), lineWidth: 1))
                                        .padding(.top, 6)
                                }
                                .padding(.vertical, 18)
                                Hairline(opacity: 0.12)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(modeRaw == m.rawValue ? .isSelected : [])
                    }
                }
            }
            RawCard(title: "Start date", index: "02") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("I know when I started", isOn: Binding(get: { startInterval > 0 }, set: { startInterval = $0 ? Date().timeIntervalSince1970 : 0 }))
                        .tint(.ncIndigo).foregroundColor(.ncPrimary)
                    if startInterval > 0 {
                        DatePicker("Started", selection: Binding(get: { Date(timeIntervalSince1970: startInterval) }, set: { startInterval = $0.timeIntervalSince1970 }),
                                   in: ...Date(), displayedComponents: .date).foregroundColor(.ncPrimary)
                    }
                    Text("Used for the adaptation tracker and the before/after line on lab charts.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
            }
            Disclaimer(text: "Targets shift with your mode as general references. They are not personalised medical advice.")
        }
    }
}
