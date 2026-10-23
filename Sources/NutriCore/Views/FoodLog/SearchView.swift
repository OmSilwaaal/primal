import SwiftUI
import SwiftData

/// Search sheet over Home (swipe down or Cancel to close): a glass search field, USDA results per 100 g,
/// then the quick-log card.
struct SearchView: View {
    var onClose: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @StateObject private var usdaService = USDAService.shared

    @State private var query: String = ""
    @State private var selectedFood: FoodSearchResult? = nil
    @State private var servingSize: Double = 100.0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Button("Cancel", action: close).buttonStyle(GlassButtonStyle(height: 48))

                    HStack(spacing: 6) {
                        TextField("", text: $query)
                            .font(.ui(size: 16)).foregroundColor(.ncPrimary)
                            .focused($isSearchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .placeholder(when: query.isEmpty) {
                                Text("Search USDA foods").font(.ui(size: 16)).foregroundColor(.ncSecondary)
                            }
                            .onChange(of: query) { _, newValue in usdaService.search(newValue) }
                        if !query.isEmpty {
                            Button { query = ""; usdaService.clearResults() } label: {
                                Text("CLEAR").font(.mono(11, .semibold)).foregroundColor(.ncPrimary)
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(Color.white.opacity(0.12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 18).padding(.trailing, 6)
                    .frame(minHeight: 48)
                    .glass(.clear)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)

                Text(usdaService.isLoading ? "Searching USDA…" : "Results · values per 100 g")
                    .monoLabel()
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Rule()
                        if let error = usdaService.errorMessage {
                            Text(error).font(.ui(size: 15)).foregroundColor(.ncEmber)
                                .padding(.vertical, 28)
                        } else if query.isEmpty {
                            Text("Search the USDA FoodData Central database, including organ cuts.")
                                .font(.ui(size: 15)).foregroundColor(.ncSecondary)
                                .padding(.vertical, 28)
                        } else if usdaService.results.isEmpty && !usdaService.isLoading {
                            Text("No results found").monoLabel(12)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(usdaService.results) { food in
                                SearchResultRow(food: food) {
                                    isSearchFocused = false
                                    servingSize = food.defaultServingGrams
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedFood = food }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            if let food = selectedFood {
                QuickLogSheet(title: "Selected food · USDA", foodName: food.description, per100g: .init(food),
                              servingSize: $servingSize,
                              onLog: { log(food) },
                              onCancel: { withAnimation(.easeOut(duration: 0.2)) { selectedFood = nil } })
            }
        }
        .onAppear { isSearchFocused = true }
    }

    private func log(_ food: FoodSearchResult) {
        let entry = MealEntry(from: food, servingSize: servingSize)
        MealLogger.log(entry, in: modelContext)
        ToastCenter.shared.show(QuickLogCard.loggedMessage(food.description, grams: servingSize))
        selectedFood = nil
        close()
    }

    private func close() {
        isSearchFocused = false
        query = ""
        usdaService.clearResults()
        onClose()
    }
}

// MARK: - Search Result Row
private struct SearchResultRow: View {
    let food: FoodSearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.description.capitalized)
                        .font(.ui(size: 15, weight: .bold)).foregroundColor(.ncPrimary)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    Text("\(food.brandOwner ?? food.dataType ?? "USDA") · per 100 g")
                        .font(.ui(size: 12)).foregroundColor(.ncSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(Int(food.caloriesPer100g)) kcal").font(.mono(13)).foregroundColor(.ncPrimary)
                    .fixedSize()
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
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
