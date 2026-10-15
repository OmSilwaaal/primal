import Foundation

// MARK: - USDA FoodData Central API Service
@MainActor
final class USDAService: ObservableObject {
    static let shared = USDAService()
    private init() {}

    @Published var results: [FoodSearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func search(_ query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms debounce
            guard !Task.isCancelled else { return }

            await performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        guard AppConstants.usdaAPIKey != "YOUR_USDA_API_KEY_HERE" else {
            errorMessage = "⚠️ ADD YOUR USDA API KEY IN Constants.swift"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            let foods = try await Self.fetch(query: query,
                                             dataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"],
                                             pageSize: 25)
            guard !Task.isCancelled else { return }
            results = foods
        } catch is CancellationError {
            // Superseded by a newer query
        } catch let error as URLError where error.code == .cancelled {
            // Superseded by a newer query
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    /// Shared request builder. Uses URLComponents so queries containing `&`, `+` or `%` are encoded correctly.
    nonisolated static func fetch(query: String, dataTypes: [String], pageSize: Int) async throws -> [FoodSearchResult] {
        var components = URLComponents(string: "\(AppConstants.usdaBaseURL)/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "api_key", value: AppConstants.usdaAPIKey),
            URLQueryItem(name: "dataType", value: dataTypes.joined(separator: ",")),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "USDA", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: http.statusCode == 429 ? "Rate limit reached, try again shortly" : "API error \(http.statusCode)"])
        }
        return try JSONDecoder().decode(USDASearchResponse.self, from: data).foods
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        errorMessage = nil
        isLoading = false
    }
}
