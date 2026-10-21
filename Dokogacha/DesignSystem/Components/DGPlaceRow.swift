//
//  DGPlaceRow.swift
//  Dokogacha
//
//  場所の行（`04_design_system.md` の §4 の PlaceRow）。S-08 の検索結果と過去のアイデアで使う。
//

import SwiftUI

/// カテゴリタイル・場所名・メタ情報と、右端の操作ボタン（「追加」「持ち込む」など）を並べた行。
///
/// 白・線 2・角丸 16・余白 上下 10／左右 12。タイル 42、場所名 15 Black、メタ 12。
/// 右のボタンは高さ 40・最小幅 72・角丸 12・線 2（有効 `accent.secondary`、無効 `surface.disabled`）。
/// ボタンの見た目は 40 だが、上下 2 ずつタップ領域を広げて 44 にしている。
struct DGPlaceRow: View {
    /// 行の角丸
    private static let cornerRadius: CGFloat = DGRadius.md
    /// 右のボタンの高さ
    private static let actionHeight: CGFloat = 40
    /// 右のボタンの最小の幅
    private static let actionMinWidth: CGFloat = 72
    /// 場所名の大きさ
    private static let nameFontSize: CGFloat = 15
    /// バッジ（「前回惜しかった」）の上下の余白（プロトタイプの値）
    private static let badgeVerticalPadding: CGFloat = 2

    /// 場所名
    let name: String
    /// メタ情報（「エリア · カテゴリ」「エリア · カテゴリ · 前回 N いいね」）
    let meta: String
    /// カテゴリ（タイルの色とアイコン）
    let category: DGCategoryStyle
    /// 場所名の横に出すバッジ（「前回惜しかった」）。無ければ `nil`
    var badge: LocalizedStringKey?
    /// 右のボタンの文言（「追加」「追加済み」「上限」「持ち込む」）
    let actionTitle: LocalizedStringKey
    /// 右のボタンを押せるか（「追加済み」「上限」のときは押せない）
    var isActionEnabled: Bool = true
    /// 右のボタンを押したときの処理
    let action: () -> Void

    var body: some View {
        HStack(spacing: DGSpacing.s12) {
            DGCategoryTile(category: category)
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                titleLine
                Text(verbatim: meta)
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            actionButton
        }
        .padding(.vertical, DGSpacing.s10)
        .padding(.horizontal, DGSpacing.s12)
        .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
        .accessibilityElement(children: .contain)
    }

    /// 場所名と、あればバッジ（狭いときはバッジを下に回す）
    private var titleLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s6) {
                nameText
                badgeView
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                nameText
                badgeView
            }
        }
    }

    /// 場所名
    private var nameText: some View {
        Text(verbatim: name)
            .font(.dgBody(Self.nameFontSize, weight: .black, relativeTo: .body))
            .foregroundStyle(Color.dgInk)
    }

    /// 「前回惜しかった」のバッジ
    @ViewBuilder private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(.dgBody(11, weight: .black, relativeTo: .caption))
                .foregroundStyle(Color.dgAccentPaleText)
                .padding(.horizontal, DGSpacing.s8)
                .padding(.vertical, Self.badgeVerticalPadding)
                .background(Color.dgAccentPale, in: RoundedRectangle(cornerRadius: DGRadius.xs))
        }
    }

    /// 右の操作ボタン
    private var actionButton: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.sm)
        return Button(action: action) {
            Text(actionTitle)
                .font(.dgBody(13, weight: .black, relativeTo: .body))
                .foregroundStyle(isActionEnabled ? Color.dgInk : Color.dgTextDisabled)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DGSpacing.s12)
                .frame(minWidth: Self.actionMinWidth, minHeight: Self.actionHeight)
                .background(isActionEnabled ? Color.dgAccentSecondary : Color.dgSurfaceDisabled, in: shape)
                .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
                // 見た目の 40 の上下を 2 ずつ広げて、タップ領域を 44 にする
                .padding(.vertical, (DGMetrics.minTapTarget - Self.actionHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .disabled(!isActionEnabled)
        .fixedSize()
    }
}

#Preview("PlaceRow 状態ごと") {
    VStack(spacing: DGSpacing.s10) {
        DGPlaceRow(name: "すみだ水族館", meta: "東京・墨田区 · 水族館", category: .aquarium, actionTitle: "追加") {}
        DGPlaceRow(name: "高尾山", meta: "東京・八王子市 · 自然", category: .nature, actionTitle: "追加済み", isActionEnabled: false) {}
        DGPlaceRow(name: "横浜中華街", meta: "神奈川・横浜市 · グルメ", category: .food, actionTitle: "上限", isActionEnabled: false) {}
        DGPlaceRow(
            name: "江の島",
            meta: "神奈川・藤沢市 · 海 · 前回 3いいね",
            category: .sea,
            badge: "前回惜しかった",
            actionTitle: "持ち込む"
        ) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("PlaceRow 文字を最大") {
    VStack(spacing: DGSpacing.s10) {
        DGPlaceRow(name: "すみだ水族館", meta: "東京・墨田区 · 水族館", category: .aquarium, actionTitle: "追加") {}
        DGPlaceRow(
            name: "江の島",
            meta: "神奈川・藤沢市 · 海 · 前回 3いいね",
            category: .sea,
            badge: "前回惜しかった",
            actionTitle: "持ち込む"
        ) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
