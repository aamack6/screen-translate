import Foundation
import StoreKit

/// Free daily allowance plus a one-time "Pro" unlock. No ads, coins or subscriptions: the most
/// common complaint about other screen translators is how they charge.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var proProduct: Product?
    @Published private(set) var isPro = Usage.isProCached
    @Published private(set) var purchaseError: String?

    private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    func load() async {
        proProduct = try? await Product.products(for: [Usage.proProductID]).first
        await refreshEntitlement()
    }

    func buyPro() async {
        guard let proProduct else { return }
        purchaseError = nil
        do {
            switch try await proProduct.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
            case .success(.unverified):
                purchaseError = "The purchase couldn't be verified. Try Restore purchases."
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
        await refreshEntitlement()
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        isPro = await Usage.hasProEntitlement()
    }
}

/// Counts free translations per day. Shared by the app and the Shortcuts action (same process,
/// same UserDefaults).
enum Usage {
    /// Create a non-consumable in-app purchase with this ID in App Store Connect.
    static let proProductID = "com.aamack6.ScreenTranslate.pro"
    static let freeTranslationsPerDay = 10

    private static let dayKey = "usage.day"
    private static let countKey = "usage.count"
    private static let proKey = "usage.isPro"

    static var isProCached: Bool { UserDefaults.standard.bool(forKey: proKey) }

    static var usedToday: Int {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: dayKey) == today ? defaults.integer(forKey: countKey) : 0
    }

    static var remainingToday: Int { max(freeTranslationsPerDay - usedToday, 0) }

    /// Checks the App Store receipt and caches the answer for quick reads.
    static func hasProEntitlement() async -> Bool {
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Usage.proProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        UserDefaults.standard.set(owned, forKey: proKey)
        return owned
    }

    /// Throws when today's free translations are used up and Pro isn't owned.
    static func checkAllowance() async throws {
        if isProCached { return }
        if remainingToday > 0 { return }
        // The cache can lag behind a purchase made on another device.
        if await hasProEntitlement() { return }
        throw UsageError.dailyLimitReached
    }

    static func recordTranslation() {
        guard !isProCached else { return }
        let used = usedToday
        let defaults = UserDefaults.standard
        defaults.set(today, forKey: dayKey)
        defaults.set(used + 1, forKey: countKey)
    }

    private static var today: String {
        Date().formatted(.iso8601.year().month().day())
    }
}

enum UsageError: LocalizedError {
    case dailyLimitReached

    var errorDescription: String? {
        "You've used today's \(Usage.freeTranslationsPerDay) free translations. Open ScreenTranslate to unlock unlimited translations with a one-time purchase, or try again tomorrow."
    }
}
