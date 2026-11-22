import Foundation
import StoreKit

/// 買い切りの広告非表示（Pro）を扱う土台。
/// 商品がまだ App Store Connect に無い間は、価格が「準備中」のままで購入ボタンは押せない。
@MainActor
final class ProStore: ObservableObject {
    static let productID = "com.shodai4.livevaluecamera.pro"

    @Published private(set) var isPro: Bool
    @Published private(set) var displayPrice: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?

    private let defaultsKey = "livevaluecamera.pro.unlocked"
    private var updatesTask: Task<Void, Never>?

    init() {
        isPro = UserDefaults.standard.bool(forKey: defaultsKey)
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await loadProduct() }
        Task { await refreshEntitlements() }
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            displayPrice = products.first?.displayPrice
        } catch {
            displayPrice = nil
        }
    }

    func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        message = nil

        do {
            guard let product = try await Product.products(for: [Self.productID]).first else {
                message = "購入項目を読み込めませんでした。時間をおいて試してください。"
                return
            }
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    unlock(true)
                } else {
                    message = "購入を確認できませんでした。"
                }
            case .userCancelled:
                break
            case .pending:
                message = "購入は承認待ちです。"
            @unknown default:
                break
            }
        } catch {
            message = "購入に失敗しました。時間をおいて試してください。"
        }
    }

    func restore() async {
        message = nil
        do {
            try await AppStore.sync()
        } catch {
            message = "購入の復元に失敗しました。"
            return
        }
        await refreshEntitlements()
        if !isPro {
            message = "購入の記録が見つかりませんでした。"
        }
    }

    private func refreshEntitlements() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                unlock(true)
                return
            }
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            unlock(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func unlock(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }
}
