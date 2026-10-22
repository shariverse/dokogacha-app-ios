//
//  MemoryTicket.swift
//  Dokogacha
//

import Foundation

/// ホーム（S-02）の「思い出のきっぷ」1 枚に出す値（03 の S-02 の 3・02 の §6.5 F-44）。
///
/// 終了したルーム（`closed`）と、その当選した候補から作る。押すと S-14 結果（閲覧のみ）を `drawID` で開く。
nonisolated struct MemoryTicket: Identifiable, Equatable, Sendable {
    /// ルームの ID
    let id: String
    /// 結果の画面で開く抽選の ID（`rooms.currentDrawId`）
    let drawID: String
    /// ルーム名
    let roomName: String
    /// 日付（行き先を決めた日 = 終了の日時。無ければ抽選の日時）
    let date: Date
    /// 当選した場所の名前（「◯◯ ゆき」）
    let destinationName: String
    /// 外れた候補の数（「外れた候補 N件は次のルームで使えます」。次のルームに持ち込める候補）
    let leftoverCount: Int
}

nonisolated extension MemoryTicket {
    /// ホームに最初に出す枚数（03 の S-02「最大5件表示＋「すべて見る」」）
    static let visibleLimit = 5

    /// 終了したルームと当選した候補から、新しい順のきっぷを作る。
    ///
    /// - `closed` で、抽選の ID と当選した候補の ID があり、当選した候補が届いているルームだけを出す
    ///   （候補は購読で後から届くので、届いたものから出す）
    /// - 新しい順は終了の日時（無ければ抽選の日時・作成日時）の降順。同じならルームの ID の降順（並びが揺れないように）
    /// - 外れた候補の数は「候補の数 − 当選の 1 件」（引き直しで外れた前の当選も過去のアイデアに入るので含める。02 の §3.4）
    /// - Parameters:
    ///   - rooms: 終了したルーム
    ///   - winners: 当選した候補（鍵はルームの ID）
    static func tickets(rooms: [Identified<Room>], winners: [String: Candidate]) -> [Self] {
        rooms
            .compactMap { room -> Self? in
                guard room.status == .closed, let drawID = room.currentDrawId, !drawID.isEmpty,
                      room.winnerCandidateId != nil, let winner = winners[room.id] else {
                    return nil
                }
                return Self(
                    id: room.id,
                    drawID: drawID,
                    roomName: room.name,
                    date: room.closedAt ?? room.drawnAt ?? room.createdAt,
                    destinationName: winner.place.name,
                    leftoverCount: max(0, room.candidateCount - 1)
                )
            }
            .sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    /// ホームに出すきっぷ（「すべて見る」を押す前は最初の 5 枚）
    /// - Parameters:
    ///   - tickets: 新しい順のきっぷ
    ///   - showsAll: 「すべて見る」を押したか
    static func visible(_ tickets: [Self], showsAll: Bool) -> [Self] {
        showsAll ? tickets : Array(tickets.prefix(visibleLimit))
    }

    /// 「すべて見る」を出すか（押す前で、5 枚より多いとき）
    static func hasMore(_ tickets: [Self], showsAll: Bool) -> Bool {
        !showsAll && tickets.count > visibleLimit
    }
}
