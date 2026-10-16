import Foundation
import SwiftData

struct RecallHit: Identifiable {
    let id = UUID()
    let source: String        // "USDA FSIS" | "openFDA"
    let title: String
    let reason: String
    let date: String
    let classification: String
}

/// Matches logged lot numbers against public recall data. A miss means "no match found",
/// never that a product is clear.
@MainActor
final class RecallService: ObservableObject {
    static let shared = RecallService()
    private init() {}

    @Published var isChecking = false
    @Published var recentFSIS: [RecallHit] = []
    @Published var fsisAvailable = true
    @Published var lastChecked: Date?

    private var fsisRaw: [[String: Any]] = []

    func refreshFSIS() async {
        guard let url = URL(string: "https://www.fsis.usda.gov/fsis/api/recall/v/1") else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Primal", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                fsisAvailable = false; return
            }
            fsisRaw = json
            fsisAvailable = true
            recentFSIS = json.prefix(15).map(Self.hit(fromFSIS:))
        } catch {
            fsisAvailable = false
        }
    }

    /// Checks every batch that has a lot number. Sets `recallFlag` on matches and clears it otherwise.
    func check(batches: [SourceBatch], context: ModelContext) async {
        isChecking = true
        defer { isChecking = false; lastChecked = Date() }
        if fsisRaw.isEmpty { await refreshFSIS() }
        for b in batches {
            let lot = b.lotNumber.trimmingCharacters(in: .whitespaces)
            guard lot.count >= 3 else { b.recallFlag = ""; continue }
            let hits = await matches(lot: lot)
            b.recallFlag = hits.first.map { "\($0.source): \($0.title)" } ?? ""
        }
        try? context.save()
    }

    func matches(lot: String) async -> [RecallHit] {
        var hits: [RecallHit] = []
        let needle = lot.lowercased()
        for entry in fsisRaw where Self.flatten(entry).lowercased().contains(needle) {
            hits.append(Self.hit(fromFSIS: entry))
        }
        hits.append(contentsOf: await openFDA(lot: lot))
        return hits
    }

    private func openFDA(lot: String) async -> [RecallHit] {
        var c = URLComponents(string: "https://api.fda.gov/food/enforcement.json")!
        c.queryItems = [URLQueryItem(name: "search", value: "code_info:\"\(lot)\""), URLQueryItem(name: "limit", value: "5")]
        guard let url = c.url, let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.map {
            RecallHit(source: "openFDA",
                      title: ($0["product_description"] as? String).map { String($0.prefix(90)) } ?? "FDA enforcement report",
                      reason: $0["reason_for_recall"] as? String ?? "",
                      date: $0["recall_initiation_date"] as? String ?? "",
                      classification: $0["classification"] as? String ?? "")
        }
    }

    // MARK: Helpers
    private static func flatten(_ any: Any) -> String {
        switch any {
        case let s as String: return s
        case let d as [String: Any]: return d.values.map(flatten).joined(separator: " ")
        case let a as [Any]: return a.map(flatten).joined(separator: " ")
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    private static func hit(fromFSIS d: [String: Any]) -> RecallHit {
        func first(_ keys: [String]) -> String {
            for k in keys { if let s = d[k] as? String, !s.isEmpty { return strip(s) } }
            return ""
        }
        return RecallHit(source: "USDA FSIS",
                         title: first(["field_title", "title"]),
                         reason: first(["field_summary", "field_recall_reason"]),
                         date: first(["field_recall_date", "field_recall_date_value"]),
                         classification: first(["field_recall_classification"]))
    }

    private static func strip(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
