import Foundation
import UIKit

struct AIFoodResult: Codable {
    let name: String
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let totalFat: Double
    let servingSize: Double // estimated grams for the whole plate/item in the photo
}

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    private init() {}

    @Published var isAnalyzing = false
    @Published var result: AIFoodResult?
    @Published var errorMessage: String?

    private static let prompt = """
    Analyze this photo of food. Identify what it is and estimate its nutrition for the portion shown.
    Respond with ONLY a JSON object with exactly these keys:
    {"name": string, "calories": number, "protein": number, "carbohydrates": number, "totalFat": number, "servingSize": number}
    "servingSize" is the estimated weight in grams of the portion in the photo. Macros are grams for that whole portion; calories are kcal.
    If the image does not contain food, return {"name": "", "calories": 0, "protein": 0, "carbohydrates": 0, "totalFat": 0, "servingSize": 0}.
    """

    func analyzeImage(_ imageData: Data) async {
        guard AppConstants.geminiAPIKey != "YOUR_GEMINI_API_KEY_HERE" else {
            errorMessage = "Add your Gemini API key in Constants.swift to enable photo scanning."
            return
        }

        isAnalyzing = true
        errorMessage = nil
        result = nil
        defer { isAnalyzing = false }

        do {
            let jpeg = try await Task.detached(priority: .userInitiated) { try Self.prepare(imageData) }.value
            let food = try await Self.request(jpeg)
            guard !food.name.isEmpty, food.servingSize > 0 else {
                errorMessage = "No food detected. Try again with the food centered."
                return
            }
            result = food
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearResult() {
        result = nil
        errorMessage = nil
    }

    // MARK: - Networking

    /// Downscale + recompress: full-resolution photos are several MB and slow the request for no accuracy gain.
    private nonisolated static func prepare(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw AIError.badImage }
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { throw AIError.badImage }
        return jpeg
    }

    private nonisolated static func request(_ jpeg: Data) async throws -> AIFoodResult {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(AppConstants.geminiModel):generateContent") else {
            throw AIError.badResponse
        }
        let body: [String: Any] = [
            "contents": [["parts": [
                ["text": prompt],
                ["inlineData": ["mimeType": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0.2],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConstants.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw AIError.api(http.statusCode, message)
        }

        guard let text = ((((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String)
        else { throw AIError.badResponse }

        // Models occasionally wrap JSON in a code fence despite the mime type.
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = cleaned.data(using: .utf8) else { throw AIError.badResponse }
        return try JSONDecoder().decode(AIFoodResult.self, from: raw)
    }

    enum AIError: LocalizedError {
        case badImage, badResponse
        case api(Int, String?)

        var errorDescription: String? {
            switch self {
            case .badImage: return "Couldn't read the photo."
            case .badResponse: return "The AI returned an unreadable response. Try again."
            case .api(let code, let message):
                if code == 400 || code == 403 { return "AI request rejected. Check your Gemini API key. \(message ?? "")" }
                if code == 429 { return "AI rate limit reached. Try again in a moment." }
                return "AI error \(code). \(message ?? "")"
            }
        }
    }
}
