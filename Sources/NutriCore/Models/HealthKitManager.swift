import Foundation
import HealthKit

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()
    private static let requestedKey = "healthKitAuthorizationRequested.v2"
    
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
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .timeInDaylight)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .waistCircumference)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
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

    // MARK: - Daylight (Apple Watch "Time in Daylight")
    /// Minutes of daylight per calendar day for the last `days` days (oldest first).
    func dailyDaylightMinutes(days: Int) async -> [Date: Double] {
        guard isAuthorized, let type = HKObjectType.quantityType(forIdentifier: .timeInDaylight) else { return [:] }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) ?? Date()
        return await withCheckedContinuation { continuation in
            let q = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                                options: .cumulativeSum, anchorDate: start,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, collection, _ in
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    if let sum = stat.sumQuantity() { out[stat.startDate] = sum.doubleValue(for: .minute()) }
                }
                continuation.resume(returning: out)
            }
            healthStore.execute(q)
        }
    }

    // MARK: - Biomarker import
    struct ImportedReading { let kind: BiomarkerKind; let date: Date; let value: Double }

    /// Latest samples (one per day per type) from Health for body measures, BP, HR, HRV and glucose.
    func importBiomarkers(days: Int = 90) async -> [ImportedReading] {
        guard isAuthorized else { return [] }
        let specs: [(HKQuantityTypeIdentifier, HKUnit, BiomarkerKind, Double)] = [
            (.bodyMass, .gramUnit(with: .kilo), .weight, 1),
            (.bodyFatPercentage, .percent(), .bodyFat, 100),
            (.waistCircumference, .meterUnit(with: .centi), .waist, 1),
            (.bloodPressureSystolic, .millimeterOfMercury(), .systolic, 1),
            (.bloodPressureDiastolic, .millimeterOfMercury(), .diastolic, 1),
            (.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), .restingHR, 1),
            (.heartRateVariabilitySDNN, .secondUnit(with: .milli), .hrv, 1),
            (.bloodGlucose, HKUnit(from: "mg/dL"), .fastingGlucose, 1),
        ]
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var out: [ImportedReading] = []
        for (id, unit, kind, scale) in specs {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
                let q = HKSampleQuery(sampleType: type,
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                      limit: 200,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, r, _ in
                    continuation.resume(returning: (r as? [HKQuantitySample]) ?? [])
                }
                healthStore.execute(q)
            }
            var seenDays = Set<Date>()
            for s in samples {
                let day = Calendar.current.startOfDay(for: s.endDate)
                guard seenDays.insert(day).inserted else { continue }
                out.append(ImportedReading(kind: kind, date: s.endDate, value: s.quantity.doubleValue(for: unit) * scale))
            }
        }
        return out
    }
}
