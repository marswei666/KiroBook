import Foundation
import StoreKit
import UIKit

@MainActor
final class AppleSubscriptionManager: ObservableObject {
    @Published private(set) var state = SubscriptionState()
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private let api = SubscriptionApiService()
    private var updatesTask: Task<Void, Never>?
    private let stateKey = "apple_subscription_state"

    init() {
        loadLocalState()
        updatesTask = listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    func initialize() {
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func canAddEntry(currentEntryCount: Int) -> Bool {
        guard state.isPaid else {
            return currentEntryCount < SubscriptionTier.free.maxEntries
        }
        return currentEntryCount < state.tier.maxEntries
    }

    func requiredTierForEntryCount(_ entryCount: Int) -> SubscriptionTier {
        SubscriptionTier.requiredTier(entryCount: entryCount)
    }

    func product(for tier: SubscriptionTier) -> Product? {
        products.first { $0.subscriptionTier == tier }
    }

    func displayPrice(for tier: SubscriptionTier) -> String {
        product(for: tier)?.displayPrice ?? tier.fallbackPriceText
    }

    func purchase(_ tier: SubscriptionTier) async -> Bool {
        lastError = nil
        isPurchasing = true
        defer { isPurchasing = false }

        if products.isEmpty {
            await loadProducts()
        }

        guard let product = product(for: tier) else {
            lastError = "Product not found"
            return false
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verifiedTransaction(from: verification) else {
                    lastError = "Transaction verification failed"
                    return false
                }

                await transaction.finish()
                await applyAppleTier(tier)
                return true

            case .userCancelled, .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    func openManageSubscriptions() {
        guard let appStoreURL = URL(string: "itms-apps://apps.apple.com/account/subscriptions"),
              let webURL = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(appStoreURL) { success in
            if !success {
                UIApplication.shared.open(webURL)
            }
        }
    }

    func refreshEntitlements() async {
        var bestTier: SubscriptionTier = .free

        for await result in Transaction.currentEntitlements {
            guard let transaction = verifiedTransaction(from: result),
                  transaction.productType == .autoRenewable,
                  let tier = SubscriptionTier.fromProductID(transaction.productID),
                  transaction.revocationDate == nil else {
                continue
            }

            if tier.maxEntries > bestTier.maxEntries {
                bestTier = tier
            }
        }

        await refreshServerWhitelist(appleTier: bestTier == .free ? nil : bestTier)
    }

    private func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let ids = Set(SubscriptionTier.paidTiers.map(\.productID))
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted {
                ($0.subscriptionTier?.maxEntries ?? 0) < ($1.subscriptionTier?.maxEntries ?? 0)
            }
        } catch {
            lastError = error.localizedDescription
            products = []
        }
    }

    private func refreshServerWhitelist(appleTier: SubscriptionTier? = nil) async {
        do {
            let response = try await api.checkSubscription(userUUID: CloudSyncService.shared.userUUID)
            if response.success, response.isActive {
                let tier = SubscriptionTier.fromID(response.tier)
                if tier.maxEntries > (appleTier?.maxEntries ?? 0) {
                    let newState = SubscriptionState(
                        tier: tier,
                        isActive: tier != .free,
                        email: response.email,
                        expiresAt: response.expiresAt,
                        source: tier == .free ? .none : .server
                    )
                    state = newState
                    saveLocalState(newState)
                } else if let appleTier {
                    await applyAppleTier(appleTier)
                } else {
                    setFreeState()
                }
            } else if let appleTier {
                await applyAppleTier(appleTier)
            } else {
                setFreeState()
            }
        } catch {
            print("Subscription whitelist refresh failed: \(error.localizedDescription)")
            if let appleTier {
                await applyAppleTier(appleTier)
            } else {
                setFreeState()
            }
        }
    }

    private func applyAppleTier(_ tier: SubscriptionTier) async {
        let newState = SubscriptionState(tier: tier, isActive: true, source: .apple)
        state = newState
        saveLocalState(newState)
    }

    private func setFreeState() {
        let newState = SubscriptionState()
        state = newState
        saveLocalState(newState)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let transaction = await self?.verifiedTransaction(from: update) else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    private func verifiedTransaction<T>(from result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let value): return value
        case .unverified: return nil
        }
    }

    private func loadLocalState() {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let decoded = try? JSONDecoder().decode(SubscriptionState.self, from: data) else {
            return
        }
        state = decoded
    }

    private func saveLocalState(_ state: SubscriptionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}
