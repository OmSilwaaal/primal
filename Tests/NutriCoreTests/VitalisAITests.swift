import XCTest
@testable import NutriCore

/// The app side of the AI: what it sends (only the last 30 days, at most 40 foods, no free text beyond names) and
/// that it reads the server's replies exactly.
final class VitalisAITests: XCTestCase {
    private func meal(_ name: String, daysAgo: Int, kcal: Double = 100) -> MealEntry {
        let m = MealEntry()
        m.foodName = name
        m.calories = kcal
        m.servingSize = 100
        m.vitaminB12 = 2
        m.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return m
    }

    func testAskSendsOnlyRecentFoodsAndCapsTheCount() {
        let meals = (0..<60).map { meal("Food \($0)", daysAgo: $0 / 2) } + [meal("Old liver", daysAgo: 45)]
        let sent = VitalisAI.logged(meals)
        XCTAssertLessThanOrEqual(sent.count, 40)
        XCTAssertTrue(sent.allSatisfy { (0...30).contains($0.daysAgo) })
        XCTAssertFalse(sent.contains { $0.name == "Old liver" })
        XCTAssertEqual(sent.first?.nutrients["b12"], 2)
        XCTAssertNil(sent.first?.nutrients["vitD"], "zero values aren't sent")
    }

    func testLongNamesAreCut() {
        let sent = VitalisAI.logged([meal(String(repeating: "a", count: 300), daysAgo: 0)])
        XCTAssertEqual(sent.first?.name.count, 60)
    }

    func testServerScanReplyDecodesIntoPhotoItems() throws {
        let json = """
        {"items":[{"name":"Ribeye steak","usdaQuery":"Beef, ribeye, steak, raw","grams":220,"raw":true,
                   "kcal":560,"protein":44,"carbs":0,"fat":42}],"remaining":3,"plan":"free"}
        """
        let reply = try JSONDecoder().decode(VitalisAI.ScanResult.self, from: Data(json.utf8))
        XCTAssertEqual(reply.remaining, 3)
        XCTAssertEqual(reply.items.first?.usdaQuery, "Beef, ribeye, steak, raw")
        XCTAssertTrue(reply.items.first?.raw ?? false)
    }

    func testPhotosAreShrunkUnderTheServerLimit() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000)).image { ctx in
            for i in 0..<200 {
                UIColor(hue: CGFloat(i) / 200, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: i * 20, y: (i * 37) % 3000, width: 20, height: 3000))
            }
        }
        let jpeg = try AIService.prepare(big.jpegData(compressionQuality: 1)!)
        XCTAssertLessThanOrEqual(jpeg.count, 1_100_000)
        XCTAssertEqual(Array(jpeg.prefix(3)), [0xFF, 0xD8, 0xFF], "a JPEG, which is all the server accepts")
        let image = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 1024)
    }
}
