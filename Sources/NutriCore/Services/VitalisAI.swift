import Foundation
import Supabase

/// The app's only way to reach the AI: the `ai` Supabase Edge Function, which holds the Claude API key, checks the
/// account and its Pro subscription with Apple, enforces every rate limit, screens questions, and calls Claude
/// Haiku 5.5. Nothing here can raise a limit — the server decides; the app only shows what it's told.
enum VitalisAI {
    /// What went wrong, in words the person can act on (from the server's `message`).
    struct Failure: LocalizedError, Equatable {
        /// invalid | unauthorized | pro_required | too_large | off_topic | crisis | no_food | quota | slow_down | busy | error
        let code: String
        let message: String
        var remaining: Int? = nil
        var errorDescription: String? { message }
    }

    struct ScanResult: Decodable {
        let items: [PhotoMeal.Item]
        /// Photo scans left today on this plan.
        let remaining: Int
        let plan: String
    }

    struct AskResult: Decodable {
        let answer: String
        let remaining: Int
    }

    /// One logged meal as the server accepts it: no ids, photos or free text beyond the food's name.
    struct LoggedFood: Encodable {
        let name: String
        let grams: Double
        let kcal: Double
        let daysAgo: Int
        let nutrients: [String: Double]
    }

    private struct ScanBody: Encodable { let action = "scan"; let image: String; let entitlement: String? }
    private struct AskBody: Encodable { let action = "ask"; let question: String; let log: [LoggedFood]; let entitlement: String? }
    private struct ErrorBody: Decodable { let error: String; let message: String; let remaining: Int? }

    static let maxQuestionLength = 200

    static func scan(jpeg: Data) async throws -> ScanResult {
        let body = ScanBody(image: jpeg.base64EncodedString(), entitlement: await SubscriptionManager.shared.entitlementJWS())
        return try await call(body)
    }

    static func ask(_ question: String, meals: [MealEntry]) async throws -> AskResult {
        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuestionLength))
        let body = AskBody(question: trimmed, log: logged(meals), entitlement: await SubscriptionManager.shared.entitlementJWS())
        return try await call(body)
    }

    /// The last 30 days, newest first, at most 40 foods, with the nutrients Ask can talk about.
    static func logged(_ meals: [MealEntry], now: Date = .now) -> [LoggedFood] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return meals.sorted { $0.date > $1.date }.prefix(40).compactMap { m in
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: m.date), to: today).day ?? 0
            guard (0...30).contains(days) else { return nil }
            let all: [String: Double] = [
                "protein": m.protein, "fat": m.totalFat, "carbs": m.carbohydrates, "fiber": m.fiber,
                "iron": m.iron, "zinc": m.zinc, "b12": m.vitaminB12, "vitA": m.vitaminA, "vitD": m.vitaminD,
                "folate": m.folate, "choline": m.choline, "omega3": m.omega3,
            ]
            return LoggedFood(name: String(m.foodName.prefix(60)), grams: m.servingSize, kcal: m.calories, daysAgo: days,
                              nutrients: all.filter { $0.value > 0 }.mapValues { ($0 * 10).rounded() / 10 })
        }
    }

    private static func call<Body: Encodable, Result: Decodable>(_ body: Body) async throws -> Result {
        guard await AuthManager.shared.ensureSession() else {
            throw Failure(code: "unauthorized", message: "Sign in to use AI features.")
        }
        do {
            return try await supabase.functions.invoke("ai", options: FunctionInvokeOptions(body: body))
        } catch FunctionsError.httpError(let code, let data) {
            if let e = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw Failure(code: e.error, message: e.message, remaining: e.remaining)
            }
            throw Failure(code: "error", message: code == 401 ? "Sign in to use AI features." : "That didn't work. Try again.")
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure(code: "error", message: "Couldn't reach Vitalis. Check your connection and try again.")
        }
    }
}
