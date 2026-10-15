import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()
    private static let requestedKey = "healthKitAuthorizationRequested"
    
    @Published var isAuthorized = false
    @Published var todaySteps: Double = 0
    @Published var todayActiveEnergy: Double = 0
    
    private init() {
        checkAuthorizationStatus()
    }
    
    // MARK: - Types to Read/Write
    private var typesToRead: Set<HKObjectType> {
        return [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
    }
    
    private var typesToWrite: Set<HKSampleType> {
        return [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!
        ]
    }
    
    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
        UserDefaults.standard.set(true, forKey: Self.requestedKey)
        checkAuthorizationStatus()
        
        if isAuthorized {
            await fetchTodayData()
        }
    }
    
    private func checkAuthorizationStatus() {
        // HealthKit never reveals read permission, and stepCount is read-only here, so its status stays
        // .notDetermined forever. Remember that we asked instead; queries simply return 0 if access was denied.
        isAuthorized = HKHealthStore.isHealthDataAvailable() && UserDefaults.standard.bool(forKey: Self.requestedKey)
    }
    
    // MARK: - Read Data
    func fetchTodayData() async {
        guard isAuthorized else { return }
        
        async let steps = fetchQuantity(for: .stepCount, unit: HKUnit.count())
        async let energy = fetchQuantity(for: .activeEnergyBurned, unit: HKUnit.kilocalorie())
        
        let fetchedSteps = await steps
        let fetchedEnergy = await energy
        
        todaySteps = fetchedSteps
        todayActiveEnergy = fetchedEnergy
    }
    
    private func fetchQuantity(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        return await withCheckedContinuation { continuation in
            guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
                continuation.resume(returning: 0)
                return
            }
            
            let calendar = Calendar.current
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
            
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                guard let sum = result?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Write Data
    func saveDietaryEnergy(calories: Double, date: Date = Date()) {
        guard isAuthorized, calories > 0, let energyType = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
              healthStore.authorizationStatus(for: energyType) == .sharingAuthorized else { return }
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
        let sample = HKQuantitySample(type: energyType, quantity: quantity, start: date, end: date)
        healthStore.save(sample) { _, error in
            if let error = error { print("Error saving calories to HealthKit: \(error)") }
        }
    }
    
    func saveDietaryProtein(grams: Double, date: Date = Date()) {
        guard isAuthorized, grams > 0, let proteinType = HKObjectType.quantityType(forIdentifier: .dietaryProtein),
              healthStore.authorizationStatus(for: proteinType) == .sharingAuthorized else { return }
        let quantity = HKQuantity(unit: HKUnit.gram(), doubleValue: grams)
        let sample = HKQuantitySample(type: proteinType, quantity: quantity, start: date, end: date)
        healthStore.save(sample) { _, error in
            if let error = error { print("Error saving protein to HealthKit: \(error)") }
        }
    }
    
    func saveDietaryWater(ounces: Double, date: Date = Date()) {
        guard isAuthorized, ounces > 0, let waterType = HKObjectType.quantityType(forIdentifier: .dietaryWater),
              healthStore.authorizationStatus(for: waterType) == .sharingAuthorized else { return }
        // 1 fl oz = 29.5735 mL
        let ml = ounces * 29.5735
        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli), doubleValue: ml)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date)
        healthStore.save(sample) { _, error in
            if let error = error { print("Error saving water to HealthKit: \(error)") }
        }
    }
}
