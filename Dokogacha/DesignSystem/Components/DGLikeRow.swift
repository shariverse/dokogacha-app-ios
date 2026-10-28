//
//  DGLikeRow.swift
//  Dokogacha
//
//  候補カードの「いいねした人」の行（`04_design_system.md` の §4 の CandidateCard の LikeRow・02 の F-20）。
//

import SwiftUI

/// いいねした人のアバターを重ねて並べ、人数と「人がいいね」を続ける行。0 人なら「まだいいねはありません」。
///
/// アバター 26（白い 2pt の縁・左に 6 ずつ重ねる。縁の色はカードの背景と同じ）＋人数（見出し 20、人気カードでは `accent.text`）＋「人がいいね」（13 Black）。
/// 20 人まで入るルームで横にあふれないよう、アバターは `DGLikeRow.maxVisibleAvatars` 人まで並べる（人数はすべて数える）。
struct DGLikeRow: View {
    /// いいねした人 1 人分（アバターに要る値だけ）
    struct Liker: Identifiable {
        /// メンバーを区別する値（ユーザー ID など）
        let id: String
        /// 表示名（アバターの 1 文字目と VoiceOver で使う）
        let name: String
        /// 割り当てた色（`Color.dgAvatars` のどれか）
        let color: Color
    }

    /// 並べるアバターの上限
    static let maxVisibleAvatars = 5
    /// 行の最小の高さ（アバターの直径）
    private static let minHeight: CGFloat = DGAvatar.Size.small.diameter
    /// 「人がいいね」の文字の大きさ
    private static let suffixSize: CGFloat = 13

    /// いいねした人（いいねした順）
    let likers: [Liker]
    /// 人気カード（F-23）か。人数を `accent.text` にする
    var isPopular = false
    /// アバターの縁の色（カードの背景と同じ色にする）
    var cardBackground: Color = .dgSurfaceCard

    var body: some View {
        Group {
            if likers.isEmpty {
                Text("まだいいねはありません")
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
            } else {
                HStack(spacing: DGSpacing.s8) {
                    HStack(spacing: -DGSpacing.s6) {
                        ForEach(likers.prefix(Self.maxVisibleAvatars)) { liker in
                            DGAvatar(name: liker.name, color: liker.color, size: .small, ringColor: cardBackground)
                        }
                    }
                    .accessibilityHidden(true)
                    countText
                }
            }
        }
        .frame(minHeight: Self.minHeight, alignment: .leading)
    }

    /// 「N人がいいね」（人数は見出し 20、続きは 13 Black）
    private var countText: some View {
        let count = Text(verbatim: "\(likers.count)")
            .font(.dg(.displayS))
            .foregroundStyle(isPopular ? Color.dgAccentText : Color.dgInk)
        return Text("\(count)人がいいね")
            .font(.dgBody(Self.suffixSize, weight: .black, relativeTo: .subheadline))
            .foregroundStyle(Color.dgInk)
    }
}

/// Preview 用のいいねした人
private let previewLikers: [DGLikeRow.Liker] = [
    DGLikeRow.Liker(id: "yui", name: "ゆい", color: .dgAvatar(at: 0)),
    DGLikeRow.Liker(id: "kenta", name: "けんた", color: .dgAvatar(at: 1)),
    DGLikeRow.Liker(id: "misaki", name: "みさき", color: .dgAvatar(at: 2)),
    DGLikeRow.Liker(id: "soma", name: "そうま", color: .dgAvatar(at: 3)),
    DGLikeRow.Liker(id: "riko", name: "りこ", color: .dgAvatar(at: 4)),
    DGLikeRow.Liker(id: "haru", name: "はる", color: .dgAvatar(at: 5))
]

#Preview("LikeRow 人数ごと") {
    VStack(alignment: .leading, spacing: DGSpacing.s16) {
        DGLikeRow(likers: [])
        DGLikeRow(likers: Array(previewLikers.prefix(1)))
        DGLikeRow(likers: Array(previewLikers.prefix(3)))
        DGLikeRow(likers: previewLikers)
        DGLikeRow(likers: Array(previewLikers.prefix(4)), isPopular: true, cardBackground: .dgSurfaceHighlight)
            .padding(DGSpacing.s8)
            .background(Color.dgSurfaceHighlight)
    }
    .padding(DGSpacing.screenX)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color.dgSurfaceCard)
}

#Preview("LikeRow 文字を最大") {
    VStack(alignment: .leading, spacing: DGSpacing.s16) {
        DGLikeRow(likers: [])
        DGLikeRow(likers: Array(previewLikers.prefix(3)))
    }
    .padding(DGSpacing.screenX)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color.dgSurfaceCard)
    .dynamicTypeSize(.accessibility5)
}
