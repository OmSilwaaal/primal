import Foundation
import StoreKit
import Supabase

/// Vitalis Pro, sold as an auto-renewing App Store subscription (StoreKit 2).
///
/// The source of truth is `Transaction.currentEntitlements`: transactions are signed by the App Store and
/// verified by StoreKit on device, so the app can't be tricked into granting itself access. The subscription
/// belongs to the Apple ID, not the Vitalis account; purchases made while signed in carry the account's
/// user ID as `appAccountToken` so they can be matched server-side later.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum Plan: String, CaseIterable, Identifiable {
        case monthly, annual
        var id: String { rawValue }

        /// Must match the product IDs in App Store Connect and Vitalis.storekit.
        var productID: String { "com.omsilwal.NutriCorePrimal.pro.\(rawValue)" }
        var title: String { self == .monthly ? "Monthly" : "Annual" }
    }

    @Published private(set) var isSubscribed: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var products: [Plan: Product] = [:]
    @Published var errorMessage: String?

    private static let cacheKey = "isSubscribed"
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Cached so the app opens correctly offline; refreshEntitlement() corrects it.
        isSubscribed = UserDefaults.standard.bool(forKey: Self.cacheKey)
        // Renewals, refunds, Ask to Buy approvals and purchases made on other devices arrive here.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlement()
            }
        }
        Task { await loadProducts() }
    }

    private func setSubscribed(_ value: Bool) {
        isSubscribed = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Plan.allCases.map(\.productID))
            var byPlan: [Plan: Product] = [:]
            for plan in Plan.allCases { byPlan[plan] = loaded.first { $0.id == plan.productID } }
            products = byPlan
        } catch {
            print("Loading products failed: \(error)")
        }
    }

    /// Localized price from the App Store, e.g. "$9.99 / month". Empty until products load.
    func priceLabel(for plan: Plan) -> String {
        guard let product = products[plan] else { return "" }
        return "\(product.displayPrice) / \(plan == .monthly ? "month" : "year")"
    }

    /// Second line under each plan; the annual one shows its monthly equivalent.
    func detail(for plan: Plan) -> String {
        guard plan == .annual, let product = products[plan] else { return "Cancel anytime" }
        let monthly = (product.price / 12).formatted(product.priceFormatStyle)
        return "Best value · \(monthly)/month equivalent"
    }

    /// Annual saving against twelve monthly payments, e.g. 40.
    var annualSavingsPercent: Int? {
        guard let m = products[.monthly]?.price, let a = products[.annual]?.price, m > 0 else { return nil }
        let saving = (1 - (a as NSDecimalNumber).doubleValue / ((m as NSDecimalNumber).doubleValue * 12)) * 100
        return saving >= 1 ? Int(saving.rounded()) : nil
    }

    // MARK: - Entitlement

    /// Recomputes access from the App Store's current entitlements.
    @discardableResult
    func refreshEntitlement() async -> Bool {
        let ids = Set(Plan.allCases.map(\.productID))
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ids.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > Date() }) ?? true else { continue }
            entitled = true
        }
        setSubscribed(entitled)
        return entitled
    }

    /// The subscription is tied to the Apple ID, so this only resets the cache; the next refresh restores it.
    func clearOnSignOut() { setSubscribed(false) }

    // MARK: - Purchase

    func subscribe(to plan: Plan) async {
        guard !isWorking else { return }
        errorMessage = nil
        guard let product = products[plan] else {
            await loadProducts()
            errorMessage = "Couldn't reach the App Store. Check your connection and try again."
            return
        }
        isWorking = true
        defer { isWorking = false }

        var options: Set<Product.PurchaseOption> = []
        if let userId = supabase.auth.currentUser?.id { options.insert(.appAccountToken(userId)) }

        do {
            switch try await product.purchase(options: options) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
            case .success(.unverified(_, let error)):
                errorMessage = "The App Store couldn't verify this purchase. (\(error.localizedDescription))"
            case .pending:
                errorMessage = "Your purchase is waiting for approval. You'll get access as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Asks the App Store to sync this Apple ID's purchases. Shows a sign-in prompt if needed.
    func restorePurchases() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        try? await AppStore.sync()
        if !(await refreshEntitlement()) {
            errorMessage = "No active Vitalis Pro subscription found for this Apple ID."
        }
    }

    #if DEBUG
    /// Development only: unlocks the app locally without a purchase. Compiled out of release builds.
    func debugUnlock() { setSubscribed(true) }
    #endif
}
