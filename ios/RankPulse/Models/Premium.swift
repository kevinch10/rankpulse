import Foundation
import Observation
import StoreKit

/// The Premium subscription (StoreKit 2). Premium unlocks unlimited fantasy matches.
@MainActor
@Observable
final class PremiumStore {
    static let groupID = "21500001"
    static let productIDs = ["app.rankpulse.premium.monthly", "app.rankpulse.premium.yearly"]

    private(set) var isPremium = false
    /// nil while checking; false when the App Store has no Premium products (not set up yet, or offline).
    private(set) var productsAvailable: Bool?
    private var updates: Task<Void, Never>?

    init() {
        // Renewals, refunds and purchases made on another device.
        updates = Task { [weak self] in
            for await _ in Transaction.updates { await self?.refresh() }
        }
        Task { await refresh() }
        Task {
            let products = (try? await Product.products(for: Self.productIDs)) ?? []
            productsAvailable = !products.isEmpty
        }
    }

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, Self.productIDs.contains(t.productID), t.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }
}
