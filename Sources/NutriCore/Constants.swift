import Foundation

// MARK: - API Configuration
// ─────────────────────────────────────────────────────────────────────────────
// STEP 1: Get your FREE USDA API key at:
//         https://fdc.nal.usda.gov/api-key-signup.html
//         (Instant signup, no credit card needed)
//
// STEP 2: Replace "YOUR_USDA_API_KEY_HERE" below with your key.
// ─────────────────────────────────────────────────────────────────────────────
enum AppConstants {
    static let usdaAPIKey = "zmvUjlHkM4v6rkRYTHoxjx0yZV7MjTXoIJtthyIJ"
    static let usdaBaseURL = "https://api.nal.usda.gov/fdc/v1"
    
    // MARK: - Supabase Configuration
    static let supabaseURL = URL(string: "https://ggxpqswpambvbnliopfv.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_aDXvVcLHxuAt86bF5VhfcQ_IHPbKk3a"
    
    // MARK: - Gemini AI Configuration
    static let geminiAPIKey = "YOUR_GEMINI_API_KEY_HERE"
}
