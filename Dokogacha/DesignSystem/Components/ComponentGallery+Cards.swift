//
//  ComponentGallery+Cards.swift
//  Dokogacha
//
//  カードと表示の部品の見本のページ（`ComponentGallery` の「カード」「表示」）。
//  Stg・Release のアプリに入れないよう、Debug でだけコンパイルする。
//

#if DEBUG
import SwiftUI

/// CandidateCard・ProbabilityMeter・LikeButton・LikeRow を状態ごとに並べた見本のページ。
///
/// いいねボタンは押すと状態が切り替わり、いいねした人・表示 %・メーターも一緒に変わる（02 の F-20 の AC の見た目を確かめるため）。
struct CardComponentsPage: View {
    /// 1 枚目の候補にいいねしているか
    @State private var isLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s14) {
            GallerySectionTitle(name: "CandidateCard")
            DGCandidateCard(
                name: "高尾山",
                meta: "東京・八王子市 · 自然",
                category: .nature,
                author: .member("みさき"),
                elapsed: "3日前",
                note: "紅葉シーズンにちょうどいい",
                highlight: isLiked ? .allLiked : .popular,
                likeStatus: isLiked ? .liked : .notLiked,
                likers: isLiked ? GallerySamples.likers : Array(GallerySamples.likers.prefix(3)),
                level: .high,
                percent: isLiked ? 16 : 15,
                maxPercent: 16
            ) {
                isLiked.toggle()
            }
            .padding(.top, DGSpacing.s8)
            DGCandidateCard(
                name: "長瀞ライン下り",
                meta: "埼玉・秩父郡 · アクティビティ",
                category: .activity,
                author: .member("そうま"),
                elapsed: "3時間前",
                note: "川下り！",
                isNew: true,
                likeStatus: .notLiked,
                likers: [],
                level: .low,
                percent: 5,
                maxPercent: 16
            ) {}
            DGCandidateCard(
                name: "東京ディズニーシー",
                meta: "千葉・浦安市 · テーマパーク",
                category: .park,
                author: .me,
                elapsed: "5時間前",
                likeStatus: .mine,
                likers: Array(GallerySamples.likers.prefix(2)),
                level: .mid,
                percent: 13,
                maxPercent: 16
            ) {}
            GallerySectionTitle(name: "ProbabilityMeter")
            VStack(spacing: DGSpacing.s12) {
                DGProbabilityMeter(level: .high, percent: 16, maxPercent: 16)
                DGProbabilityMeter(level: .mid, percent: 13, maxPercent: 16)
                DGProbabilityMeter(level: .low, percent: 5, maxPercent: 16)
                DGProbabilityMeter(level: .flat, percent: 13, maxPercent: 13)
            }
            .padding(DGSpacing.cardPadding)
            .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: DGRadius.md))
            GallerySectionTitle(name: "LikeButton / LikeRow")
            HStack(spacing: DGSpacing.s12) {
                ForEach(DGLikeButton.Status.allCases, id: \.self) { status in
                    DGLikeButton(state: status) {}
                }
            }
            DGLikeRow(likers: Array(GallerySamples.likers.prefix(3)))
            DGLikeRow(likers: [])
        }
    }
}

/// RoomTagCard・DestinationBoard・TicketStub・Stamp・AdFreeNotice を状態ごとに並べた見本のページ。
struct DisplayComponentsPage: View {
    /// スタンプの押す動きをやり直すための番号
    @State private var stampRound = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s14) {
            GallerySectionTitle(name: "RoomTagCard")
            DGRoomTagCard(status: .open, roomName: "11月の日帰り旅行", capsuleCount: 8, members: GallerySamples.members(5, ready: 3)) {}
            DGRoomTagCard(status: .unlocked, roomName: "サークルの合宿", capsuleCount: 12, members: GallerySamples.members(9, ready: 9)) {}
            GallerySectionTitle(name: "DestinationBoard")
            DGDestinationBoard(capsuleCount: 8)
            DGDestinationBoard(capsuleCount: 12, placement: .cardTop)
            GallerySectionTitle(name: "TicketStub")
            DGTicketStub(roomName: "夏の日帰り", date: GallerySamples.summerDate, destinationName: "城ヶ島", leftoverCount: 4) {}
            DGTicketStub(roomName: "サークルの合宿", date: GallerySamples.autumnDate, destinationName: "高尾山", leftoverCount: 0) {}
            GallerySectionTitle(name: "Stamp")
            HStack(spacing: DGSpacing.s24) {
                DGStamp("済")
                DGStamp("決定", size: .large, date: GallerySamples.autumnDate)
                DGStamp("決定", size: .large, date: GallerySamples.autumnDate, animatesIn: true)
                    .id(stampRound)
                DGButton("押す", kind: .yellow) {
                    stampRound += 1
                }
            }
            .padding(DGSpacing.s12)
            .frame(maxWidth: .infinity)
            .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: DGRadius.md))
            GallerySectionTitle(name: "AdFreeNotice")
            DGAdFreeNotice(sponsorName: "けんた")
        }
    }
}

/// 見本のセクションの見出し（部品の名前。翻訳の対象ではないので `Text(verbatim:)` で出す）
struct GallerySectionTitle: View {
    /// 部品の名前
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.dg(.displaySection))
            .foregroundStyle(Color.dgInk)
            .padding(.top, DGSpacing.s4)
    }
}

/// 見本に並べるデモの値
private enum GallerySamples {
    /// いいねした人
    static let likers: [DGLikeRow.Liker] = [
        DGLikeRow.Liker(id: "kenta", name: "けんた", color: .dgAvatar(at: 1)),
        DGLikeRow.Liker(id: "misaki", name: "みさき", color: .dgAvatar(at: 2)),
        DGLikeRow.Liker(id: "soma", name: "そうま", color: .dgAvatar(at: 3)),
        DGLikeRow.Liker(id: "me", name: "あなた", color: .dgAvatar(at: 4))
    ]

    /// 2026/8/24（日本時間の 13 時）
    static let summerDate = Date(timeIntervalSince1970: 1_787_544_000)
    /// 2026/10/21（日本時間の 13 時）
    static let autumnDate = Date(timeIntervalSince1970: 1_792_555_200)

    /// メンバーを `count` 人作り、先頭の `ready` 人を準備OKにする
    static func members(_ count: Int, ready: Int) -> [DGRoomTagCard.Member] {
        let names = ["ゆい", "けんた", "みさき", "そうま", "りこ", "はる", "なお", "あおい", "たくみ", "めい"]
        return (0..<count).map { index in
            DGRoomTagCard.Member(
                id: "member-\(index)",
                name: names[index % names.count],
                color: .dgAvatar(at: index),
                isReady: index < ready
            )
        }
    }
}

#Preview("カード") {
    ComponentGallery(page: .cards)
}

#Preview("表示") {
    ComponentGallery(page: .displays)
}
#endif
