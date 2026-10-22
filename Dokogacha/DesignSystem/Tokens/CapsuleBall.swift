//
//  CapsuleBall.swift
//  Dokogacha
//

import SwiftUI

/// カプセル: 上半分を候補の色、下半分を白に塗り分けた円（`04_design_system.md` の §7）。
///
/// グラデーションで面を塗らない原則（デザインの原則 5）の唯一の例外。
/// 位置 0.5 で色が切り替わる 2 つの区切りだけの `LinearGradient` にして、ぼかさずに 2 色に分ける。
/// 大きさは呼び出し側の `.frame` で決める（ドームの中は直径 40、取り出し口から出てくるものは直径 60）。
/// 縁は `strokeBorder` で内側に描くので、`.frame` の大きさからはみ出さない。
struct CapsuleBall: View {
    /// 上半分の色（`Color.dgCapsule(at:)` で選んだ候補の色）
    let color: Color
    /// 縁の色。ドームの中は墨色、取り出し口から出てくるものは白
    var strokeColor: Color = .dgInk
    /// 縁の太さ。ドームの中は 3、取り出し口から出てくるものは 4
    var lineWidth: CGFloat = 3

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: color, location: 0.5),
                        .init(color: .dgSurfaceCard, location: 0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(Circle().strokeBorder(strokeColor, lineWidth: lineWidth))
    }
}

#Preview("CapsuleBall") {
    VStack(spacing: DGSpacing.s24) {
        HStack(spacing: DGSpacing.s12) {
            ForEach(Color.dgCapsules.indices, id: \.self) { index in
                CapsuleBall(color: .dgCapsule(at: index))
                    .frame(width: 40, height: 40)
            }
        }
        CapsuleBall(color: .dgCapsule(at: 0), strokeColor: .dgSurfaceCard, lineWidth: 4)
            .frame(width: 60, height: 60)
            .padding(DGSpacing.s16)
            .background(Color.dgInk, in: RoundedRectangle(cornerRadius: DGRadius.md))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}
