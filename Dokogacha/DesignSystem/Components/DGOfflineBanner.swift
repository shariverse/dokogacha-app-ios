//
//  DGOfflineBanner.swift
//  Dokogacha
//
//  「オフラインです」のバナー（02 の §9「オフライン時は「オフラインです」バナー」）。
//  03・04 に位置と見た目の決まりが無いので、トースト（04 の §4 の Toast）と同じ `ink` の地に、
//  AdFreeNotice と同じ 12 Bold の文字で、画面の上端（ヘッダーの上）に帯で出す。
//

import SwiftUI

/// 端末がオフラインのときに画面の上端に出す帯。
///
/// 背景 `ink`・文字 `text.onInk` 12 Bold・上下 8・左右 16。文字が大きいときは折り返して高さが伸びる。
/// 閲覧はキャッシュでできるので、画面は塞がない（02 の §9）。
struct DGOfflineBanner: View {
    /// UI テストが探す ID
    static let identifier = "offline.banner"

    /// アイコンを Dynamic Type に合わせて大きくする倍率
    @ScaledMetric(relativeTo: .caption) private var iconScale: CGFloat = 1
    /// アイコンの一辺
    private static let iconSize: CGFloat = 14

    var body: some View {
        HStack(spacing: DGSpacing.s6) {
            Image(systemName: "wifi.slash")
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSize * iconScale, height: Self.iconSize * iconScale)
                .accessibilityHidden(true)
            Text("オフラインです")
                .font(.dgBody(12, weight: .bold, relativeTo: .caption))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.dgTextOnInk)
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.vertical, DGSpacing.s8)
        .frame(maxWidth: .infinity)
        .background(Color.dgInk)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.identifier)
    }
}

#Preview("OfflineBanner") {
    VStack(spacing: DGSpacing.s16) {
        DGOfflineBanner()
        DGOfflineBanner()
            .dynamicTypeSize(.accessibility5)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.dgBgBase)
}
