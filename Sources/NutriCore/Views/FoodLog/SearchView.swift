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
                VStack(alignment: .leading, spacing: 28) {
                    PageHeader(title: "Search", caption: usdaService.isLoading ? "Searching…" : "USDA FoodData Central")
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isSearchFocused ? .ncPrimary : .ncSecondary)
                        TextField("", text: $query)
                            .font(.system(size: 18)).foregroundColor(.ncPrimary)
                            .focused($isSearchFocused)
                            .placeholder(when: query.isEmpty) {
                                Text("Ribeye, liver, salmon…").font(.serif(18)).italic().foregroundColor(.ncSecondary)
                            }
                            .onChange(of: query) { _, newValue in usdaService.search(newValue) }
                        if !query.isEmpty {
                            Button { query = ""; usdaService.clearResults(); selectedFood = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(.ncSecondary)
                            }
                        }
                    }
                    .frame(height: 48)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.ncPrimary.opacity(isSearchFocused ? 0.9 : 0.3)).frame(height: 1)
                    }
                    .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 28)
                .padding(.bottom, 8)

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
                        LazyVStack(spacing: 0) {
                            if let error = usdaService.errorMessage {
                                Text(error)
                                    .font(.ncBodySm).foregroundColor(.ncError)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24).padding(.top, 60)
                            } else if usdaService.results.isEmpty && !query.isEmpty && !usdaService.isLoading {
                                VStack(spacing: 12) {
                                    Text("Nothing found").font(.serif(24)).foregroundColor(.ncPrimary)
                                    Text("No results for “\(query)”. Try a simpler name.")
                                        .font(.system(size: 14)).foregroundColor(.ncSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else if query.isEmpty {
                                VStack(spacing: 12) {
                                    Text("Every food, measured.").font(.serif(24)).foregroundColor(.ncPrimary)
                                    Text("Search the USDA FoodData Central database, including organ cuts.")
                                        .font(.system(size: 14)).foregroundColor(.ncSecondary).multilineTextAlignment(.center)
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

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(food.description.capitalized)
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.ncPrimary)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Text(food.brandOwner ?? food.dataType ?? "USDA").serifCaps(10).foregroundColor(.ncSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let kcal = food.foodNutrients.first(where: { $0.nutrientId == 1008 }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(kcal.value))").font(.metric(18)).foregroundColor(.ncPrimary)
                            Text("kcal / 100 g").font(.serif(11)).foregroundColor(.ncSecondary)
                        }
                    }
                }
                .padding(.vertical, 16)
                Hairline(opacity: 0.12)
            }
            .padding(.horizontal, Space.margin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
