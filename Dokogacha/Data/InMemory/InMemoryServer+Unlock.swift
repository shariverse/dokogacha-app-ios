//
//  InMemoryServer+Unlock.swift
//  Dokogacha
//
//  擬似のサーバーの、解禁と設定の変更の Callable（backend の `unlock/service.ts` の `forceUnlock`・`settings/` の `updateRoomSettings`）。
//  backend の `unlock/logic.ts`・`settings/logic.ts` と同じ順で検証し、同じ理由で失敗する（`InMemoryServerUnlockTests` で確かめる）。
//  メンバーの書き込みの後の数え直し（`onMemberWrite`）と締切日時の判定（`checkDeadlines`）は `InMemoryServer+Triggers.swift`。
//

import Foundation

extension InMemoryServer {
    // MARK: この端末（サインインしている人）からの呼び出し（`FunctionsClient`）

    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
        try updateRoomSettings(request, by: signedInUserID)
    }

    func forceUnlock(_ request: RoomRequest) async throws {
        try forceUnlock(request, by: signedInUserID)
    }

    // MARK: 呼んだ人の uid を `callerID` で受け取る（ほかのメンバーの端末 `Device` からも呼ぶ）

    /// 作成者がルームの設定を変える（backend の `settings/service.ts` の `updateRoomSettings`。変更ルールは `settings/logic.ts`）。
    ///
    /// 入力の検証 → ルーム → 作成者か → `closed` でないか → ルーム名 → 投稿数（引き上げのみ）→ 解禁の条件（`open` のみ）
    /// → いいねの効き方（`open`・`unlocked` のみ）の順に確かめる。今と同じ値の項目は「変えない」とみなし、状態の決まりで断らない。
    /// 変える項目があれば、変えた後に解禁を判定し直す（`onMemberWrite` と同じ判定）
    func updateRoomSettings(_ request: UpdateRoomSettingsRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        let name = try Self.validatedSettingsName(request)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.room.ownerId == userID else {
            throw Self.error(.notRoomOwner)
        }
        guard record.room.status != .closed else {
            throw Self.error(.roomClosed)
        }
        let current = record.room
        var next = current
        if let name {
            next.name = name
        }
        if let postLimit = request.postLimit, postLimit != current.settings.postLimit {
            guard postLimit > current.settings.postLimit else {
                throw Self.error(.postLimitDecrease)
            }
            next.settings.postLimit = postLimit
        }
        (next.settings.unlockRule, next.settings.deadlineAt) = try Self.unlockRule(request, current: current, now: clock())
        if let likeMode = request.likeMode, likeMode != current.settings.likeMode {
            guard Self.interactiveStatuses.contains(current.status) else {
                throw Self.error(.likeModeLocked)
            }
            next.settings.likeMode = likeMode
        }
        guard next != current else {
            return
        }
        record.room = next
        rejudgeUnlock(&record)
        rooms[roomID] = record
    }

    /// 作成者が強制解禁する（backend の `unlock/service.ts` の `forceUnlock`。判定は `decideForceUnlock`）。
    ///
    /// 作成者だけ。`open` なら `forcedUnlock` を立てて `unlocked` にし、もう `unlocked` なら何もせずに成功する（`forcedUnlock` は立てない）。
    /// `drawn`・`closed` は `room-already-decided`
    func forceUnlock(_ request: RoomRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.room.ownerId == userID else {
            throw Self.error(.notRoomOwner)
        }
        switch record.room.status {
        case .open:
            record.room.forcedUnlock = true
            record.room.status = .unlocked
            rooms[roomID] = record
        case .unlocked:
            return
        case .drawn, .closed:
            throw Self.error(.roomAlreadyDecided)
        }
    }
}

private extension InMemoryServer {
    /// 設定の変更の入力のうち、状態によらない形・範囲を確かめる（backend の `parseUpdateRoomSettingsInput`）。
    ///
    /// ルーム名は前後の空白を取り除いた 1〜20 文字・投稿数は 1〜10・締切日時は 0 以上で、条件を「締切日時」以外にするときは送れない
    /// - Returns: 前後の空白を取り除いたルーム名（送られていなければ nil）
    static func validatedSettingsName(_ request: UpdateRoomSettingsRequest) throws -> String? {
        let name = try request.name.map { try trimmedText($0, length: DomainConstants.Limits.roomNameLength) }
        if let postLimit = request.postLimit, !DomainConstants.Limits.postLimitRange.contains(postLimit) {
            throw error(.invalidArgument)
        }
        if let deadlineAt = request.deadlineAt, deadlineAt < 0 || (request.unlockRule.map { $0 != .deadline } ?? false) {
            throw error(.invalidArgument)
        }
        return name
    }

    /// 設定の変更の後の解禁の条件と締切日時（backend の `settings/logic.ts` の `planUnlockRule`）。
    ///
    /// 条件を「締切日時」にするときは締切日時が要る（今が「締切日時」なら今の締切日時を引き継ぐ）。「締切日時」以外にするときは締切日時を消す。
    /// 今と違えば `open` のときだけ変えられ（`unlock-rule-locked`）、新しい締切日時は `createRoom` と同じ範囲（今から 1 時間後（5 分の猶予）〜30 日後）
    private static func unlockRule(
        _ request: UpdateRoomSettingsRequest,
        current: Room,
        now: Date
    ) throws -> (UnlockRule, Date?) {
        let rule = request.unlockRule ?? current.settings.unlockRule
        var deadline: Date?
        if rule == .deadline {
            deadline = request.deadlineAt.map(CallableTime.date(fromMilliseconds:))
                ?? (current.settings.unlockRule == .deadline ? current.settings.deadlineAt : nil)
            guard deadline != nil else {
                throw error(.invalidArgument)
            }
        } else if request.deadlineAt != nil {
            // 条件を送らずに締切日時だけを送ったが、今の条件が「締切日時」でない
            throw error(.invalidArgument)
        }
        guard rule != current.settings.unlockRule || deadline != current.settings.deadlineAt else {
            return (rule, deadline)
        }
        guard current.status == .open else {
            throw error(.unlockRuleLocked)
        }
        if let deadline, deadline != current.settings.deadlineAt {
            let earliest = now.addingTimeInterval(DomainConstants.Limits.deadlineEarliestFromNow - deadlineEarliestGrace)
            let latest = now.addingTimeInterval(DomainConstants.Limits.deadlineLatestFromNow)
            guard earliest...latest ~= deadline else {
                throw error(.invalidArgument)
            }
        }
        return (rule, deadline)
    }
}
