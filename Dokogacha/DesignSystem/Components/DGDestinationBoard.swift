//
//  DGDestinationBoard.swift
//  Dokogacha
//
//  行き先表示の黒帯（`04_design_system.md` の §4 の DestinationBoard・03 の S-02・S-07）。
//

import SwiftUI

/// 駅の行き先表示に見立てた黒帯。「行き先」＋「？？？」と、右端に「カプセル N個」を出す。
///
/// 背景 `ink`・角丸 12。「行き先」は 11 Bold の `text.onInk`、「？？？」は見出し 22（`display.m`）の `accent.secondary` で字間 0.2em、
/// 「カプセル N個」は 12 の `text.onInk` で、数字だけ `accent.secondary` の 15 Bold。
/// ホームの RoomTagCard の中に置くもの（`.inline`）と、ルームパネルの上部に置くもの（`.cardTop`。上だけ角丸）がある。
/// 文字が大きくて 1 行に収まらないときは、「カプセル N個」を下の行に回す。
struct DGDestinationBoard: View {
    /// 置き場所
    nonisolated enum Placement: CaseIterable, Sendable {
        /// カードの中に置く（ホームの RoomTagCard）。四隅を角丸にする
        case inline
        /// カードの上部に置く（S-07 のルームパネル）。上だけ角丸にする
        case cardTop

        /// 左右の余白（04 の §4「左右14〜16」）
        var horizontalPadding: CGFloat {
            switch self {
            case .inline: DGSpacing.s14
            case .cardTop: DGSpacing.s16
            }
        }

        /// 上下の余白（04 の §4「上下10〜12」）
        var verticalPadding: CGFloat {
            switch self {
            case .inline: DGSpacing.s10
            case .cardTop: DGSpacing.s12
            }
        }
    }

    /// 角丸
    private static let cornerRadius: CGFloat = DGRadius.sm
    /// 「行き先」の文字の大きさ
    private static let labelSize: CGFloat = 11
    /// カプセルの数の文字の大きさ
    private static let countSize: CGFloat = 15
    /// 行き先が決まっていないときの表示（03 の表記）
    private static let undecided = "？？？"

    /// ルームにあるカプセル（候補）の数
    let capsuleCount: Int
    /// 置き場所
    var placement: Placement = .inline

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s10) {
                destination
                Spacer(minLength: 0)
                capsules
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                destination
                capsules
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, placement.horizontalPadding)
        .padding(.vertical, placement.verticalPadding)
        .background(Color.dgInk, in: shape)
        .accessibilityElement(children: .combine)
    }

    /// 置き場所に合わせた背景の形
    private var shape: UnevenRoundedRectangle {
        let bottom: CGFloat = placement == .inline ? Self.cornerRadius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: Self.cornerRadius
        )
    }

    /// 「行き先 ？？？」
    private var destination: some View {
        HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s10) {
            Text("行き先")
                .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Color.dgTextOnInk)
            Text(verbatim: Self.undecided)
                .font(.dg(.displayM))
                .tracking(DGTracking.points(DGTracking.destination, fontSize: DGTypeScale.displayM.size))
                .foregroundStyle(Color.dgAccentSecondary)
                .lineLimit(1)
                .accessibilityLabel(Text("未定"))
        }
    }

    /// 「カプセル N個」（数字だけ黄色の 15 Bold）
    private var capsules: some View {
        let count = Text(verbatim: "\(capsuleCount)")
            .font(.dgBody(Self.countSize, weight: .bold, relativeTo: .caption))
            .foregroundStyle(Color.dgAccentSecondary)
        return Text("カプセル \(count)個")
            .font(.dg(.bodyCaption))
            .foregroundStyle(Color.dgTextOnInk)
    }
}

#Preview("DestinationBoard 置き場所ごと") {
    VStack(spacing: DGSpacing.s24) {
        DGDestinationBoard(capsuleCount: 8)
        DGDestinationBoard(capsuleCount: 0)
        DGDestinationBoard(capsuleCount: 12, placement: .cardTop)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("DestinationBoard 文字を最大") {
    VStack(spacing: DGSpacing.s24) {
        DGDestinationBoard(capsuleCount: 8)
        DGDestinationBoard(capsuleCount: 12, placement: .cardTop)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
    .dynamicTypeSize(.accessibility5)
}
