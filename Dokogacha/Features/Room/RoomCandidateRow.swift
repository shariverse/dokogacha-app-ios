//
//  RoomCandidateRow.swift
//  Dokogacha
//

import Foundation

/// ルーム画面（S-07）の候補一覧の 1 行分（候補カード 1 枚分）の表示の値。
///
/// 候補・メンバー・ルームの購読の値と、自分が送っている途中のいいね（楽観的更新）から `rows(...)` で作る。
/// 部品（`DGCandidateCard`）に渡す値だけを持つ値の型にして、並び・出やすさ・NEW・いいねの状態を Unit テストで確かめる。
/// 経過時間の文言（F-12）は、時刻とともに変わるので画面の側で `createdAt` から作る。
nonisolated struct RoomCandidateRow: Identifiable, Equatable, Sendable {
    /// いいねした人 1 人分
    struct Liker: Identifiable, Equatable, Sendable {
        /// uid
        let id: String
        /// 表示名（メンバーをまだ読めていないときは空）
        let name: String
        /// アバターの色の位置（`Color.dgAvatar(at:)`。パレットに無い色・まだ読めていないときは nil）
        let avatarColorIndex: Int?
    }

    /// いいねを受け付けるルームの状態（02 の §2.1・F-20「いいねできるのは open/unlocked のときだけ」）
    static let likeableStatuses: Set<RoomStatus> = [.open, .unlocked]

    /// 候補の ID
    let id: String
    /// 場所名
    let name: String
    /// エリアの表示
    let area: String
    /// カテゴリ
    let category: PlaceCategory
    /// ひとこと（無ければ nil）
    let note: String?
    /// 投稿者
    let author: DGCandidateCard.Author
    /// 投稿日時（経過時間の文言に使う）
    let createdAt: Date
    /// NEW バッジを付けるか（F-12）
    let isNew: Bool
    /// 人気の強調（F-23。強調しないなら nil）
    let highlight: PopularityHighlight?
    /// いいねボタンの状態（送っている途中のいいねを映したもの）
    let likeStatus: DGLikeButton.Status
    /// いいねした人（いいねした順。送っている途中の自分のいいねを映したもの）
    let likers: [Liker]
    /// 出やすさ（F-21・F-22）。引き直しで抽選の対象から外れた候補は nil
    let odds: CandidateOdds?
    /// 抽選の対象の候補の中で最大の表示 %（メーターの長さ）
    let maxPercent: Int

    /// 候補一覧の行を作る。
    ///
    /// - 並びは新しい順（`CandidateList.sorted`。F-12）
    /// - いいねの数は、購読の `likedBy` に自分の送っている途中のいいね（`pendingLikes`）を映してから数える。
    ///   押した候補の人数・アバター・出やすさだけでなく、ほかの候補の % も同時に変わる（F-20〜23 の AC）
    /// - 出やすさは `Probability.odds`（引き直しで外れた候補は対象外で nil）、人気は `Probability.highlight`（メンバー数は `memberCount`）。
    ///   引き直しで外れた候補は、人気の強調を付けず、いいねも押せない（もう当たらないため）
    /// - NEW は `CandidateList.isNew`（`lastSeenAt` は画面を開いたときの値。まだ読めていなければ NEW にしない）
    /// - 自分が報告した候補は、ひとことを出さない（02 の §3.5）
    /// - 投稿者は、自分なら「あなた」、ルームのメンバーなら今の表示名（読めていなければ投稿時の名前）、いなければ退出した人
    /// - Parameters:
    ///   - candidates: 候補（購読の値）
    ///   - members: メンバー（購読の値。まだ読めていなければ空）
    ///   - room: ルーム
    ///   - myUserID: 自分の uid
    ///   - lastSeenAt: NEW の判定に使う、自分が前回ルームを見た日時
    ///   - pendingLikes: 送っている途中のいいね（候補の ID → 付ける・外す）
    ///   - reportedIDs: 自分が報告した候補の ID（ひとことを出さない。F-14・`ReportedContent`）
    static func rows(
        candidates: [Identified<Candidate>],
        members: [Identified<Member>],
        room: Room,
        myUserID: String,
        lastSeenAt: Date?,
        pendingLikes: [String: Bool] = [:],
        reportedIDs: Set<String> = []
    ) -> [Self] {
        let sorted = CandidateList.sorted(candidates)
        let likedBy = Dictionary(uniqueKeysWithValues: sorted.map { candidate in
            (candidate.id, effectiveLikedBy(candidate.likedBy, pending: pendingLikes[candidate.id], myUserID: myUserID))
        })
        let excluded = Set(room.excludedCandidateIds)
        let table = Probability.odds(
            of: sorted.map { OddsInput(id: $0.id, likeCount: likedBy[$0.id]?.count ?? 0) },
            mode: room.settings.likeMode,
            excluding: excluded
        )
        let membersByID = Dictionary(members.map { ($0.id, $0.value) }) { first, _ in first }
        return sorted.map { candidate in
            let likers = likedBy[candidate.id] ?? []
            return Self(
                id: candidate.id,
                name: candidate.place.name,
                area: candidate.place.area,
                category: candidate.category,
                note: ReportedContent.visibleNote(candidate.note, isReported: reportedIDs.contains(candidate.id)),
                author: author(of: candidate.value, room: room, members: membersByID, myUserID: myUserID),
                createdAt: candidate.createdAt,
                isNew: lastSeenAt.map { CandidateList.isNew(candidate.value, myUID: myUserID, lastSeenAt: $0) } ?? false,
                // 引き直しで外れた候補は、もう当たらないので人気の強調（リボン）を付けない
                highlight: excluded.contains(candidate.id)
                    ? nil
                    : Probability.highlight(likeCount: likers.count, memberCount: room.memberCount),
                likeStatus: likeStatus(
                    postedBy: candidate.postedBy,
                    isLiked: likers.contains(myUserID),
                    roomStatus: room.status,
                    isExcluded: excluded.contains(candidate.id),
                    myUserID: myUserID
                ),
                likers: likers.map { userID in
                    let member = membersByID[userID]
                    return Liker(
                        id: userID,
                        name: member?.displayName ?? "",
                        avatarColorIndex: member.flatMap { AvatarPalette.index(of: $0.avatarColor) }
                    )
                },
                odds: table[candidate.id],
                maxPercent: table.maxDisplayPercent
            )
        }
    }

    /// 送っている途中の自分のいいねを映した `likedBy`（付けるなら末尾に足し、外すなら取り除く。`arrayUnion`・`arrayRemove` と同じ）
    /// - Parameters:
    ///   - likedBy: 購読の `likedBy`
    ///   - pending: 送っている途中のいいね（無ければ nil）
    ///   - myUserID: 自分の uid
    static func effectiveLikedBy(_ likedBy: [String], pending: Bool?, myUserID: String) -> [String] {
        switch pending {
        case true?:
            likedBy.contains(myUserID) ? likedBy : likedBy + [myUserID]
        case false?:
            likedBy.filter { $0 != myUserID }
        case nil:
            likedBy
        }
    }

    /// いいねボタンの状態。自分の投稿は「自分」（F-20）、いいねを受け付けない状態（`drawn`・`closed`）と、
    /// 引き直しで抽選の対象から外れた候補（いいねしても出やすさが変わらない）は押せない状態
    /// - Parameters:
    ///   - postedBy: 投稿者の uid
    ///   - isLiked: 自分がいいねしているか
    ///   - roomStatus: ルームの状態
    ///   - isExcluded: 引き直しで抽選の対象から外れた候補か
    ///   - myUserID: 自分の uid
    static func likeStatus(
        postedBy: String,
        isLiked: Bool,
        roomStatus: RoomStatus,
        isExcluded: Bool,
        myUserID: String
    ) -> DGLikeButton.Status {
        if postedBy == myUserID {
            return .mine
        }
        guard likeableStatuses.contains(roomStatus), !isExcluded else {
            return isLiked ? .lockedLiked : .locked
        }
        return isLiked ? .liked : .notLiked
    }

    /// 投稿者の表示
    private static func author(
        of candidate: Candidate,
        room: Room,
        members: [String: Member],
        myUserID: String
    ) -> DGCandidateCard.Author {
        if candidate.postedBy == myUserID {
            return .me
        }
        guard room.memberIds.contains(candidate.postedBy) else {
            return .departed
        }
        return .member(members[candidate.postedBy]?.displayName ?? candidate.postedByName)
    }
}
