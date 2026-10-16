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
            Color.ncSurfaceContLowest.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── HUD Header ───────────────────────────────────────────────
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isSearchFocused ? .ncPrimary : .ncSecondary)
                            TextField("", text: $query)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.ncPrimary)
                                .focused($isSearchFocused)
                                .placeholder(when: query.isEmpty) {
                                    Text("QUERY FOOD DATABASE...")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .tracking(1)
                                        .foregroundColor(.ncSecondary)
                                }
                                .onChange(of: query) { _, newValue in usdaService.search(newValue) }
                            if !query.isEmpty {
                                Button { query = ""; usdaService.clearResults(); selectedFood = nil } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.ncSecondary)
                                        .font(.system(size: 14))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.ncSurfaceContHigh)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isSearchFocused ? Color.ncPrimary : Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                    }

                    HStack {
                        Text("USDA FOODDATA CENTRAL")
                            .font(.ncLabelMonoReg)
                            .tracking(1.5)
                            .foregroundColor(.ncSecondary)
                        Spacer()
                        if usdaService.isLoading {
                            Text("QUERYING...")
                                .font(.ncLabelMonoBold)
                                .tracking(1.5)
                                .foregroundColor(.ncPrimary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color.ncSurfaceContLowest)
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)

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
                                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundColor(.ncSecondary)
                                    Text("NO SIGNAL")
                                        .font(.ncLabelMonoBold).tracking(2).foregroundColor(.ncSecondary)
                                    Text("No results for \"\(query)\"")
                                        .font(.ncBodySm).foregroundColor(.ncSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else if query.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "viewfinder")
                                        .font(.system(size: 40, weight: .ultraLight))
                                        .foregroundColor(.ncSecondary.opacity(0.5))
                                    Text("BEGIN QUERY")
                                        .font(.ncLabelMonoBold).tracking(2).foregroundColor(.ncSecondary)
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
                        Text("FDCID: \(food.fdcId)")
                            .font(.ncLabelMonoReg)
                            .tracking(1)
                            .foregroundColor(.ncSecondary)
                        if let kcal = food.foodNutrients.first(where: { $0.nutrientId == 1008 }) {
                            Text("\(Int(kcal.value)) KCAL/100G")
                                .font(.ncLabelMonoBold)
                                .tracking(1)
                                .foregroundColor(.ncPrimary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.ncSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(pressed ? Color.ncSurfaceContHigh : Color.ncSurfaceCont)
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
