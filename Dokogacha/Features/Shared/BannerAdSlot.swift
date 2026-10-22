//
//  BannerAdSlot.swift
//  Dokogacha
//

import SwiftUI

/// 画面の最下部に置くバナー広告の場所（02 の F-50・03 の §3「画面最下部、セーフエリアの上に固定。左右16pt、下14pt の余白」）。
///
/// 出すかは `AdCoordinator.shouldShowAds(on:room:)`（05 の §8）で決め、出さないときは場所も取らない。
/// 起動のしかた（`AdMode`）ごとに、本物のバナー（`GoogleBannerAdView`）・撮影モードの固定の枠（`DGAdPlaceholder`）・何も出さない（テスト）を選ぶ。
/// 画面の下のボタンとは縦に並べて置くので重ならない（`safeAreaInset` の中でボタンの下に置く）
struct BannerAdSlot: View {
    /// UI テスト・撮影で探す ID
    static let identifier = "ad.banner"

    /// 置く画面
    let screen: AdScreen
    /// 開いているルーム（ルーム・候補を追加のとき。購入者がいれば出さない。届くまでの nil のあいだも出さない）
    var room: Room?

    /// 広告のまとめ役（`DokoGachaApp` が渡す。プレビューでは無い）
    @Environment(AdCoordinator.self) private var ads: AdCoordinator?

    var body: some View {
        if let ads, ads.shouldShowAds(on: screen, room: room) {
            content(ads)
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.bottom, DGSpacing.s14)
                .frame(maxWidth: .infinity)
                .background(Color.dgBgBase)
                .accessibilityIdentifier(Self.identifier)
        }
    }

    /// 起動のしかたごとの中身
    @ViewBuilder
    private func content(_ ads: AdCoordinator) -> some View {
        switch ads.mode {
        case let .live(adUnitID):
            GoogleBannerAdView(adUnitID: adUnitID, requestParameters: ads.requestParameters)
        case .placeholder:
            DGAdPlaceholder()
        case .disabled:
            EmptyView()
        }
    }
}
