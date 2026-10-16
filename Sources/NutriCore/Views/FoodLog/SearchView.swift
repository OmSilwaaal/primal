import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var usdaService = USDAService.shared

    @State private var query: String = ""
    @State private var selectedFood: FoodSearchResult? = nil
    @State private var servingSize: Double = 100.0
    @State private var loggedToast: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 0) {
                // ── Header ───────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(title: "Search", caption: usdaService.isLoading ? "Searching…" : "USDA FoodData Central")
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isSearchFocused ? .ncPrimary : .ncSecondary)
                        TextField("", text: $query)
                            .font(.system(size: 15)).foregroundColor(.ncPrimary)
                            .focused($isSearchFocused)
                            .placeholder(when: query.isEmpty) {
                                Text("Search foods").font(.system(size: 15)).foregroundColor(.ncSecondary)
                            }
                            .onChange(of: query) { _, newValue in usdaService.search(newValue) }
                        if !query.isEmpty {
                            Button { query = ""; usdaService.clearResults(); selectedFood = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.ncSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 46)
                    .background(Color.ncSurfaceContLowest.opacity(0.8))
                    .overlay(Rectangle().stroke(isSearchFocused ? Color.ncPrimary : Color.ncPrimary.opacity(0.18), lineWidth: 1))
                    .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // ── Results ──────────────────────────────────────────────────
                if let selected = selectedFood {
                    QuickLogCard(
                        title: "USDA ID: \(selected.fdcId)",
                        foodName: selected.description,
                        servingSize: $servingSize
                    ) {
                        MealLogger.log(MealEntry(from: selected, servingSize: servingSize), in: modelContext)
                        isSearchFocused = false
                        selectedFood = nil
                        query = ""
                        usdaService.clearResults()
                        withAnimation { loggedToast = "Added to today's log" }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            withAnimation { loggedToast = nil }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 1) {
                            if let error = usdaService.errorMessage {
                                Text(error)
                                    .font(.ncBodySm).foregroundColor(.ncError)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24).padding(.top, 60)
                            } else if usdaService.results.isEmpty && !query.isEmpty && !usdaService.isLoading {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundColor(.ncSecondary)
                                    Text("No results")
                                        .spacedCaps(12, tracking: 2.4).foregroundColor(.ncSecondary)
                                    Text("No results for \"\(query)\"")
                                        .font(.ncBodySm).foregroundColor(.ncSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else if query.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "leaf")
                                        .font(.system(size: 40, weight: .ultraLight))
                                        .foregroundColor(.ncSecondary.opacity(0.5))
                                    Text("Start typing")
                                        .spacedCaps(12, tracking: 2.4).foregroundColor(.ncSecondary)
                                    Text("Search USDA FoodData Central")
                                        .font(.ncBodySm).foregroundColor(.ncSecondary.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else {
                                ForEach(usdaService.results) { food in
                                    SearchResultRow(food: food) {
                                        isSearchFocused = false
                                        servingSize = food.defaultServingGrams
                                        selectedFood = food
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            if let toast = loggedToast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.ncSurfaceContHighest, in: Rectangle())
                    .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Search Result Row
private struct SearchResultRow: View {
    let food: FoodSearchResult
    let onTap: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.description.capitalized)
                        .font(.ncBodySm)
                        .fontWeight(.medium)
                        .foregroundColor(.ncPrimary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Text(food.dataType ?? "USDA")
                            .spacedCaps(11, tracking: 1.2)
                            .foregroundColor(.ncSecondary)
                        if let kcal = food.foodNutrients.first(where: { $0.nutrientId == 1008 }) {
                            Text("\(Int(kcal.value)) kcal / 100 g")
                                .spacedCaps(11, tracking: 1)
                                .foregroundColor(.ncPrimary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.ncSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.ncSurfaceContLowest.opacity(0.6))
            .overlay(Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(PlainButtonStyle())
        .smoothButton()
    }
}

// MARK: - View extension for placeholder
extension View {
    func placeholder<Content: View>(when shouldShow: Bool, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow { placeholder() }
            self
        }
    }
}
