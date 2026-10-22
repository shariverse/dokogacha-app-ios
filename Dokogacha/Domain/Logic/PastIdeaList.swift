//
//  PastIdeaList.swift
//  Dokogacha
//
//  S-08 の「過去のアイデア」の並び（02 の §3.4 F-13・03 の S-08 の「過去のアイデア」）。
//

import Foundation

/// 過去のアイデアの、元のルームごとのまとまり（03 の S-08「ルームごとの見出し（黒帯）：「{ルーム名} {M/D}」＋右に「{当選場所} ゆき」」）
nonisolated struct PastIdeaGroup: Identifiable, Equatable, Sendable {
    /// 元のルームの ID
    let id: String
    /// 元のルームの名前
    let roomName: String
    /// 元のルームが終了した日時（見出しの M/D）
    let closedAt: Date
    /// 元のルームで当選した場所の名前（「◯◯ ゆき」。空なら出さない）
    let winnerName: String
    /// このルームの過去のアイデア（前回のいいねが多い順）
    let ideas: [Identified<PastIdea>]
}

/// 過去のアイデアを画面に並べる形にする。
///
/// 過去のアイデアは Functions がルームの終了のときにメンバーごとに作り（`RoomClosing.pastIdeas`）、アプリは読むだけ。
/// 持ち込んでも消さない（02 の §3.4 は消すと書いていない。同じルームに 2 度入れようとすると重複の判定で止まり、別のルームにはまた持ち込める）
nonisolated enum PastIdeaList {
    /// 元のルームごとにまとめ、新しいルーム順に並べる（02 の §3.4「ルームごとにまとめ、新しいルーム順に並べる」）。
    ///
    /// - ルームの順は終了の日時の降順。同じならルームの ID の降順（並びが揺れないように）
    /// - 見出しのルーム名・当選の場所は、そのルームの最初の過去のアイデアの値（同じルームのものはどれも同じ値）
    /// - ルームの中は前回のいいねが多い順（「前回惜しかった」を上に出す）。同じなら ID の順。02 に決まりは無い
    /// - Parameter ideas: 自分の過去のアイデア（順は問わない）
    static func groups(_ ideas: [Identified<PastIdea>]) -> [PastIdeaGroup] {
        Dictionary(grouping: ideas, by: \.sourceRoomId)
            .compactMap { roomID, members -> PastIdeaGroup? in
                let sorted = members.sorted { lhs, rhs in
                    (rhs.prevLikeCount, lhs.id) < (lhs.prevLikeCount, rhs.id)
                }
                guard let first = sorted.first else {
                    return nil
                }
                return PastIdeaGroup(
                    id: roomID,
                    roomName: first.sourceRoomName,
                    closedAt: sorted.map(\.sourceClosedAt).max() ?? first.sourceClosedAt,
                    winnerName: first.sourceWinnerName,
                    ideas: sorted
                )
            }
            .sorted { ($0.closedAt, $0.id) > ($1.closedAt, $1.id) }
    }

    /// 「前回惜しかった」バッジを付けるか（02 の §3.4「前回のいいねが3以上」。`DomainConstants.Popularity.closeCallMinLikes`）
    static func isCloseCall(_ idea: PastIdea) -> Bool {
        idea.prevLikeCount >= DomainConstants.Popularity.closeCallMinLikes
    }

    /// 持ち込むときに S-09 で確かめる場所（`SearchedPlace` の形にする。ID は過去のアイデアの ID、カテゴリは前回のもの）
    static func draftPlace(_ idea: Identified<PastIdea>) -> SearchedPlace {
        SearchedPlace(id: idea.id, place: idea.place, category: idea.category)
    }
}
