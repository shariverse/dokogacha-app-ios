//
//  AdFreeNoticeSlot.swift
//  Dokogacha
//

import SwiftUI

/// バナー広告の代わりに画面の最下部に置く「（王冠）◯◯さんのおかげで、このルームは広告なし」（03 の S-07・02 の §7.2 F-51）。
///
/// 出すかと名前は `AdFreeNoticePolicy`（ルームの画面で、ルームに購入者がいるとき）で決め、出さないときは場所も取らない。
/// 広告ではないので、広告を読み込まない起動（テスト・撮影モード）でも出す。
/// 置き方はバナー（`BannerAdSlot`）と同じ（左右 16pt・下 14pt の余白。03 の §3）。購入者がいるルームではバナーは出ないので、2 つは重ならない
struct AdFreeNoticeSlot: View {
    /// UI テスト・撮影で探す ID
    static let identifier = "ad.freeNotice"

    /// 置く画面
    let screen: AdScreen
    /// 開いているルーム（届くまでの nil のあいだは出さない）
    var room: Room?

    var body: some View {
        if let name = AdFreeNoticePolicy.sponsorName(screen: screen, room: room) {
            DGAdFreeNotice(sponsorName: name)
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.bottom, DGSpacing.s14)
                .frame(maxWidth: .infinity)
                .background(Color.dgBgBase)
                .accessibilityIdentifier(Self.identifier)
        }
    }
}
