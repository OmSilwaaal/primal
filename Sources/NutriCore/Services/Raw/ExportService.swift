import Foundation
import UIKit

/// Builds the doctor export: labs + diet history as CSV or a simple PDF.
enum ExportService {
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    static func csv(readings: [BiomarkerReading], meals: [MealEntry], dietStart: Date?) -> URL? {
        var lines = ["# Vitalis export — general information for discussion with a clinician, not medical advice"]
        if let dietStart { lines.append("# Diet start date,\(df.string(from: dietStart))") }
        lines.append("")
        lines.append("LABS AND MEASUREMENTS")
        lines.append("date,marker,value,unit,source")
        for r in readings.sorted(by: { $0.date < $1.date }) {
            guard let k = r.kindEnum else { continue }
            lines.append("\(df.string(from: r.date)),\(k.label),\(r.value),\(k.unit),\(r.source)")
        }
        lines.append("")
        lines.append("DIET LOG")
        lines.append("date,food,species,category,prep,grams,kcal,protein_g,fat_g,carbs_g,vitaminA_mcg,copper_mg,risk_score")
        for m in meals.sorted(by: { $0.date < $1.date }) {
            let name = m.foodName.replacingOccurrences(of: ",", with: " ")
            lines.append("\(df.string(from: m.date)),\(name),\(m.species),\(m.cutCategory),\(m.prep),\(Int(m.servingSize)),\(Int(m.calories)),\(Int(m.protein)),\(Int(m.totalFat)),\(Int(m.carbohydrates)),\(Int(m.vitaminA)),\(String(format: "%.1f", m.copper)),\(Int(m.riskScore))")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitalis-export.csv")
        do { try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    static func pdf(readings: [BiomarkerReading], meals: [MealEntry], dietStart: Date?) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
        let head: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]

        // Latest reading per marker, plus the first one for a before/after view.
        let byKind = Dictionary(grouping: readings.compactMap { r in r.kindEnum.map { ($0, r) } }, by: { $0.0 })
        var labLines: [String] = []
        for k in BiomarkerKind.allCases {
            guard let rs = byKind[k]?.map(\.1).sorted(by: { $0.date < $1.date }), let last = rs.last else { continue }
            let first = rs.first!
            let trend = rs.count > 1 ? "  (first \(fmt(first.value)) on \(shortDate(first.date)))" : ""
            labLines.append("\(k.label.padding(toLength: 20, withPad: " ", startingAt: 0)) \(fmt(last.value)) \(k.unit)  \(shortDate(last.date))\(trend)")
        }
        let recent = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let m30 = meals.filter { $0.date >= recent }
        let days = max(1, Set(m30.map { Calendar.current.startOfDay(for: $0.date) }).count)
        let rating = DietRater.rate(meals: meals, days: 30)
        let dietLines = [
            "Days with logged food (last 30): \(days)",
            "Average per logged day: \(Int(m30.totalCalories) / days) kcal, \(Int(m30.totalProtein) / days) g protein, \(Int(m30.totalFat) / days) g fat, \(Int(m30.totalCarbs) / days) g carbs",
            "Avg preformed vitamin A: \(Int(m30.totalVitaminA) / days) mcg RAE/day   Avg copper: \(String(format: "%.1f", m30.totalCopper / Double(days))) mg/day",
            "Diet position (30 days): \(rating.tier.title) — raw \(Int(rating.rawPct))%, animal \(Int(rating.animalPct))%, plant \(Int(rating.plantPct))%",
        ] + (dietStart.map { ["Diet start date: \(shortDate($0))"] } ?? [])

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            func draw(_ s: String, _ attrs: [NSAttributedString.Key: Any], gap: CGFloat = 14) {
                if y > 740 { ctx.beginPage(); y = 40 }
                (s as NSString).draw(in: CGRect(x: 40, y: y, width: 532, height: 60), withAttributes: attrs)
                y += gap
            }
            draw("Vitalis — labs and diet summary", title, gap: 28)
            draw("Generated \(shortDate(Date())). General information to discuss with a clinician; not medical advice.", body, gap: 24)
            draw("Labs and measurements (latest)", head, gap: 18)
            (labLines.isEmpty ? ["No readings logged."] : labLines).forEach { draw($0, body) }
            y += 12
            draw("Diet summary", head, gap: 18)
            dietLines.forEach { draw($0, body) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitalis-summary.pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }

    private static func fmt(_ v: Double) -> String { v >= 100 ? String(Int(v)) : String(format: "%.1f", v) }
    private static func shortDate(_ d: Date) -> String { let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d) }
}
