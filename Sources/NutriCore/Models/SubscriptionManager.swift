import Foundation
import SwiftUI
import UIKit
import StripePaymentSheet
import Supabase

/// Subscription state. The source of truth is the `subscriptions` table, which only the Stripe
/// webhook can write, so the app can't be tricked into granting itself access.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum Plan: String, CaseIterable, Identifiable {
        case monthly, annual
        var id: String { rawValue }

        // Display only. The amount actually charged is the Stripe price configured on the backend; keep these in sync.
        var priceLabel: String { self == .monthly ? "$9.99 / month" : "$71.99 / year" }
        var detail: String { self == .monthly ? "Cancel anytime" : "Best value · $6.00/month equivalent" }
        var title: String { self == .monthly ? "Monthly" : "Annual" }
    }

    @Published private(set) var isSubscribed: Bool
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private static let cacheKey = "isSubscribed"

    private init() {
        // Cached so the app opens correctly offline; refreshEntitlement() corrects it.
        isSubscribed = UserDefaults.standard.bool(forKey: Self.cacheKey)
    }

    private func setSubscribed(_ value: Bool) {
        isSubscribed = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }

    // MARK: - Entitlement

    private struct SubscriptionRow: Decodable {
        let status: String
        let currentPeriodEnd: Date?

        enum CodingKeys: String, CodingKey {
            case status
            case currentPeriodEnd = "current_period_end"
        }

        var isEntitled: Bool {
            guard status == "active" || status == "trialing" else { return false }
            return currentPeriodEnd.map { $0 > Date() } ?? true
        }
    }

    /// Reads the user's subscription row. With `onlyUpgrade`, a missing/inactive row is ignored
    /// (used while waiting for the webhook right after a payment).
    @discardableResult
    func refreshEntitlement(onlyUpgrade: Bool = false) async -> Bool {
        guard let userId = try? await supabase.auth.session.user.id else {
            if !onlyUpgrade { setSubscribed(false) }
            return false
        }
        do {
            let rows: [SubscriptionRow] = try await supabase
                .from("subscriptions")
                .select("status, current_period_end")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            let entitled = rows.first?.isEntitled ?? false
            if entitled || !onlyUpgrade { setSubscribed(entitled) }
            return entitled
        } catch {
            // Offline or transient failure: keep the cached value rather than locking the user out.
            print("Entitlement refresh failed: \(error)")
            return isSubscribed
        }
    }

    func clearOnSignOut() { setSubscribed(false) }

    // MARK: - Checkout

    private struct CheckoutRequest: Encodable { let plan: String }
    private struct CheckoutResponse: Decodable {
        let clientSecret: String
        let customerId: String
        let ephemeralKey: String
        let publishableKey: String
    }

    func subscribe(to plan: Plan) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let checkout: CheckoutResponse = try await supabase.functions.invoke(
                "create-subscription",
                options: FunctionInvokeOptions(body: CheckoutRequest(plan: plan.rawValue))
            )

            STPAPIClient.shared.publishableKey = checkout.publishableKey
            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Vitalis"
            config.customer = .init(id: checkout.customerId, ephemeralKeySecret: checkout.ephemeralKey)
            config.returnURL = "com.omsilwal.NutriCorePrimal://stripe-redirect"
            config.allowsDelayedPaymentMethods = false

            let sheet = PaymentSheet(paymentIntentClientSecret: checkout.clientSecret, configuration: config)
            let result = await present(sheet)

            switch result {
            case .completed:
                setSubscribed(true) // optimistic; the webhook row confirms below
                await confirmWithServer()
            case .canceled:
                break
            case .failed(let error):
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// The webhook usually lands within a couple of seconds. If it never does, revert the optimistic grant.
    private func confirmWithServer() async {
        for _ in 0..<10 {
            if await refreshEntitlement(onlyUpgrade: true) { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        errorMessage = "Payment received, but activation is taking longer than expected. Tap Restore in a moment."
        await refreshEntitlement()
    }

    private func present(_ sheet: PaymentSheet) async -> PaymentSheetResult {
        await withCheckedContinuation { continuation in
            guard let top = Self.topViewController() else {
                continuation.resume(returning: .failed(error: NSError(
                    domain: "Subscription", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Couldn't open the payment screen."])))
                return
            }
            sheet.present(from: top) { continuation.resume(returning: $0) }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private static func message(for error: Error) -> String {
        if let fn = error as? FunctionsError, case .httpError(let code, let data) = fn {
            if code == 409 { return "You're already subscribed. Tap Restore." }
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = body["error"] as? String { return text }
        }
        return "Couldn't start checkout. Check your connection and try again."
    }

    // MARK: - Manage

    private struct PortalResponse: Decodable { let url: URL }

    /// Opens Stripe's billing portal (update card, cancel, invoices).
    func openBillingPortal() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let portal: PortalResponse = try await supabase.functions.invoke("create-portal-session")
            await UIApplication.shared.open(portal.url)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func restorePurchases() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        if !(await refreshEntitlement()) {
            errorMessage = "No active subscription found for this account."
        }
    }

    #if DEBUG
    /// Development only: unlocks the app locally without Stripe. Compiled out of release builds.
    func debugUnlock() { setSubscribed(true) }
    #endif
}
