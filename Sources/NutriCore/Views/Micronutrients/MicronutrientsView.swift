import SwiftUI
import SwiftData

struct MicronutrientsView: View {
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    
    private var goals: NutrientGoals {
        if let profile = profiles.first {
            return NutrientGoals.from(profile)
        }
        return NutrientGoals.default
    }
    
    private var todaysMeals: [MealEntry] {
        let calendar = Calendar.current
        return meals.filter { calendar.isDateInToday($0.date) }
    }
    
    private var nutrients: [NutrientInfo] {
        buildNutrientList(from: todaysMeals, goals: goals)
    }
    
    private var groupedNutrients: [(String, [NutrientInfo])] {
        [
            ("VITAMINS", nutrients.filter { $0.group == .vitamins }),
            ("MINERALS", nutrients.filter { $0.group == .minerals })
        ]
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 40) {
                        
                        Text("MICRONUTRIENTS")
                            .font(.system(size: 24, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.white)
                            .padding(.top, 20)
                            .padding(.horizontal)
                        
                        ForEach(groupedNutrients, id: \.0) { groupName, groupItems in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(groupName)
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)
                                
                                VStack(spacing: 0) {
                                    ForEach(groupItems) { item in
                                        TypographicNutrientRow(nutrient: item)
                                        Divider().background(Color.white.opacity(0.1)).padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Stark Typographic Row
struct TypographicNutrientRow: View {
    let nutrient: NutrientInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Text(nutrient.name.uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(String(format: "%.1f", nutrient.current)) / \(String(format: "%.1f", nutrient.goal)) \(nutrient.unit.uppercased())")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray)
                    .contentTransition(.numericText(value: nutrient.current))
            }
            
            // Stark Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: max(0, min(geo.size.width * CGFloat(nutrient.progress), geo.size.width)))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 16)
        .padding(.horizontal)
        .background(Color.black)
    }
}
