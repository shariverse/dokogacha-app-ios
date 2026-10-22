//
//  RoomModel+Display.swift
//  Dokogacha
//

import Foundation

/// S-07 ルームの画面に出す値（購読で届いた値と送っている途中の書き込みから計算する）。
///
/// `RoomModel.swift` が SwiftLint の `file_length` を超えないよう、読むだけの計算をこのファイルに分けている
extension RoomModel {
    /// 候補一覧の行（新しい順。送っている途中のいいねを映し、報告した候補のひとことを隠したもの）
    var rows: [RoomCandidateRow] {
        guard let room else {
            return []
        }
        return RoomCandidateRow.rows(
            candidates: candidates,
            members: members,
            room: room,
            myUserID: userID,
            lastSeenAt: seenBaseline,
            pendingLikes: pendingLikes.mapValues(\.value),
            reportedIDs: reportedCandidateIDs
        )
    }

    /// 自分が報告した候補の ID（ひとこととURLを出さない。F-14）
    var reportedCandidateIDs: Set<String> {
        Set(candidates.map(\.id).filter { reportedCandidates.hasReported(roomID: roomID, candidateID: $0) })
    }

    /// NEW の候補の数（「前回見たあとに N件の候補が増えました」の N）
    var newCount: Int {
        rows.count(where: \.isNew)
    }

    /// 候補が 1 件も無いと分かったか（空の表示を出す）
    var isEmpty: Bool {
        hasLoadedCandidates && candidates.isEmpty
    }

    /// 行き先表示の「カプセル N個」（引き直しで外れた候補を除いた数。ホームのカードと同じ数え方）
    var capsuleCount: Int {
        guard let room else {
            return 0
        }
        return HomeRoomCard.capsuleCount(of: room)
    }

    /// 自分がルームの作成者か（設定の入口を出す）
    var isOwner: Bool {
        room?.ownerId == userID
    }

    /// ルームパネルに出すメンバー（参加の早い順。自分の準備OKは送っている途中の値を映す）
    var displayedMembers: [Identified<Member>] {
        guard let pendingReady else {
            return members
        }
        return members.map { member in
            guard member.id == userID else {
                return member
            }
            var value = member.value
            value.ready = pendingReady.value
            return Identified(id: member.id, value: value)
        }
    }

    /// 準備OKの人数（メンバーを読めていればその数（自分の送っている途中の準備OKを含む）、読めていなければルームの `readyCount`）
    var readyCount: Int {
        members.isEmpty ? room?.readyCount ?? 0 : displayedMembers.count(where: \.ready)
    }

    /// 自分が準備OKにしているか（送っている途中ならその値）
    var isReady: Bool {
        pendingReady?.value ?? members.first { $0.id == userID }?.ready ?? false
    }

    /// 「準備OK」「準備OKを取り消す」を出すか（F-30「open/unlocked のとき」。判定ではなくルームの `status` で決める）
    var showsReadyButton: Bool {
        room.map { Self.readyStatuses.contains($0.status) } ?? false
    }

    /// 「強制解禁（作成者）」を出すか（F-32「作成者だけ・未解禁のとき」。`status` が `open`。強制解禁が通った後は、購読が追いつく前でも出さない）
    var canForceUnlock: Bool {
        isOwner && room?.status == .open && !hasForceUnlocked
    }

    /// ルームパネルのヒント（F-31。抽選の後は nil）。解禁の文言は `status` が `unlocked` のときだけ（`ReadyHint`）
    var readyHint: ReadyHint? {
        guard let room else {
            return nil
        }
        return ReadyHint.make(UnlockInput(
            status: room.status,
            rule: room.settings.unlockRule,
            memberCount: memberCount,
            readyCount: readyCount,
            deadlineAt: room.settings.deadlineAt,
            forcedUnlock: room.forcedUnlock
        ))
    }

    /// メンバーの人数
    var memberCount: Int {
        members.isEmpty ? room?.memberCount ?? 0 : members.count
    }

    /// 自分の投稿の数（「あなたの投稿 n/上限件」の n）
    var myPostCount: Int {
        candidates.count { $0.postedBy == userID }
    }

    /// 候補を追加できる状態か（F-10「投稿できるのは open/unlocked のときだけ」）
    var acceptsCandidates: Bool {
        room.map { RoomCandidateRow.likeableStatuses.contains($0.status) } ?? false
    }

    /// 準備OKを変えられるルームの状態（02 の §2.1）
    static let readyStatuses: Set<RoomStatus> = [.open, .unlocked]

    /// 下部のボタンの状態。`drawn`・`closed` は「行き先きっぷを見る」（抽選の ID が無い壊れたルーム・読み込み中は出さない）
    var gachaButtonState: GachaButtonState? {
        switch room?.status {
        case .unlocked: .ready
        case .open: .waiting
        case .drawn, .closed: room?.currentDrawId.flatMap { $0.isEmpty ? nil : .result(drawID: $0) }
        case nil: nil
        }
    }
}
