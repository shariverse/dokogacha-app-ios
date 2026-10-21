//
//  DGStatusChip.swift
//  Dokogacha
//
//  ルームの状態チップ（`04_design_system.md` の §4 の StatusChip・§1 の「状態チップ」）。
//

import SwiftUI

/// ルームの状態を表すチップ（「候補募集中」「ガチャ解禁！」「行き先決定」「終了」）。
///
/// 高さ約 22・左右 10・角丸 pill・本文 Bold 12。文字が大きくなったら高さが伸びる。
struct DGStatusChip: View {
    /// チップで表すルームの状態。
    ///
    /// ルームの状態（`Domain/Models` の `RoomStatus`）からは `init(_:)` で作る。
    nonisolated enum Status: CaseIterable, Sendable {
        /// 候補募集中（`open`）
        case open
        /// ガチャ解禁！（`unlocked`）
        case unlocked
        /// 行き先決定（`drawn`）
        case drawn
        /// 終了（`closed`）
        case closed

        /// ルームの状態に対応するチップの状態を作る（4 つの状態が 1 対 1 で対応する）。
        /// - Parameter status: ルームの状態
        init(_ status: RoomStatus) {
            switch status {
            case .open: self = .open
            case .unlocked: self = .unlocked
            case .drawn: self = .drawn
            case .closed: self = .closed
            }
        }

        /// チップの文言（04 の §1 の表記）
        var label: LocalizedStringResource {
            switch self {
            case .open: "候補募集中"
            case .unlocked: "ガチャ解禁！"
            case .drawn: "行き先決定"
            case .closed: "終了"
            }
        }

        /// チップの背景と文字の色
        var colors: DGColorPair {
            switch self {
            case .open: DGStatusColors.open
            case .unlocked: DGStatusColors.unlocked
            case .drawn: DGStatusColors.drawn
            case .closed: DGStatusColors.closed
            }
        }
    }

    /// チップの最小の高さ（04 の §4「高さ約22」）
    private static let minHeight: CGFloat = 22
    /// 文字の上下の余白（プロトタイプの値）
    private static let verticalPadding: CGFloat = 3

    /// 表す状態
    let status: Status

    var body: some View {
        Text(status.label)
            .font(.dgBody(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(status.colors.foreground)
            .padding(.horizontal, DGSpacing.s10)
            .padding(.vertical, Self.verticalPadding)
            .frame(minHeight: Self.minHeight)
            .background(status.colors.background, in: RoundedRectangle(cornerRadius: DGRadius.pill))
    }
}

#Preview("StatusChip 状態ごと") {
    VStack(spacing: DGSpacing.s12) {
        ForEach(DGStatusChip.Status.allCases, id: \.self) { status in
            DGStatusChip(status: status)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("StatusChip 文字を最大") {
    VStack(spacing: DGSpacing.s12) {
        ForEach(DGStatusChip.Status.allCases, id: \.self) { status in
            DGStatusChip(status: status)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
