//
//  ResultTicket.swift
//  Dokogacha
//

import Foundation

/// S-14 の行き先きっぷに出す値（02 の §6.3 F-42）。
///
/// 抽選の記録（当選確率・抽選日・抽選の対象の候補の数）・ルーム（ルーム名）・当選した候補の行（場所・投稿者・いいね数）から作る。
/// 画面と共有画像（`TicketShareImage`）の両方がこの値だけで描く。
nonisolated struct ResultTicket: Equatable, Sendable {
    /// ルーム名（帯の右）
    let roomName: String
    /// 当選した場所の名前
    let destinationName: String
    /// エリアの表示
    let area: String
    /// カテゴリ
    let category: PlaceCategory
    /// ひとこと（無ければ nil）
    let note: String?
    /// 投稿者
    let author: DGCandidateCard.Author
    /// いいね数（`drawn` 以降はいいねできないので、抽選の時点の数と同じ）
    let likeCount: Int
    /// 当選確率の表示 %（抽選の記録の確率を F-21 と同じ丸めで %）
    let percent: Int
    /// 抽選の日時（「決定」スタンプの `M.DD`）
    let drawnAt: Date
    /// レア当選か（`WinRarity`）
    let isRare: Bool

    /// 抽選の記録・ルーム・当選した候補の行から作る
    /// - Parameters:
    ///   - draw: 抽選の記録
    ///   - room: ルーム
    ///   - winner: 当選した候補の行（S-07 と同じ作り方。投稿者は自分なら「あなた」、退出した人なら「退出したメンバー」）
    static func make(draw: Draw, room: Room, winner: RoomCandidateRow) -> Self {
        Self(
            roomName: room.name,
            destinationName: winner.name,
            area: winner.area,
            category: winner.category,
            note: winner.note,
            author: winner.author,
            likeCount: winner.likers.count,
            percent: Probability.displayPercent(probability: draw.probability),
            drawnAt: draw.createdAt,
            isRare: WinRarity.isRare(draw)
        )
    }
}
