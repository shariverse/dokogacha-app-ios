//
//  HomeRoomCard.swift
//  Dokogacha
//

import Foundation

/// ホームの「進行中のルーム」のカード 1 枚分の表示の値（03 の S-02 の 2）。
///
/// ルーム（`rooms` の購読）とメンバー（ルームごとの `members` の購読）から、`cards(rooms:members:)` で作る。
/// 画面の部品（`DGRoomTagCard`）に渡す値だけを持つ値の型にして、並び・人数・カプセルの数を Unit テストで確かめる。
nonisolated struct HomeRoomCard: Identifiable, Equatable, Sendable {
    /// カードに並べるメンバー 1 人分
    struct Member: Identifiable, Equatable, Sendable {
        /// uid
        let id: String
        /// 表示名（メンバーをまだ読めていないときは空）
        let name: String
        /// アバターの色の位置（`Color.dgAvatar(at:)`。パレットに無い色・まだ読めていないときは nil）
        let avatarColorIndex: Int?
        /// 準備OKか
        let isReady: Bool
    }

    /// ルームの ID
    let id: String
    /// ルーム名
    let name: String
    /// ルームの状態（状態チップ）
    let status: RoomStatus
    /// 行き先表示の「カプセル N個」（候補の数から、引き直しで外れた候補を除いた数）
    let capsuleCount: Int
    /// メンバー（参加の早い順）
    let members: [Member]

    /// ホームに並べるカードを作る。
    ///
    /// - 並びは作成日時の新しい順（同じ日時ならルームの ID の降順。05 の §6 のクエリと同じ順）
    /// - `closed` のルームは「思い出のきっぷ」の側なので除く（購読は `closed` を返さないが、念のため）
    /// - メンバーをまだ読めていないルームは、ルームの `memberIds` と `readyCount` から仮のメンバー（名前なし）を並べ、
    ///   「準備OK n/m人」の数だけは先に正しく出す
    static func cards(rooms: [Identified<Room>], members: [String: [Identified<Dokogacha.Member>]]) -> [Self] {
        rooms
            .filter { $0.status != .closed }
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
            .map { room in
                Self(
                    id: room.id,
                    name: room.name,
                    status: room.status,
                    capsuleCount: capsuleCount(of: room.value),
                    members: members[room.id].map(cardMembers) ?? placeholderMembers(of: room.value)
                )
            }
    }

    /// カプセルの数（候補の数から引き直しで外れた候補を除く。負にしない）
    static func capsuleCount(of room: Room) -> Int {
        max(room.candidateCount - room.excludedCandidateIds.count, 0)
    }

    /// 読めたメンバーをカードの値にする
    private static func cardMembers(_ members: [Identified<Dokogacha.Member>]) -> [Member] {
        members.map { member in
            Member(
                id: member.id,
                name: member.displayName,
                avatarColorIndex: AvatarPalette.index(of: member.avatarColor),
                isReady: member.ready
            )
        }
    }

    /// メンバーを読む前の仮のメンバー（人数と準備OKの数だけ合わせる）
    private static func placeholderMembers(of room: Room) -> [Member] {
        room.memberIds.enumerated().map { index, userID in
            Member(id: userID, name: "", avatarColorIndex: nil, isReady: index < room.readyCount)
        }
    }
}
