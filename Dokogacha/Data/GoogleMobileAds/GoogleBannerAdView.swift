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
/// 読み込めなかったら（オフライン・在庫なし）`didFail` を立てる。置いた側（`BannerAdSlot`）が余白ごと場所を消し、
/// 回線が戻ったら `didFail` を下ろして読み込み直す（PR #89 の持ち越し）。
///
/// iPad でウィンドウの大きさを変えている間（Split View・Stage Manager）は幅が続けて変わるので、そのたびには読み込み直さず、
/// 幅が `resizeSettleDelay` のあいだ変わらなくなってから、その幅で読み込み直す（広告のリクエストを続けて送らない）。最初の 1 回はすぐに読み込む
struct GoogleBannerAdView: View {
    /// 幅が変わってから読み込み直すまでの待ち時間
    private static let resizeSettleDelay: Duration = .milliseconds(500)

    /// 広告ユニット ID
    let adUnitID: String
    /// リクエストに足すパラメータ（ATT で許可していなければ非パーソナライズの `npa`）
    let requestParameters: [String: String]
    /// 読み込めなかったか（置いた側が持つ。下ろすと読み込み直す）
    @Binding var didFail: Bool

    /// 置いた場所の幅（測るまでは 0。ウィンドウの大きさを変えている間も追いかける）
    @State private var width: CGFloat = 0
    /// 広告を読み込む幅（最初に測るまでは 0）。幅が落ち着いてから `width` に合わせる
    @State private var loadWidth: CGFloat = 0

    var body: some View {
        if !didFail {
            Color.dgSurfaceAd
                .frame(height: loadWidth > 0 ? Self.adSize(width: loadWidth).size.height : 0)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    width = newWidth
                }
                .task(id: width) {
                    await settleLoadWidth()
                }
                .overlay {
                    if loadWidth > 0 {
                        BannerRepresentable(
                            adSize: Self.adSize(width: loadWidth),
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

    /// 広告を読み込む幅を、いまの幅に合わせる。2 回目からは幅が落ち着くまで待つ（待っている間に幅が変われば、この待ちは取り消される）
    private func settleLoadWidth() async {
        guard width > 0, width != loadWidth else {
            return
        }
        if loadWidth > 0 {
            try? await Task.sleep(for: Self.resizeSettleDelay)
            guard !Task.isCancelled else {
                return
            }
        }
        loadWidth = width
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
