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

    static var isProCached: Bool { isDeveloperBuild || UserDefaults.standard.bool(forKey: proKey) }

    /// Builds installed from Xcode carry a development provisioning profile; App Store and
    /// TestFlight builds don't. The developer's own copy is unlimited.
    static let isDeveloperBuild = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil

    static var usedToday: Int {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: dayKey) == today ? defaults.integer(forKey: countKey) : 0
    }

    static var remainingToday: Int { max(freeTranslationsPerDay - usedToday, 0) }

    /// Checks the App Store receipt and caches the answer for quick reads.
    static func hasProEntitlement() async -> Bool {
        if isDeveloperBuild { return true }
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

    // MARK: Live mode

    static let freeLiveMinutesPerDay = 5

    private static let liveDayKey = "usage.live.day"
    private static let liveSecondsKey = "usage.live.seconds"

    static var liveSecondsRemainingToday: Double {
        let defaults = UserDefaults.standard
        let used = defaults.string(forKey: liveDayKey) == today ? defaults.double(forKey: liveSecondsKey) : 0
        return max(Double(freeLiveMinutesPerDay * 60) - used, 0)
    }

    static func recordLiveSeconds(_ seconds: Double) {
        let used = Double(freeLiveMinutesPerDay * 60) - liveSecondsRemainingToday
        let defaults = UserDefaults.standard
        defaults.set(today, forKey: liveDayKey)
        defaults.set(used + seconds, forKey: liveSecondsKey)
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
