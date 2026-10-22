//
//  DGCategoryTile.swift
//  Dokogacha
//
//  カテゴリタイル（`04_design_system.md` の §1 の「カテゴリタイル」・§4 の PlaceRow と CandidateCard）。
//

import SwiftUI

/// カテゴリの色の角丸の四角に、カテゴリのアイコンを置いたタイル。
///
/// PlaceRow では 42（角丸 12・アイコン 24）、CandidateCard と行き先きっぷでは 52（角丸 14・アイコン 30）。
/// 飾りなので VoiceOver では読まない（カテゴリ名は隣の文言で読む）。
struct DGCategoryTile: View {
    /// タイルの大きさ
    nonisolated enum Size: CaseIterable, Sendable {
        /// PlaceRow（42）
        case small
        /// CandidateCard・行き先きっぷ（52）
        case large

        /// 一辺
        var side: CGFloat {
            switch self {
            case .small: 42
            case .large: 52
            }
        }

        /// 角丸
        var cornerRadius: CGFloat {
            switch self {
            case .small: DGRadius.sm
            case .large: 14
            }
        }

        /// アイコンの一辺
        var iconSize: CGFloat {
            switch self {
            case .small: 24
            case .large: 30
            }
        }
    }

    /// カテゴリの色とアイコン
    let category: DGCategoryStyle
    /// 大きさ
    var size: Size = .small

    var body: some View {
        Image(category.iconName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size.iconSize, height: size.iconSize)
            .foregroundStyle(category.foreground)
            .frame(width: size.side, height: size.side)
            .background(category.background, in: RoundedRectangle(cornerRadius: size.cornerRadius))
            .accessibilityHidden(true)
    }
}

#Preview("CategoryTile") {
    let categories = PlaceCategory.allCases.map(DGCategoryStyle.of)
    VStack(spacing: DGSpacing.s16) {
        HStack(spacing: DGSpacing.s6) {
            ForEach(categories.indices, id: \.self) { index in
                DGCategoryTile(category: categories[index])
            }
        }
        HStack(spacing: DGSpacing.s8) {
            ForEach(categories.prefix(5).indices, id: \.self) { index in
                DGCategoryTile(category: categories[index], size: .large)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}
