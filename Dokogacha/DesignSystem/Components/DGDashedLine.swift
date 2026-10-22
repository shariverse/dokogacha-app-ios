//
//  DGDashedLine.swift
//  Dokogacha
//
//  カード・きっぷの点線の区切り（`04_design_system.md` の §4 の CandidateCard・TicketStub・DestinationTicket）。
//

import SwiftUI

/// 横または縦に 1 本引く点線の区切り。
///
/// CandidateCard の区切り（2pt `line.dashed`）、TicketStub・行き先きっぷの切り取り線（2pt `line.dashedStrong`）で使う。
/// 線の太さ分の大きさを自分で取るので、`.frame` で長さを決めなくても並べられる。飾りなので VoiceOver では読まない。
struct DGDashedLine: View {
    /// 線を引く向き
    nonisolated enum Axis: Sendable {
        /// 横（区切り）
        case horizontal
        /// 縦（きっぷの半券の境目）
        case vertical
    }

    /// 点線の線と隙間の長さ（CSS の `dashed` の見た目に合わせる。`DGButtonKind.dashed` と同じ）
    private static let dashPattern: [CGFloat] = [6, 4]

    /// 線の色
    var color: Color = .dgLineDashed
    /// 線の太さ
    var lineWidth: CGFloat = DGBorder.regular
    /// 線を引く向き
    var axis: Axis = .horizontal

    var body: some View {
        DashedLineShape(axis: axis)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: Self.dashPattern))
            .frame(
                width: axis == .vertical ? lineWidth : nil,
                height: axis == .horizontal ? lineWidth : nil
            )
            .accessibilityHidden(true)
    }
}

/// 枠の中央を通る 1 本の線の形。
private struct DashedLineShape: Shape {
    let axis: DGDashedLine.Axis

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch axis {
        case .horizontal:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .vertical:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

#Preview("DashedLine") {
    VStack(spacing: DGSpacing.s24) {
        DGDashedLine()
        DGDashedLine(color: .dgLineDashedStrong)
        DGDashedLine(color: .dgLineDashedStrong, axis: .vertical)
            .frame(height: 80)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}
