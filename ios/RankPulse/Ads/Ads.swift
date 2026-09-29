@preconcurrency import AppTrackingTransparency
@preconcurrency import GoogleMobileAds
import SwiftUI
@preconcurrency import UserMessagingPlatform

/// Handles ad consent and SDK start-up. Order matters:
/// 1. Google's consent form (shown only where the law requires it, e.g. EU/UK)
/// 2. Apple's App Tracking Transparency prompt
/// 3. Start the Mobile Ads SDK — ads are only requested after this.
@MainActor
@Observable
final class AdsManager {
    private(set) var ready = false
    private var started = false

    func start() async {
        guard !started else { return }
        started = true

        let consent = ConsentInformation.shared
        do {
            try await consent.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: Self.rootViewController())
        } catch {
            // No form configured yet (e.g. test IDs) or offline: fall back to
            // whatever consent state we already have.
        }
        guard consent.canRequestAds else { return }

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await MobileAds.shared.start()
        ready = true
    }

    /// Lets users revisit their privacy choices (required where the consent
    /// form applies).
    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: Self.rootViewController())
    }

    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
    }
}

/// A Google banner ad. `inline` banners go between list rows; the default
/// anchored banner sits at the bottom of the screen.
struct BannerAd: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    var inline = false
    var onLoad: ((Bool) -> Void)? = nil

    // In-list ads are a fixed 320×100. The bottom banner uses the standard
    // adaptive size: the newer "large" size is about twice as tall.
    var size: AdSize {
        inline ? AdSizeLargeBanner : currentOrientationAnchoredAdaptiveBanner(width: width)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLoad: onLoad) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = adUnitID
        banner.rootViewController = AdsManager.rootViewController()
        banner.delegate = context.coordinator
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        let onLoad: ((Bool) -> Void)?
        init(onLoad: ((Bool) -> Void)?) { self.onLoad = onLoad }
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { onLoad?(true) }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) { onLoad?(false) }
    }
}

/// Bottom banner shown above the tab bar once ads are allowed.
struct BottomBannerAd: View {
    @Environment(AdsManager.self) private var ads
    @Environment(PremiumStore.self) private var premium

    var body: some View {
        if ads.ready && !premium.isPremium {  // Premium removes all ads
            GeometryReader { proxy in
                BannerAd(adUnitID: Config.bannerAdUnitID, width: proxy.size.width)
                    .frame(width: proxy.size.width, height: currentOrientationAnchoredAdaptiveBanner(width: proxy.size.width).size.height)
            }
            .frame(height: currentOrientationAnchoredAdaptiveBanner(width: UIScreen.main.bounds.width).size.height)
            .background(.bar)
            .accessibilityLabel("Advertisement")
        }
    }
}

/// An ad placed between rows of a list, labelled so it's clearly not a match.
struct InlineAdRow: View {
    @Environment(AdsManager.self) private var ads
    @Environment(PremiumStore.self) private var premium
    @State private var failed = false
    private let width: CGFloat = 320

    var body: some View {
        if ads.ready && !failed && !premium.isPremium {
            // Full size while loading (a hidden banner never renders); removed if no ad arrives.
            VStack(alignment: .leading, spacing: 4) {
                Text("SPONSORED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.secondary)
                BannerAd(adUnitID: Config.inlineAdUnitID, width: width, inline: true) { ok in
                    Task { @MainActor in failed = !ok }
                }
                .frame(width: width, height: 100)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Advertisement")
        }
    }
}
