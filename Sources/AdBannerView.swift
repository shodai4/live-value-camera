import SwiftUI
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

enum AdsSetup {
    /// Google のテスト用アプリ ID。本番公開前に差し替える。
    static let applicationID = "ca-app-pub-3940256099942544~1458002511"
    /// Google のテスト用バナー ID。本番公開前に差し替える。
    static let bannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    static var isUsingTestIdentifiers: Bool {
        applicationID.contains("3940256099942544") && bannerUnitID.contains("3940256099942544")
    }

    /// 広告の読み込み前に一度だけ呼ぶ。
    static func start() {
        #if canImport(GoogleMobileAds)
        MobileAds.shared.start()
        #endif
    }
}

#if canImport(GoogleMobileAds)
struct AdBannerView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = AdBannerView.hostingController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ view: BannerView, context: Context) {}

    /// 広告のクリックで開く画面の起点。
    private static func hostingController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
#else
struct AdBannerView: View {
    var adUnitID: String = ""
    var body: some View { EmptyView() }
}
#endif
