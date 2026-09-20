import Foundation
import SwiftUI
// import StripePaymentSheet

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // 🔥 USER INSTRUCTIONS: Place your live Stripe Publishable Key here
    let stripePublishableKey = "pk_test_XXXXXXXXXXXXXXXXXXXXXXXX"
    
    // 🔥 USER INSTRUCTIONS: This is the URL to your backend endpoint that returns a PaymentIntent Client Secret
    let backendCheckoutUrl = URL(string: "https://your-backend.com/create-payment-intent")!
    
    @Published var isSubscribed: Bool {
        didSet {
            UserDefaults.standard.set(isSubscribed, forKey: "isSubscribed")
        }
    }
    
    // @Published var paymentSheet: PaymentSheet?
    // @Published var paymentResult: PaymentSheetResult?
    @Published var isPreparingPaymentSheet = false
    
    private init() {
        self.isSubscribed = UserDefaults.standard.bool(forKey: "isSubscribed")
        // StripeAPI.defaultPublishableKey = stripePublishableKey
    }
    
    func preparePaymentSheet() {
        isPreparingPaymentSheet = true
        // Commented out Stripe integration to speed up build times
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isPreparingPaymentSheet = false
        }
    }
    
    /*
    func onPaymentCompletion(result: PaymentSheetResult) {
        self.paymentResult = result
        switch result {
        case .completed:
            print("Payment completed successfully!")
            self.isSubscribed = true
        case .canceled:
            print("Payment canceled.")
        case .failed(let error):
            print("Payment failed: \(error.localizedDescription)")
        }
    }
    */
    
    // FOR TESTING ONLY: Bypass stripe for development without a backend
    func bypassSubscriptionForTesting() {
        self.isSubscribed = true
    }
}
