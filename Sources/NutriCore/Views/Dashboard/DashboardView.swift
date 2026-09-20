import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var fastingStates: [FastingState]
    @Query private var hydrations: [DailyHydration]
    
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
    
    private var currentFastingState: FastingState {
        if let state = fastingStates.first { return state }
        let newState = FastingState()
        modelContext.insert(newState)
        return newState
    }
    
    private var todaysHydration: DailyHydration {
        let calendar = Calendar.current
        if let hydration = hydrations.first(where: { calendar.isDateInToday($0.date) }) {
            return hydration
        }
        let newHydration = DailyHydration()
        modelContext.insert(newHydration)
        return newHydration
    }
    
    // Strict date formatter
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea() // Pure black
                
                ScrollView {
                    VStack(spacing: 30) {
                        
                        // 1. Header with SEARCH
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TODAY")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(2)
                                    .foregroundColor(.gray)
                                Text(formattedDate)
                                    .font(.system(size: 18, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            NavigationLink(destination: SearchView()) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                        
                        // 2. Massive Progress Ring
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 12)
                                    .frame(width: 220, height: 220)
                                
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(min(todaysMeals.totalCalories / goals.calories, 1.0)))
                                    .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .square))
                                    .frame(width: 220, height: 220)
                                    .rotationEffect(Angle(degrees: -90))
                                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: todaysMeals.totalCalories)
                                
                                VStack(spacing: 4) {
                                    Text("\(Int(todaysMeals.totalCalories))")
                                        .font(.system(size: 54, weight: .bold, design: .default))
                                        .foregroundColor(.white)
                                        .contentTransition(.numericText(value: todaysMeals.totalCalories))
                                    
                                    Text("kcal")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.gray)
                                        .tracking(2)
                                }
                            }
                            
                            Text("\(Int((todaysMeals.totalCalories / goals.calories) * 100))% OF GOAL")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.gray)
                                .padding(.top, 16)
                        }
                        .padding(.vertical, 20)
                        
                        Divider().background(Color.white.opacity(0.2)).padding(.horizontal)
                        
                        // 3. Typographic Macros Grid
                        VStack(alignment: .leading, spacing: 16) {
                            Text("MACROS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            HStack(spacing: 0) {
                                TypographicMacro(title: "PROTEIN", current: todaysMeals.totalProtein, goal: goals.protein)
                                Spacer()
                                TypographicMacro(title: "CARBS", current: todaysMeals.totalCarbs, goal: goals.carbohydrates)
                                Spacer()
                                TypographicMacro(title: "FAT", current: todaysMeals.totalFat, goal: goals.fat)
                            }
                            .padding(.horizontal)
                        }
                        
                        Divider().background(Color.white.opacity(0.2)).padding(.horizontal)
                        
                        // 3.5. Fasting Tracker
                        VStack(alignment: .leading, spacing: 16) {
                            Text("FASTING")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    TimelineView(.periodic(from: .now, by: 60.0)) { context in
                                        if currentFastingState.isFasting, let start = currentFastingState.startTime {
                                            let duration = context.date.timeIntervalSince(start)
                                            let hours = Int(duration) / 3600
                                            let minutes = (Int(duration) % 3600) / 60
                                            Text(String(format: "%02d:%02d", hours, minutes))
                                                .font(.system(size: 32, weight: .bold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("00:00")
                                                .font(.system(size: 32, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    Text(currentFastingState.isFasting ? "FASTING" : "NOT FASTING")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(currentFastingState.isFasting ? .white : .gray)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if currentFastingState.isFasting {
                                        currentFastingState.isFasting = false
                                        currentFastingState.startTime = nil
                                    } else {
                                        currentFastingState.isFasting = true
                                        currentFastingState.startTime = Date()
                                    }
                                    try? modelContext.save()
                                }) {
                                    Text(currentFastingState.isFasting ? "END FAST" : "START FAST")
                                        .font(.system(size: 12, weight: .bold))
                                        .tracking(1)
                                        .foregroundColor(currentFastingState.isFasting ? .white : .black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(currentFastingState.isFasting ? Color.clear : Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(currentFastingState.isFasting ? Color.white : Color.clear, lineWidth: 1)
                                        )
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Divider().background(Color.white.opacity(0.2)).padding(.horizontal)
                        
                        // 3.6. Electrolytes & Hydration
                        VStack(alignment: .leading, spacing: 16) {
                            Text("HYDRATION & ELECTROLYTES")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            HStack(spacing: 12) {
                                HydrationButton(title: "WATER", amount: "\(Int(todaysHydration.waterOunces)) oz", icon: "drop.fill") {
                                    todaysHydration.waterOunces += 8
                                    try? modelContext.save()
                                }
                                
                                HydrationButton(title: "SODIUM", amount: "\(Int(todaysHydration.addedSodiumMg)) mg", icon: "bolt.fill") {
                                    todaysHydration.addedSodiumMg += 100
                                    try? modelContext.save()
                                }
                            }
                            .padding(.horizontal)
                            
                            HStack(spacing: 12) {
                                HydrationButton(title: "POTASSIUM", amount: "\(Int(todaysHydration.addedPotassiumMg)) mg", icon: "bolt.fill") {
                                    todaysHydration.addedPotassiumMg += 100
                                    try? modelContext.save()
                                }
                                
                                HydrationButton(title: "MAGNESIUM", amount: "\(Int(todaysHydration.addedMagnesiumMg)) mg", icon: "bolt.fill") {
                                    todaysHydration.addedMagnesiumMg += 50
                                    try? modelContext.save()
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        Divider().background(Color.white.opacity(0.2)).padding(.horizontal)
                        
                        // 4. Typographic Timeline
                        VStack(alignment: .leading, spacing: 16) {
                            Text("MEALS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            if todaysMeals.isEmpty {
                                Text("----")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(todaysMeals.reversed()) { meal in
                                        SwipeToDeleteRow(
                                            item: meal,
                                            onDelete: {
                                                withAnimation(.spring()) {
                                                    modelContext.delete(meal)
                                                }
                                            },
                                            content: {
                                                HStack {
                                                    Text(meal.foodName.uppercased())
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .lineLimit(1)
                                                    
                                                    Spacer()
                                                    
                                                    Text("\(Int(meal.calories)) kcal")
                                                        .font(.system(size: 16, weight: .regular))
                                                        .foregroundColor(.gray)
                                                }
                                                .padding(.vertical, 16)
                                                .padding(.horizontal)
                                                .background(Color.black)
                                            }
                                        )
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

// MARK: - Stark Typographic Macro
struct TypographicMacro: View {
    let title: String
    let current: Double
    let goal: Double
    
    private var progress: Double { goal > 0 ? min(current / goal, 1.0) : 0 }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            Text("\(Int(current)) / \(Int(goal)) g")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                    
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: max(0, geo.size.width * CGFloat(progress)))
                }
            }
            .frame(width: 90, height: 6)
            .padding(.top, 4)
        }
    }
}

// MARK: - Swipe to Delete Wrapper
struct SwipeToDeleteRow<Content: View, Item: Equatable>: View {
    let item: Item
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Minimal Delete Background
            if offset < 0 {
                Button(action: {
                    onDelete()
                    offset = 0
                }) {
                    Text("DELETE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .background(Color.red)
                }
            }
            
            // Foreground Content
            content()
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                offset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring()) {
                                if value.translation.width < -50 {
                                    offset = -80
                                } else {
                                    offset = 0
                                }
                            }
                        }
                )
        }
    }
}

// MARK: - Hydration Button
struct HydrationButton: View {
    let title: String
    let amount: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.white)
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                }
                Text(amount)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .cornerRadius(12)
        }
    }
}
