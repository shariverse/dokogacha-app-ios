//
//  DGLogo.swift
//  Dokogacha
//
//  ロゴ（カプセルのアイコン＋「ドコガチャ」＋サブタイトル）。
//  03 の S-01 の 1 と S-02 の 1 の「ロゴエリア」、プロトタイプ（`Main.dc.html`）のホームの見出しの形。
//

import SwiftUI

/// ロゴ。カプセルのアイコン（34）と「ドコガチャ」（`display.xl`）を横に並べ、下にサブタイトル（本文 Bold 13・`text.secondary`）を置く。
///
/// S-01（オンボーディング）・S-02（ホーム）・起動中の表示で同じものを使う。
/// VoiceOver では 1 つの見出しとして「ドコガチャ、友達旅行・おでかけの行き先ガチャ」と読む（カプセルは飾りなので読まない）。
struct DGLogo: View {
    /// カプセルのアイコンの直径（03 の S-01「カプセルアイコン34pt」）
    static let capsuleSize: CGFloat = 34
    /// カプセルのアイコンの縁の太さ（プロトタイプの `border: 3px`）
    private static let capsuleLineWidth: CGFloat = 3
    /// サブタイトルの文字の大きさ（03 の S-02「本文13pt bold」）
    private static let subtitleSize: CGFloat = 13

    /// カプセルのアイコンを、見出しと一緒に Dynamic Type で大きくする
    @ScaledMetric(relativeTo: .largeTitle) private var capsuleSize = DGLogo.capsuleSize

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s6) {
            HStack(spacing: DGSpacing.s10) {
                CapsuleBall(color: .dgAccentPrimary, lineWidth: Self.capsuleLineWidth)
                    .frame(width: capsuleSize, height: capsuleSize)
                    .accessibilityHidden(true)
                Text("ドコガチャ")
                    .font(.dg(.displayXL))
                    .foregroundStyle(Color.dgInk)
            }
            Text("友達旅行・おでかけの行き先ガチャ")
                .font(.dgBody(Self.subtitleSize, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Logo") {
    VStack(alignment: .leading, spacing: DGSpacing.s24) {
        DGLogo()
        DGLogo()
            .dynamicTypeSize(.accessibility5)
    }
    .padding(DGSpacing.screenX)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.dgBgBase)
}
