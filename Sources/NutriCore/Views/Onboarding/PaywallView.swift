import SwiftUI
// import StripePaymentSheet

struct PaywallView: View {
    @StateObject private var subManager = SubscriptionManager.shared
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Subtle ambient glow
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(y: -300)
            
            VStack(spacing: 40) {
                Spacer()
                
                VStack(spacing: 12) {
                    Text("PRIMAL")
                        .font(.system(size: 36, weight: .heavy, design: .default))
                        .tracking(8)
                        .foregroundColor(.white)
                    
                    Text("PRO")
                        .font(.system(size: 36, weight: .heavy, design: .default))
                        .tracking(8)
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 24) {
                    FeatureRow(icon: "bolt.fill", title: "Fasting Tracker", subtitle: "Live lock-screen and dashboard timer.")
                    FeatureRow(icon: "heart.fill", title: "HealthKit Sync", subtitle: "Auto-sync steps, active calories, and vitals.")
                    FeatureRow(icon: "drop.fill", title: "Electrolytes", subtitle: "Advanced sodium and magnesium tracking.")
                    FeatureRow(icon: "camera.macro", title: "Food Scanner", subtitle: "Instant AI macro estimation from photos.")
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                VStack(spacing: 16) {
                    /*
                    if let paymentSheet = subManager.paymentSheet {
                        PaymentSheet.PaymentButton(
                            paymentSheet: paymentSheet,
                            onCompletion: subManager.onPaymentCompletion
                        ) {
                            Text("SUBSCRIBE - $9.99/MO")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                    } else {
                    */
                        Button(action: {
                            // Empty action, waiting for payment sheet
                        }) {
                            Text(subManager.isPreparingPaymentSheet ? "LOADING..." : "STRIPE TEMPORARILY DISABLED")
                                .font(.system(size: 16, weight: .bold))
                                .tracking(2)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .disabled(true)
                    // }
                    
                    // TODO: REMOVE THIS IN PRODUCTION
                    // This is just a bypass button so the user can test the app without setting up a backend
                    Button(action: {
                        withAnimation {
                            subManager.bypassSubscriptionForTesting()
                        }
                    }) {
                        Text("[DEV ONLY] BYPASS SUBSCRIPTION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            /*
            if subManager.paymentSheet == nil && !subManager.isPreparingPaymentSheet {
                subManager.preparePaymentSheet()
            }
            */
            subManager.preparePaymentSheet()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
    }
}
