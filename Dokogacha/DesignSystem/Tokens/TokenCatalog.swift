//
//  TokenCatalog.swift
//  Dokogacha
//
//  トークンの見本。Xcode Preview で `docs/spec/04_design_system.md` の表と見比べるためだけに使い、画面からは使わない。
//  Stg・Release のアプリに入れないよう、Debug でだけコンパイルする。
//

#if DEBUG
import SwiftUI

/// 色とタイプスケールのトークンを並べた見本の画面（Preview 用）。
///
/// トークン名は翻訳の対象ではないので `Text(verbatim:)` で出す。
struct TokenCatalog: View {
    /// 見本の 1 行（トークン名と色）
    private struct Swatch: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    /// 見本に並べる基本の色
    private let baseSwatches: [Swatch] = [
        Swatch(name: "bg.base", color: .dgBgBase),
        Swatch(name: "surface.card", color: .dgSurfaceCard),
        Swatch(name: "surface.highlight", color: .dgSurfaceHighlight),
        Swatch(name: "surface.subtle", color: .dgSurfaceSubtle),
        Swatch(name: "surface.muted", color: .dgSurfaceMuted),
        Swatch(name: "surface.disabled", color: .dgSurfaceDisabled),
        Swatch(name: "surface.ad", color: .dgSurfaceAd),
        Swatch(name: "surface.gachaDome", color: .dgSurfaceGachaDome),
        Swatch(name: "ink", color: .dgInk),
        Swatch(name: "text.secondary", color: .dgTextSecondary),
        Swatch(name: "text.disabled", color: .dgTextDisabled),
        Swatch(name: "text.onInk", color: .dgTextOnInk),
        Swatch(name: "line.dashed", color: .dgLineDashed),
        Swatch(name: "line.dashedStrong", color: .dgLineDashedStrong),
        Swatch(name: "accent.primary", color: .dgAccentPrimary),
        Swatch(name: "accent.text", color: .dgAccentText),
        Swatch(name: "accent.secondary", color: .dgAccentSecondary),
        Swatch(name: "accent.pale", color: .dgAccentPale),
        Swatch(name: "accent.paleText", color: .dgAccentPaleText),
        Swatch(name: "like.bg", color: .dgLikeBg),
        Swatch(name: "like.bgActive", color: .dgLikeBgActive),
        Swatch(name: "like.icon", color: .dgLikeIcon),
        Swatch(name: "like.iconActive", color: .dgLikeIconActive),
        Swatch(name: "like.iconMine", color: .dgLikeIconMine)
    ]

    /// 見本に並べるタイプスケール
    private let typeScales: [(name: String, token: DGTypeScale)] = [
        ("display.xl", .displayXL),
        ("display.ticket", .displayTicket),
        ("display.l", .displayL),
        ("display.m", .displayM),
        ("display.s", .displayS),
        ("display.header", .displayHeader),
        ("display.section", .displaySection),
        ("display.tag", .displayTag),
        ("body.title", .bodyTitle),
        ("body.button", .bodyButton),
        ("body.regular", .bodyRegular),
        ("body.caption", .bodyCaption)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpacing.s16) {
                ForEach(baseSwatches) { swatch in
                    HStack(spacing: DGSpacing.s12) {
                        RoundedRectangle(cornerRadius: DGRadius.xs)
                            .fill(swatch.color)
                            .overlay(RoundedRectangle(cornerRadius: DGRadius.xs).stroke(Color.dgInk, lineWidth: DGBorder.regular))
                            .frame(width: DGMetrics.minTapTarget, height: DGMetrics.minTapTarget)
                        Text(verbatim: swatch.name)
                            .font(.dg(.bodyCaption))
                            .foregroundStyle(Color.dgTextPrimary)
                    }
                }
                chipRow
                capsuleRow
                ForEach(typeScales, id: \.name) { item in
                    Text(verbatim: "\(item.name) ドコガチャ 16%")
                        .font(.dg(item.token))
                        .foregroundStyle(Color.dgTextPrimary)
                }
            }
            .padding(DGSpacing.screenX)
        }
        .background(Color.dgBgBase)
    }

    /// 状態チップと出やすさのレベルの色の組
    private var chipRow: some View {
        let statuses: [DGColorPair] = [DGStatusColors.open, DGStatusColors.unlocked, DGStatusColors.drawn, DGStatusColors.closed]
        let levels: [DGLevelStyle] = [.high, .mid, .low, .flat]
        return VStack(alignment: .leading, spacing: DGSpacing.s8) {
            HStack(spacing: DGSpacing.s6) {
                ForEach(statuses.indices, id: \.self) { index in
                    Text(verbatim: "status")
                        .font(.dgBody(12, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(statuses[index].foreground)
                        .padding(.horizontal, DGSpacing.s10)
                        .padding(.vertical, DGSpacing.s4)
                        .background(statuses[index].background, in: Capsule())
                }
            }
            HStack(spacing: DGSpacing.s6) {
                ForEach(levels.indices, id: \.self) { index in
                    Text(levels[index].label)
                        .font(.dgBody(12, weight: .black, relativeTo: .caption))
                        .foregroundStyle(levels[index].chipForeground)
                        .padding(.horizontal, DGSpacing.s8)
                        .padding(.vertical, DGSpacing.s4)
                        .background(levels[index].chipBackground, in: RoundedRectangle(cornerRadius: DGRadius.xs))
                }
            }
        }
    }

    /// カプセルとアバターの色
    private var capsuleRow: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s8) {
            HStack(spacing: DGSpacing.s6) {
                ForEach(Color.dgCapsules.indices, id: \.self) { index in
                    CapsuleBall(color: .dgCapsule(at: index))
                        .frame(width: 28, height: 28)
                }
            }
            HStack(spacing: DGSpacing.s6) {
                ForEach(Color.dgAvatars.indices, id: \.self) { index in
                    Circle()
                        .fill(Color.dgAvatar(at: index))
                        .frame(width: 28, height: 28)
                }
            }
        }
    }
}

#Preview("トークンの見本") {
    TokenCatalog()
}
#endif
