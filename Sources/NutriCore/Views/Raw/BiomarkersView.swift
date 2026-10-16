import SwiftUI
import SwiftData
import Charts

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct BiomarkersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BiomarkerReading.date, order: .reverse) private var readings: [BiomarkerReading]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]
    @AppStorage(RawSettings.startKey) private var startInterval = 0.0
    @State private var showAdd = false
    @State private var importing = false
    @State private var importMsg: String?
    @State private var shareURL: URL?

    private var dietStart: Date? { startInterval > 0 ? Date(timeIntervalSince1970: startInterval) : nil }

    var body: some View {
        RawScreen(title: "Biomarkers") {
            HStack(spacing: 10) {
                Button { showAdd = true } label: { Label("Add reading", systemImage: "plus") }.buttonStyle(.primal)
                Button { Task { await importHealth() } } label: {
                    HStack { if importing { ProgressView().tint(.ncPrimary) }; Label("Health", systemImage: "heart.text.square") }
                }.buttonStyle(.primalSecondary).frame(maxWidth: 130)
            }
            if let importMsg { Text(importMsg).font(.system(size: 12)).foregroundColor(.ncSecondary) }

            ForEach(BiomarkerGroup.allCases) { g in
                RawCard(title: g.label) {
                    VStack(spacing: 4) {
                        ForEach(BiomarkerKind.allCases.filter { $0.group == g }) { k in
                            NavigationLink { BiomarkerDetailView(kind: k) } label: { BiomarkerRow(kind: k, latest: readings.first { $0.kind == k.rawValue }) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            RawCard(title: "Doctor export") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Labs and diet history in one file to share with your clinician.").font(.system(size: 12)).foregroundColor(.ncSecondary)
                    HStack(spacing: 10) {
                        Button("CSV") { shareURL = ExportService.csv(readings: readings, meals: meals, dietStart: dietStart) }
                            .buttonStyle(.primalSecondary)
                        Button("PDF summary") { shareURL = ExportService.pdf(readings: readings, meals: meals, dietStart: dietStart) }
                            .buttonStyle(.primalSecondary)
                    }
                }
            }
            Disclaimer(text: "Reference ranges are typical lab-report intervals shown for context, not a diagnosis. Discuss results with a clinician.")
        }
        .sheet(isPresented: $showAdd) { NavigationStack { AddReadingView(kind: nil) } }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
    }

    private func importHealth() async {
        importing = true; importMsg = nil
        if !HealthKitManager.shared.isAuthorized { try? await HealthKitManager.shared.requestAuthorization() }
        let imported = await HealthKitManager.shared.importBiomarkers()
        var added = 0
        let cal = Calendar.current
        for i in imported {
            let exists = readings.contains { $0.kind == i.kind.rawValue && cal.isDate($0.date, inSameDayAs: i.date) && $0.source == "health" }
            if exists { continue }
            let r = BiomarkerReading(); r.kind = i.kind.rawValue; r.date = i.date; r.value = i.value; r.source = "health"
            context.insert(r); added += 1
        }
        try? context.save()
        importMsg = added > 0 ? "Imported \(added) reading(s) from Health." : "Nothing new to import from Health."
        importing = false
    }
}

private struct BiomarkerRow: View {
    let kind: BiomarkerKind
    let latest: BiomarkerReading?
    var body: some View {
        HStack {
            Text(kind.label).font(.system(size: 14, weight: .medium)).foregroundColor(.ncPrimary)
            Spacer()
            if let latest {
                let inRange = kind.reference?.contains(latest.value)
                Text("\(fmt(latest.value)) \(kind.unit)").font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(inRange == false ? .ncOrange : .ncPrimary)
            } else {
                Text("—").foregroundColor(.ncSecondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundColor(.ncOutline)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
private func fmt(_ v: Double) -> String { v >= 100 ? String(Int(v.rounded())) : String(format: "%.1f", v) }

struct AddReadingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State var kind: BiomarkerKind?
    @State private var value = ""
    @State private var date = Date()

    var body: some View {
        RawScreen(title: "Add reading") {
            RawCard {
                VStack(alignment: .leading, spacing: 12) {
                    FieldLabel(text: "Marker")
                    Menu {
                        ForEach(BiomarkerGroup.allCases) { g in
                            Menu(g.label) {
                                ForEach(BiomarkerKind.allCases.filter { $0.group == g }) { k in Button(k.label) { kind = k } }
                            }
                        }
                    } label: {
                        HStack { Text(kind?.label ?? "Choose…").foregroundColor(.ncPrimary); Spacer(); Image(systemName: "chevron.up.chevron.down").foregroundColor(.ncSecondary) }
                            .padding(.horizontal, 12).frame(height: 44)
                            .background(Color.ncSurfaceContHigh, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    RawField(title: "Value\(kind.map { " (\($0.unit))" } ?? "")", text: $value, keyboard: .decimalPad)
                    DatePicker("Date", selection: $date, in: ...Date()).foregroundColor(.ncPrimary)
                }
            }
            Button("Save") {
                guard let kind, let v = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
                let r = BiomarkerReading(); r.kind = kind.rawValue; r.value = v; r.date = date
                context.insert(r); try? context.save(); Haptics.success(); dismiss()
            }
            .buttonStyle(.primal)
            .disabled(kind == nil || Double(value.replacingOccurrences(of: ",", with: ".")) == nil)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
    }
}

struct BiomarkerDetailView: View {
    let kind: BiomarkerKind
    @Environment(\.modelContext) private var context
    @Query(sort: \BiomarkerReading.date) private var all: [BiomarkerReading]
    @AppStorage(RawSettings.startKey) private var startInterval = 0.0
    @State private var showAdd = false

    private var rows: [BiomarkerReading] { all.filter { $0.kind == kind.rawValue } }
    private var start: Date? { startInterval > 0 ? Date(timeIntervalSince1970: startInterval) : nil }

    var body: some View {
        RawScreen(title: kind.label) {
            RawCard(title: "Trend", trailing: kind.unit) {
                if rows.count < 2 {
                    Text(rows.isEmpty ? "No readings yet." : "Add another reading to see a trend.").font(.system(size: 13)).foregroundColor(.ncSecondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                } else {
                    Chart {
                        if let ref = kind.reference {
                            RectangleMark(yStart: .value("Low", ref.lowerBound), yEnd: .value("High", ref.upperBound))
                                .foregroundStyle(Color.ncGreen.opacity(0.10))
                        }
                        if let start {
                            RuleMark(x: .value("Diet start", start))
                                .foregroundStyle(Color.ncIndigo)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Diet start").font(.system(size: 10, weight: .semibold)).foregroundColor(.ncIndigo)
                                }
                        }
                        ForEach(rows) { r in
                            LineMark(x: .value("Date", r.date), y: .value(kind.label, r.value)).foregroundStyle(Color.ncPrimary)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", r.date), y: .value(kind.label, r.value)).foregroundStyle(Color.ncPrimary)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    if start != nil { Text("Dashed line marks when you started this diet.").font(.system(size: 11)).foregroundColor(.ncSecondary) }
                }
            }
            if let ref = kind.reference {
                Text("Typical lab reference: \(fmt(ref.lowerBound))–\(fmt(ref.upperBound)) \(kind.unit)").font(.system(size: 12)).foregroundColor(.ncSecondary)
            }
            RawCard(title: "Readings") {
                VStack(spacing: 8) {
                    ForEach(rows.reversed()) { r in
                        HStack {
                            Text(r.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 13)).foregroundColor(.ncSecondary)
                            if r.source == "health" { Tag(text: "Health") }
                            Spacer()
                            Text("\(fmt(r.value)) \(kind.unit)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundColor(.ncPrimary)
                            Button { context.delete(r); try? context.save() } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.ncSecondary) }
                        }
                    }
                    if rows.isEmpty { Text("Nothing logged.").font(.system(size: 13)).foregroundColor(.ncSecondary) }
                }
            }
            Button { showAdd = true } label: { Label("Add reading", systemImage: "plus") }.buttonStyle(.primal)
        }
        .sheet(isPresented: $showAdd) { NavigationStack { AddReadingView(kind: kind) } }
    }
}
