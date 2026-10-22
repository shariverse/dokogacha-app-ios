//
//  DGAdFreeNotice.swift
//  Dokogacha
//
//  広告なしのメッセージ（`04_design_system.md` の §4 の AdFreeNotice・03 の S-07・02 の F-51）。
//

import SwiftUI

/// 広告非表示を買った人がいるルームで、バナー広告の代わりに画面の最下部に出すメッセージ。
///
/// 「（王冠）◯◯さんのおかげで、このルームは広告なし」。高さ 40・角丸 20・背景 `accent.pale`・文字 `accent.paleText` 12 Bold・王冠 16。
/// 誰の名前を出すか（購入者が複数いるときは最初に参加した人）は呼び出し側で決める。文字が大きくなったら折り返して高さが伸びる。
struct DGAdFreeNotice: View {
    /// 最小の高さ
    private static let minHeight: CGFloat = 40
    /// 角丸
    private static let cornerRadius: CGFloat = DGRadius.lg
    /// 王冠のアイコンの一辺
    private static let crownSize: CGFloat = 16

    /// 広告非表示を買ったメンバーの表示名
    let sponsorName: String

    /// 王冠を Dynamic Type に合わせて大きくする倍率
    @ScaledMetric(relativeTo: .caption) private var iconScale: CGFloat = 1

    var body: some View {
        HStack(spacing: DGSpacing.s6) {
            Image("ui-crown")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: Self.crownSize * iconScale, height: Self.crownSize * iconScale)
                .accessibilityHidden(true)
            Text("\(sponsorName)さんのおかげで、このルームは広告なし")
                .font(.dgBody(12, weight: .bold, relativeTo: .caption))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.dgAccentPaleText)
        .padding(.horizontal, DGSpacing.s16)
        .padding(.vertical, DGSpacing.s8)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight)
        .background(Color.dgAccentPale, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

#Preview("AdFreeNotice") {
    VStack(spacing: DGSpacing.s16) {
        DGAdFreeNotice(sponsorName: "けんた")
        DGAdFreeNotice(sponsorName: "とても長い表示名の人")
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("AdFreeNotice 文字を最大") {
    DGAdFreeNotice(sponsorName: "けんた")
        .padding(DGSpacing.screenX)
        .frame(maxHeight: .infinity)
        .background(Color.dgBgBase)
        .dynamicTypeSize(.accessibility5)
}
