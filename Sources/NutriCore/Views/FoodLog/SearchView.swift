import SwiftUI
import SwiftData

/// Add food, a sheet over Home (swipe down or the close button): a glass capsule search field, then matching foods
/// in one bento tile (kcal per 100 g), then the quick-log sheet.
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

            VStack(alignment: .leading, spacing: Bento.gap) {
                HStack(alignment: .center) {
                    Text("Add food").font(.bentoTitle).foregroundColor(Mono.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.bentoRound)
                        .accessibilityLabel("Close")
                }
                .padding(.top, 16)

                searchField

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Bento.gap) {
                        results
                    }
                    .padding(.bottom, 120)
                }
                .scrollDismissesKeyboard(.immediately)
                .glassLightFollowsScroll()
            }
            .padding(.horizontal, Bento.margin)

            if let food = selectedFood {
                QuickLogSheet(title: food.brandOwner ?? "Per serving", foodName: food.description, per100g: .init(food),
                              servingSize: $servingSize,
                              onLog: { log(food) },
                              onCancel: { withAnimation(.easeOut(duration: 0.2)) { selectedFood = nil } })
            }
        }
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.ui(size: 16, weight: .semibold)).foregroundColor(Mono.label)
                .accessibilityHidden(true)
            TextField("", text: $query)
                .font(.ui(size: 16)).foregroundColor(Mono.text)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .placeholder(when: query.isEmpty) {
                    Text("Search foods").font(.ui(size: 16)).foregroundColor(Mono.label)
                }
                .accessibilityLabel("Search foods")
                .onChange(of: query) { _, newValue in usdaService.search(newValue) }
            if usdaService.isLoading {
                ProgressView().tint(Mono.text)
            } else if !query.isEmpty {
                Button { query = ""; usdaService.clearResults() } label: {
                    Image(systemName: "xmark.circle.fill").font(.ui(size: 18)).foregroundColor(Mono.label)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18).padding(.trailing, 8)
        .frame(minHeight: 52)
        .glass(.clear, in: Capsule())
    }

    @ViewBuilder private var results: some View {
        if let error = usdaService.errorMessage {
            Text(error).font(.bentoBody).foregroundColor(Mono.label)
                .bentoTile()
        } else if !query.isEmpty && usdaService.results.isEmpty && !usdaService.isLoading {
            Text("No foods match \u{201C}\(query)\u{201D}.").font(.bentoBody).foregroundColor(Mono.label)
                .bentoTile()
        } else if !usdaService.results.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Per 100 g").font(.bentoLabel).foregroundColor(Mono.label)
                    .padding(.bottom, 4)
                ForEach(Array(usdaService.results.enumerated()), id: \.element.id) { i, food in
                    SearchResultRow(food: food) {
                        isSearchFocused = false
                        servingSize = food.defaultServingGrams
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedFood = food }
                    }
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                    }
                }
            }
            .bentoTile()
        }
    }

    private func log(_ food: FoodSearchResult) {
        let entry = MealEntry(from: food, servingSize: servingSize)
        MealLogger.log(entry, in: modelContext)
        ToastCenter.shared.show(QuickLogCard.loggedMessage(food.description, grams: servingSize), branded: true)
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
/// Food name, brand (when there is one), kcal per 100 g.
private struct SearchResultRow: View {
    let food: FoodSearchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.description.capitalized)
                        .font(.bentoBody).foregroundColor(Mono.text)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    if let brand = food.brandOwner, !brand.isEmpty {
                        Text(brand.capitalized).font(.ui(size: 12, weight: .medium)).foregroundColor(Mono.label).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Int(food.caloriesPer100g).formatted()).font(.ui(size: 17, weight: .semibold)).foregroundColor(Mono.text)
                    Text("kcal").font(.ui(size: 12)).foregroundColor(Mono.label)
                }
                .fixedSize()
            }
            .padding(.vertical, 11)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
