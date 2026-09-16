import Foundation

struct AIFoodResult: Codable {
    let name: String
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let totalFat: Double
    let servingSize: Double // in grams
}

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    private init() {}
    
    @Published var isAnalyzing = false
    @Published var result: AIFoodResult?
    @Published var errorMessage: String?
    
    func analyzeImage(_ imageData: Data) async {
        guard AppConstants.geminiAPIKey != "YOUR_GEMINI_API_KEY_HERE" else {
            self.errorMessage = "⚠️ ADD YOUR GEMINI API KEY IN Constants.swift"
            return
        }
        
        isAnalyzing = true
        errorMessage = nil
        result = nil
        
        let base64Image = imageData.base64EncodedString()
        let prompt = """
        Analyze this image of food. Identify what it is, and estimate its macronutrients based on what you see.
        You MUST respond with ONLY a raw JSON object and nothing else. No markdown formatting, no backticks.
        The JSON object must match this schema exactly:
        {
          "name": "String (e.g. Banana, Chicken Breast)",
          "calories": Number,
          "protein": Number,
          "carbohydrates": Number,
          "totalFat": Number,
          "servingSize": Number (estimated grams)
        }
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(AppConstants.geminiAPIKey)"),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            isAnalyzing = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Parse Gemini response structure
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                
                if let rawJSONData = text.data(using: .utf8) {
                    let aiFood = try JSONDecoder().decode(AIFoodResult.self, from: rawJSONData)
                    self.result = aiFood
                } else {
                    self.errorMessage = "Failed to parse AI response data."
                }
            } else {
                self.errorMessage = "Invalid response from AI."
            }
        } catch {
            self.errorMessage = "AI Analysis failed: \(error.localizedDescription)"
        }
        
        isAnalyzing = false
    }
    
    func clearResult() {
        result = nil
        errorMessage = nil
    }
}
