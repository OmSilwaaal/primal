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

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            isLoading = false
            return
        }

        let urlStr = "\(AppConstants.usdaBaseURL)/foods/search"
                   + "?query=\(encoded)"
                   + "&api_key=\(AppConstants.usdaAPIKey)"
                   + "&dataType=SR%20Legacy,Survey%20(FNDDS),Branded"
                   + "&pageSize=25"
                   + "&sortBy=dataType.keyword"
                   + "&sortOrder=asc"

        guard let url = URL(string: urlStr) else {
            errorMessage = "Invalid search URL"
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errorMessage = "API Error \(http.statusCode)"
                isLoading = false
                return
            }

            let decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            results = decoded.foods
        } catch is CancellationError {
            // Silently ignore
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        errorMessage = nil
        isLoading = false
    }
}
