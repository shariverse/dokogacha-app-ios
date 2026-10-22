//
//  GoogleBannerAdView.swift
//  Dokogacha
//

@preconcurrency import GoogleMobileAds
import SwiftUI

/// Google Mobile Ads のアンカー型アダプティブバナー（02 の F-50）を SwiftUI に置く。
///
/// 幅は置いた場所の幅に合わせ、高さは SDK が幅から決める（`largeAnchoredAdaptiveBanner`。03 の §3「目安50pt」）。
/// 読み込めるまでは `surface.ad` の枠で場所を取っておき（読み込めた瞬間に下のボタンが押し上がらないように）、
/// 読み込めなかったら（オフライン・在庫なし）場所ごと消す。
struct GoogleBannerAdView: View {
    /// 広告ユニット ID
    let adUnitID: String
    /// リクエストに足すパラメータ（ATT で許可していなければ非パーソナライズの `npa`）
    let requestParameters: [String: String]

    /// 置いた場所の幅（測るまでは 0）
    @State private var width: CGFloat = 0
    /// 読み込めなかった
    @State private var didFail = false

    var body: some View {
        if !didFail {
            Color.dgSurfaceAd
                .frame(height: width > 0 ? Self.adSize(width: width).size.height : 0)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    width = newWidth
                }
                .overlay {
                    if width > 0 {
                        BannerRepresentable(
                            adSize: Self.adSize(width: width),
                            adUnitID: adUnitID,
                            requestParameters: requestParameters
                        ) {
                            didFail = true
                        }
                    }
                }
                .clipped()
        }
    }

    /// 幅から決まるバナーの大きさ（同じ幅なら同じ高さ）
    private static func adSize(width: CGFloat) -> AdSize {
        largeAnchoredAdaptiveBanner(width: width)
    }
}

/// SDK の `BannerView` を包む。大きさ（幅）かリクエストのパラメータ（ATT の答え）が変わったら読み込み直す
private struct BannerRepresentable: UIViewRepresentable {
    let adSize: AdSize
    let adUnitID: String
    let requestParameters: [String: String]
    /// 読み込めなかった
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        load(banner)
        context.coordinator.loaded = conditions
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        context.coordinator.onFailure = onFailure
        guard conditions.needsReload(since: context.coordinator.loaded) else {
            return
        }
        if banner.adSize.size.width != adSize.size.width {
            banner.adSize = adSize
        }
        load(banner)
        context.coordinator.loaded = conditions
    }

    /// いまの読み込みの条件
    private var conditions: BannerLoadConditions {
        BannerLoadConditions(width: Double(adSize.size.width), requestParameters: requestParameters)
    }

    /// 置いた場所（SwiftUI が決めた幅とバナーの高さ）に収める。SDK のビューの intrinsicContentSize（広告の素材の大きさ）に
    /// 合わせると、枠からはみ出して下のボタンに重なる
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BannerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? adSize.size.width, height: proposal.height ?? adSize.size.height)
    }

    /// リクエストを作って読み込む。非パーソナライズは `Extras` の追加のパラメータで求める
    private func load(_ banner: BannerView) {
        let request = Request()
        if !requestParameters.isEmpty {
            let extras = Extras()
            extras.additionalParameters = requestParameters
            request.register(extras)
        }
        banner.load(request)
    }

    /// 読み込みの結果を受ける（SDK は delegate を main thread で呼ぶ。`NS_SWIFT_UI_ACTOR`）
    final class Coordinator: NSObject, BannerViewDelegate {
        /// 読み込めなかったときに呼ぶ
        var onFailure: () -> Void
        /// 最後に読み込んだときの条件（幅とリクエストのパラメータ）
        var loaded: BannerLoadConditions?

        init(onFailure: @escaping () -> Void) {
            self.onFailure = onFailure
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
            onFailure()
        }
    }
}
