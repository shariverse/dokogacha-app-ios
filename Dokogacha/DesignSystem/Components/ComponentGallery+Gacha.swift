//
//  ComponentGallery+Gacha.swift
//  Dokogacha
//
//  ガチャの筐体と行き先きっぷの見本のページ（`ComponentGallery` の「ガチャ」「きっぷ」）。
//  Stg・Release のアプリに入れないよう、Debug でだけコンパイルする。
//

#if DEBUG
import SwiftUI

/// GachaMachine を状態ごとに並べた見本のページ。
///
/// 1 台目は等倍（回せる・カプセル 8 個）。2 台目からは 2 台ずつ横に並べるため縮小して出す
/// （回せない・カプセル 0 個／取り出し・カプセル 60 個（描くのは 50 個）／動きの途中の `Pose`／カプセル 1 個）。
/// 1 台目のレバーは押すと押した回数を数え、レバーが押せることを確かめられる。
struct GachaComponentsPage: View {
    /// 2 台ずつ並べるときの縮小の倍率
    private static let compactScale: CGFloat = 0.5

    /// 1 台目のレバーを押した回数
    @State private var turnCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s14) {
            GallerySectionTitle(name: "GachaMachine")
            DGGachaMachine(capsuleColors: Self.colors(8)) {
                turnCount += 1
            }
            .frame(maxWidth: .infinity)
            Text(verbatim: "lever: \(turnCount)")
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
            GallerySectionTitle(name: "GachaMachine 状態ごと")
            HStack(alignment: .top, spacing: DGSpacing.s12) {
                compact(caption: "0 / disabled") {
                    DGGachaMachine(capsuleColors: [], isLeverEnabled: false) {}
                }
                compact(caption: "60 / dispensed") {
                    DGGachaMachine(capsuleColors: Self.colors(60), dispensedColor: .dgCapsule(at: 2), isLeverEnabled: false) {}
                }
            }
            HStack(alignment: .top, spacing: DGSpacing.s12) {
                compact(caption: "pose") {
                    DGGachaMachine(
                        capsuleColors: Self.colors(12),
                        dispensedColor: .dgCapsule(at: 4),
                        isLeverEnabled: false,
                        pose: DGGachaMachine.Pose(
                            domeRotationDegrees: -4,
                            leverRotationDegrees: 45,
                            dispensedOffsetY: -30,
                            dispensedScale: 1.3
                        )
                    ) {}
                }
                compact(caption: "1") {
                    DGGachaMachine(capsuleColors: Self.colors(1)) {}
                }
            }
        }
    }

    /// 候補の投稿順のカプセルの色を `count` 個
    private static func colors(_ count: Int) -> [Color] {
        (0..<count).map { Color.dgCapsule(at: $0) }
    }

    /// 縮小した筐体と、その状態の説明
    private func compact(caption: String, @ViewBuilder machine: () -> DGGachaMachine) -> some View {
        let size = DGGachaMachine.size
        return VStack(spacing: DGSpacing.s4) {
            machine()
                .scaleEffect(Self.compactScale)
                .frame(width: size.width * Self.compactScale, height: size.height * Self.compactScale)
            Text(verbatim: caption)
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// DestinationTicket を状態ごとに並べた見本のページ。
///
/// ひとことあり（自然）／長いルーム名と場所名・ひとことなし（アート・自分の投稿）／退出したメンバーの投稿（グルメ）。
struct TicketComponentsPage: View {
    /// 抽選日（2026/10/21 の日本時間 13 時）
    private static let drawnAt = Date(timeIntervalSince1970: 1_792_555_200)

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s14) {
            GallerySectionTitle(name: "DestinationTicket")
            DGDestinationTicket(
                roomName: "11月の日帰り旅行",
                destinationName: "高尾山",
                meta: "東京・八王子市 · 自然",
                category: .nature,
                note: "紅葉シーズンにちょうどいい",
                author: .member("みさき"),
                likeCount: 4,
                percent: 16,
                drawnAt: Self.drawnAt
            )
            GallerySectionTitle(name: "DestinationTicket 長い名前")
            DGDestinationTicket(
                roomName: "サークルの合宿の行き先をみんなで決めるルーム",
                destinationName: "チームラボプラネッツ TOKYO DMM",
                meta: "東京・江東区 · アート・美術館",
                category: .art,
                author: .me,
                likeCount: 0,
                percent: 5,
                drawnAt: Self.drawnAt
            )
            GallerySectionTitle(name: "DestinationTicket 退出したメンバー")
            DGDestinationTicket(
                roomName: "ごはん会",
                destinationName: "横浜中華街",
                meta: "神奈川・横浜市 · グルメ",
                category: .food,
                author: .departed,
                likeCount: 2,
                percent: 13,
                drawnAt: Self.drawnAt
            )
        }
    }
}

#Preview("ガチャ") {
    ComponentGallery(page: .gacha)
}

#Preview("きっぷ") {
    ComponentGallery(page: .ticket)
}
#endif
