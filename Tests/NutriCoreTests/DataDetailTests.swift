import XCTest
@testable import NutriCore

/// The Data sheet's breakdown by food, and the wheel's motion.
final class DataDetailTests: XCTestCase {
    private func meal(_ name: String, _ set: (MealEntry) -> Void) -> MealEntry {
        let m = MealEntry(); m.foodName = name; m.servingSize = 100; set(m); return m
    }

    func testEveryNutrientsBreakdownAddsUpToItsTotal() {
        let meals = [
            meal("Beef, variety meats and by-products, liver, raw") { $0.vitaminB12 = 59; $0.vitaminA = 4970; $0.iron = 4.9; $0.calories = 135; $0.choline = 333 },
            meal("Egg, yolk, raw, fresh") { $0.vitaminB12 = 2; $0.vitaminA = 381; $0.choline = 820; $0.calories = 322; $0.iodine = 20 },
            meal("Beef, variety meats and by-products, liver, raw") { $0.vitaminB12 = 30; $0.iron = 2 },
            meal("Blueberries, raw") { $0.vitaminC = 9.7; $0.fiber = 2.4 },
        ]
        let all = buildNutrientList(from: meals, goals: .default) + buildRawList(from: meals, isMale: true)
        for n in all {
            let sum = n.sources(in: meals).reduce(0) { $0 + $1.amount }
            XCTAssertEqual(sum, n.current, accuracy: 1e-9, "\(n.name): breakdown must equal the total")
            let shares = n.sources(in: meals).reduce(0) { $0 + $1.share }
            if n.current > 0 { XCTAssertEqual(shares, 1, accuracy: 1e-9, n.name) }
        }
    }

    func testSameFoodTwiceCountsOnceAndBiggestComesFirst() {
        let meals = [
            meal("Beef, liver, raw") { $0.vitaminB12 = 59 },
            meal("Egg, yolk, raw") { $0.vitaminB12 = 2 },
            meal("Beef, liver, raw") { $0.vitaminB12 = 30 },
        ]
        let b12 = buildNutrientList(from: meals, goals: .default).first { $0.id == "b12" }!
        let sources = b12.sources(in: meals)
        XCTAssertEqual(sources.map(\.name), ["Beef", "Egg"])
        XCTAssertEqual(sources.first?.amount ?? 0, 89, accuracy: 1e-9)
        XCTAssertEqual(sources.first?.share ?? 0, 89.0 / 91, accuracy: 1e-9)
        let vitD = buildNutrientList(from: meals, goals: .default).first { $0.id == "vd" }!
        XCTAssertTrue(vitD.sources(in: meals).isEmpty)
    }

    @MainActor
    func testWheelCarriesTheReleaseSpeedAndSettlesWithoutOvershoot() {
        let wheel = WheelPhysics()
        wheel.jump(to: 0)
        _ = wheel.grab()
        wheel.release(to: 1, velocity: 3)   // a flick towards the next card at 3 cards a second
        XCTAssertEqual(wheel.velocity, 3, "no restart from zero speed on release")
        var highest = 0.0
        for _ in 0..<240 { wheel.advance(by: 1.0 / 120); highest = max(highest, wheel.position) }
        XCTAssertEqual(wheel.position, 1, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(highest, 1.06, "barely any overshoot")
        // Grabbing mid-glide holds the wheel where it is.
        wheel.release(to: 2, velocity: 0)
        for _ in 0..<12 { wheel.advance(by: 1.0 / 120) }
        let midway = wheel.position
        XCTAssertEqual(wheel.grab(), midway)
        XCTAssertGreaterThan(midway, 1); XCTAssertLessThan(midway, 2)
    }

    func testEachSwipeTurnsAtMostOneCard() {
        XCTAssertEqual(DataWheel.target(from: 0, to: 0.9, velocity: 25), 1, "a hard flick still moves one card")
        XCTAssertEqual(DataWheel.target(from: 0, to: -0.9, velocity: -25), -1)
        XCTAssertEqual(DataWheel.target(from: 2, to: 2.4, velocity: 0), 3, "past a third of a card")
        XCTAssertEqual(DataWheel.target(from: 2, to: 2.2, velocity: 0.1), 2, "a short, slow drag springs back")
        XCTAssertEqual(DataWheel.target(from: 0, to: 0.2, velocity: -2), -1, "a flick decides the direction")
    }
}
