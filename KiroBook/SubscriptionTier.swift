import Foundation
import StoreKit

enum SubscriptionTier: String, CaseIterable, Identifiable, Codable {
    case free
    case tier1 = "tier_1"
    case tier2 = "tier_2"
    case tier3 = "tier_3"

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .free: return ""
        case .tier1: return "kirobook_plus_monthly"
        case .tier2: return "kirobook_pro_monthly"
        case .tier3: return "kirobook_max_monthly"
        }
    }

    var maxEntries: Int {
        #if DEBUG
        switch self {
        case .free: return 3
        case .tier1: return 6
        case .tier2: return 9
        case .tier3: return Int.max
        }
        #else
        switch self {
        case .free: return 30
        case .tier1: return 60
        case .tier2: return 90
        case .tier3: return Int.max
        }
        #endif
    }

    var fallbackPrice: Decimal {
        switch self {
        case .free: return 0
        case .tier1: return 9.99
        case .tier2: return 14.99
        case .tier3: return 19.99
        }
    }

    var fallbackPriceText: String {
        switch self {
        case .free: return "Free"
        case .tier1: return "$9.99"
        case .tier2: return "$14.99"
        case .tier3: return "$19.99"
        }
    }

    var displayName: String {
        switch self {
        case .free: return "KiroBook Free"
        case .tier1: return "KiroBook Plus"
        case .tier2: return "KiroBook Pro"
        case .tier3: return "KiroBook Max"
        }
    }

    var transactionAmountCents: Int {
        NSDecimalNumber(decimal: fallbackPrice * 100).intValue
    }

    static var paidTiers: [SubscriptionTier] { [.tier1, .tier2, .tier3] }

    static func fromProductID(_ productID: String) -> SubscriptionTier? {
        paidTiers.first { $0.productID == productID }
    }

    static func fromID(_ id: String) -> SubscriptionTier {
        SubscriptionTier(rawValue: id) ?? .free
    }

    static func requiredTier(entryCount: Int) -> SubscriptionTier {
        paidTiers.first { entryCount <= $0.maxEntries } ?? .tier3
    }
}

struct SubscriptionState: Codable, Equatable {
    var tier: SubscriptionTier = .free
    var isActive: Bool = false
    var email: String = ""
    var expiresAt: String = ""
    var source: SubscriptionSource = .none

    var isFree: Bool { tier == .free }
    var isPaid: Bool { tier != .free && isActive }
}

enum SubscriptionSource: String, Codable {
    case none
    case apple
    case server
}

extension Product {
    var subscriptionTier: SubscriptionTier? {
        SubscriptionTier.fromProductID(id)
    }
}
