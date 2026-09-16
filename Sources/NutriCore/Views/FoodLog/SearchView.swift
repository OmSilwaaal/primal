import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var usdaService = USDAService.shared
    
    @State private var query: String = ""
    @State private var selectedFood: FoodSearchResult? = nil
    @State private var servingSize: Double = 100.0
    
    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Bar & Search Input
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.ncPrimary)
                    }
                    
                    TextField("Search foods...", text: $query)
                        .font(.system(size: 16))
                        .foregroundColor(.ncPrimary)
                        .padding(12)
                        .background(Color.ncSurface2)
                        .cornerRadius(12)
                        .onChange(of: query) { _, newValue in
                            usdaService.search(newValue)
                        }
                    
                    if !query.isEmpty {
                        Button(action: {
                            query = ""
                            usdaService.clearResults()
                            selectedFood = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.ncSecondary)
                        }
                    }
                }
                .padding()
                .background(Color.ncSurface)
                
                // Results List
                if usdaService.isLoading {
                    Spacer()
                    ProgressView().tint(.ncPrimary)
                    Text("SEARCHING USDA...")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.ncSecondary)
                        .padding(.top, 12)
                    Spacer()
                } else if usdaService.results.isEmpty && !query.isEmpty {
                    Spacer()
                    Text("NO RESULTS FOUND")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.ncSecondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(usdaService.results, id: \.fdcId) { food in
                                FoodResultRow(food: food)
                                    .onTapGesture {
                                        withAnimation(.spring()) {
                                            selectedFood = food
                                            servingSize = 100.0
                                        }
                                    }
                            }
                        }
                        .padding()
                        // Add extra padding at bottom so results aren't hidden behind the Quick Log card
                        .padding(.bottom, selectedFood != nil ? 220 : 0)
                    }
                }
            }
            
            // Quick Log Card Overlay
            if let food = selectedFood {
                VStack {
                    Spacer()
                    QuickLogCard(
                        title: "SELECTED FOOD",
                        foodName: food.description,
                        servingSize: $servingSize
                    ) {
                        let entry = MealEntry(from: food, servingSize: servingSize)
                        modelContext.insert(entry)
                        
                        // Briefly show a success state or just dismiss
                        selectedFood = nil
                        query = ""
                        usdaService.clearResults()
                        dismiss()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationBarHidden(true)
        .onDisappear {
            usdaService.clearResults()
        }
    }
}

// MARK: - Result Row
struct FoodResultRow: View {
    let food: FoodSearchResult
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(food.description.capitalized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ncPrimary)
                    .lineLimit(2)
                
                if let brand = food.brandOwner {
                    Text(brand)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.ncSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Show base calories if available
            if let energy = food.foodNutrients.first(where: { $0.nutrientId == 1008 }) {
                Text("\(Int(energy.value)) kcal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.ncSecondary)
            }
        }
        .padding()
        .background(Color.ncSurface)
        .cornerRadius(12)
    }
}
