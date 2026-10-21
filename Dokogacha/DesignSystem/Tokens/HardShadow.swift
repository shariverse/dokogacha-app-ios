//
//  HardShadow.swift
//  Dokogacha
//

import SwiftUI

/// ハードシャドウ: ぼかしのない墨色の影を、角丸の四角で要素の真下にずらして敷く（`04_design_system.md` の §3・§7）。
///
/// SwiftUI の `.shadow` はぼかしが入り、半透明の要素では中身の形に沿って影が出るので使わない。
/// 要素と同じ角丸の四角を背面に置いてずらす。要素に不透明な背景がある前提で、背景が影の四角を覆い、下にずれた分だけが影として見える
/// （背景が透明・半透明だと、影の四角が要素の中まで透けて見える）。
/// 押せる・目立たせたい要素だけに使う（デザインの原則 2）。
struct HardShadow: ViewModifier {
    /// 影の値（ずれ・色）。小さいボタンは `DGShadow.hardSmall`
    var shadow: DGShadow = .hard
    /// 影の四角の角丸。付ける要素の角丸と同じ値にする
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(shadow.color)
                .offset(x: shadow.x, y: shadow.y)
        )
    }
}

extension View {
    /// ハードシャドウを付ける（`HardShadow`）。
    ///
    /// 縁取りや背景を付けた後に呼ぶ（影は要素の背面に敷くため、背景より後ろに来るようにする）。
    /// - Parameters:
    ///   - shadow: 影の値。既定は `DGShadow.hard`（真下に 4）
    ///   - cornerRadius: 付ける要素の角丸
    func dgHardShadow(_ shadow: DGShadow = .hard, cornerRadius: CGFloat) -> some View {
        modifier(HardShadow(shadow: shadow, cornerRadius: cornerRadius))
    }
}

#Preview("HardShadow") {
    VStack(spacing: DGSpacing.s24) {
        Text(verbatim: "shadow.hard")
            .font(.dg(.bodyButton))
            .foregroundStyle(Color.dgTextOnAccent)
            .frame(width: 240, height: 56)
            .background(Color.dgAccentPrimary, in: RoundedRectangle(cornerRadius: DGRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: DGRadius.lg).strokeBorder(Color.dgInk, lineWidth: DGBorder.strong))
            .dgHardShadow(cornerRadius: DGRadius.lg)
        Text(verbatim: "shadow.hardSmall")
            .font(.dgBody(14, weight: .black))
            .foregroundStyle(Color.dgInk)
            .frame(width: 160, height: 40)
            .background(Color.dgAccentSecondary, in: RoundedRectangle(cornerRadius: DGRadius.sm))
            .overlay(RoundedRectangle(cornerRadius: DGRadius.sm).strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
            .dgHardShadow(.hardSmall, cornerRadius: DGRadius.sm)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}
