//
//  Metrics.swift
//  Dokogacha
//
//  `docs/spec/design/tokens.json` の `radius`・`border`・`shadow`・`spacing`・`minTapTarget` を写した寸法のトークン。
//  単位はすべて pt（`04_design_system.md` の §3）。
//

import SwiftUI

/// 角丸の半径（`radius`）。
///
/// 04 の §3 は「6〜8」のように幅で書いてあるので、tokens.json の値を既定にする。
/// SwiftLint の `identifier_name`（2 文字以上）に合わせ、`s`・`m`・`l` は `sm`・`md`・`lg` と名付けている。
/// 部品の表（04 の §4）で別の値が決まっているものは、その部品で値を持つ。
nonisolated enum DGRadius {
    /// バッジ、チップ（`radius.xs`）
    static let xs: CGFloat = 6
    /// 小ボタン、タブ、小さいタイル（`radius.s`）
    static let sm: CGFloat = 12
    /// 入力欄、ボタン、PlaceRow、カテゴリタイル（`radius.m`）
    static let md: CGFloat = 16
    /// カード、主ボタン、ルームパネル（`radius.l`）
    static let lg: CGFloat = 20
    /// 状態チップ、アバター（`radius.pill`。高さの半分より大きければ丸くなる）
    static let pill: CGFloat = 999
}

/// 線の太さ（`border`）。色はどれも `Color.dgInk`。
nonisolated enum DGBorder {
    /// 主要なカード・ボタンの縁（`border.regular`）
    static let regular: CGFloat = 2
    /// 目立たせたいカード・主ボタンの縁（`border.strong`）
    static let strong: CGFloat = 2.5
    /// ガチャの筐体（ドーム・本体・レバー）の縁（`border.machine`）
    static let machine: CGFloat = 5
}

/// 余白と間隔（`spacing`）。
nonisolated enum DGSpacing {
    /// 画面の左右の余白（`spacing.screenX`）
    static let screenX: CGFloat = 16
    /// カード内の余白（`spacing.cardPadding`）
    static let cardPadding: CGFloat = 14
    /// 人気カードの上の余白（04 の §3「人気カードは上だけ 20」。リボンが重なるため広い）
    static let popularCardTopPadding: CGFloat = 20

    /// 要素間の間隔の段（`spacing.scale`）。この中から選び、ほかの値を使わない
    static let scale: [CGFloat] = [s4, s6, s8, s10, s12, s14, s16, s22, s24]

    /// 間隔 4
    static let s4: CGFloat = 4
    /// 間隔 6
    static let s6: CGFloat = 6
    /// 間隔 8
    static let s8: CGFloat = 8
    /// 間隔 10
    static let s10: CGFloat = 10
    /// 間隔 12
    static let s12: CGFloat = 12
    /// 間隔 14
    static let s14: CGFloat = 14
    /// 間隔 16
    static let s16: CGFloat = 16
    /// 間隔 22
    static let s22: CGFloat = 22
    /// 間隔 24
    static let s24: CGFloat = 24
}

/// そのほかの寸法。
nonisolated enum DGMetrics {
    /// 最小のタップ領域の一辺（`minTapTarget`。44×44）
    static let minTapTarget: CGFloat = 44
}

/// ハードシャドウ（ぼかしのない影）の値（`shadow`）。
///
/// 描くときは `HardShadow`（`View.dgHardShadow(_:cornerRadius:)`）を使う。
nonisolated struct DGShadow: Sendable {
    /// 横のずれ（pt）
    let x: CGFloat
    /// 縦のずれ（pt。正の値で下へ）
    let y: CGFloat
    /// ぼかしの半径（ハードシャドウなので 0）
    let blur: CGFloat
    /// 影の色
    let color: Color

    /// 押せる・目立たせたい要素の影（`shadow.hard`。真下に 4）
    static let hard = DGShadow(x: 0, y: 4, blur: 0, color: .dgInk)
    /// 小さいボタンの影（`shadow.hardSmall`。真下に 3）
    static let hardSmall = DGShadow(x: 0, y: 3, blur: 0, color: .dgInk)
    /// 押している間のボタンの影（04 の §4 の Button「押下時：影を y 1 に縮める」。tokens.json には無い）
    static let pressed = DGShadow(x: 0, y: 1, blur: 0, color: .dgInk)
}
