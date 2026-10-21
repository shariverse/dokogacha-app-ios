//
//  InMemoryServer+Functions.swift
//  Dokogacha
//
//  擬似のサーバーの Callable Functions。backend の `users/service.ts`・`rooms/service.ts`・`rooms/logic.ts`・`rooms/input.ts` と
//  同じ順で検証し、同じ理由で失敗する（Emulator のテストと同じ観点を `InMemoryServerTests` で確かめる）。
//

import Foundation

extension InMemoryServer: FunctionsClient {
    /// 招待コードを作り直す最大の回数（backend の `MAX_INVITE_CODE_ATTEMPTS`）
    static let maxInviteCodeAttempts = 10
    /// 締切日時の下限に持たせる猶予（backend の `DEADLINE_EARLIEST_GRACE_MS`。5 分）
    static let deadlineEarliestGrace: TimeInterval = 5 * 60
    /// 参加できる状態（02 の F-04）
    static let joinableStatuses: Set<RoomStatus> = [.open, .unlocked]

    // MARK: ユーザー

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        let userID = try callerID()
        let displayName = try Self.trimmedText(request.displayName, length: DomainConstants.Limits.displayNameLength)
        if var existing = users[userID] {
            existing.displayName = displayName
            users[userID] = existing
            return SaveProfileResponse(displayName: displayName, avatarColor: existing.avatarColor, created: false)
        }
        let avatarColor = AvatarPalette.random(randomIndex: randomIndex)
        users[userID] = UserProfile(displayName: displayName, avatarColor: avatarColor, adFree: false, fcmTokens: [], createdAt: clock())
        return SaveProfileResponse(displayName: displayName, avatarColor: avatarColor, created: true)
    }

    // MARK: ルーム

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        let userID = try callerID()
        let now = clock()
        let name = try Self.trimmedText(request.name, length: DomainConstants.Limits.roomNameLength)
        guard DomainConstants.Limits.postLimitRange.contains(request.postLimit) else {
            throw Self.error(.invalidArgument)
        }
        let deadline = try Self.deadline(request, now: now)
        let profile = try requireProfile(userID)
        let code = try allocateInviteCode()

        let roomID = makeID()
        var record = RoomRecord(room: Room(
            name: name,
            ownerId: userID,
            inviteCode: code,
            status: .open,
            settings: RoomSettings(
                postLimit: request.postLimit,
                unlockRule: request.unlockRule,
                deadlineAt: deadline,
                likeMode: request.likeMode
            ),
            forcedUnlock: false,
            memberIds: [userID],
            memberCount: 1,
            readyCount: 0,
            candidateCount: 0,
            adFreeSponsor: profile.adFree ? AdFreeSponsor(uid: userID, displayName: profile.displayName) : nil,
            currentDrawId: nil,
            winnerCandidateId: nil,
            excludedCandidateIds: [],
            reroll: .initial,
            createdAt: now,
            drawnAt: nil,
            closedAt: nil
        ))
        record.members[userID] = Self.newMember(profile, role: .owner, now: now)
        inviteCodes[code] = InviteCodeEntry(roomId: roomID, createdAt: now)
        rooms[roomID] = record
        return CreateRoomResponse(roomId: roomID, inviteCode: code)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        let userID = try callerID()
        guard let code = InviteCode(request.inviteCode) else {
            throw Self.error(.inviteCodeNotFound)
        }
        let profile = try requireProfile(userID)
        guard let roomID = inviteCodes[code.value]?.roomId, var record = rooms[roomID] else {
            throw Self.error(.inviteCodeNotFound)
        }
        if record.members[userID] != nil {
            return JoinRoomResponse(roomId: roomID, alreadyMember: true)
        }
        // 状態を先に見る（drawn・closed の満員のルームは「もう行き先が決まっています」と出す。logic.ts の assertJoinable）
        guard Self.joinableStatuses.contains(record.room.status) else {
            throw Self.error(.roomAlreadyDecided)
        }
        guard record.room.memberCount < DomainConstants.Limits.maxMembers else {
            throw Self.error(.roomFull)
        }
        record.members[userID] = Self.newMember(profile, role: .member, now: clock())
        record.room.memberIds.append(userID)
        record.room.memberCount += 1
        if record.room.adFreeSponsor == nil, profile.adFree {
            record.room.adFreeSponsor = AdFreeSponsor(uid: userID, displayName: profile.displayName)
        }
        rooms[roomID] = record
        return JoinRoomResponse(roomId: roomID, alreadyMember: false)
    }

    func leaveRoom(_ request: RoomRequest) async throws {
        let userID = try callerID()
        let roomID = try Self.documentID(request.roomId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.room.ownerId != userID else {
            throw Self.error(.ownerCannotLeave)
        }
        try remove(userID, from: &record, notMember: .notRoomMember)
        rooms[roomID] = record
    }

    func removeMember(_ request: RemoveMemberRequest) async throws {
        let userID = try callerID()
        let roomID = try Self.documentID(request.roomId)
        let memberID = try Self.documentID(request.memberId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.room.ownerId == userID else {
            throw Self.error(.notRoomOwner)
        }
        guard memberID != record.room.ownerId else {
            throw Self.error(.cannotRemoveOwner)
        }
        try remove(memberID, from: &record, notMember: .memberNotFound)
        rooms[roomID] = record
    }

    // MARK: まだ backend に無い Callable（backend のタスクで足すときに、ここにも同じ検証を足す）

    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
        throw AppError(.notImplemented)
    }

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        throw AppError(.notImplemented)
    }

    func deleteCandidate(_ request: CandidateRequest) async throws {
        throw AppError(.notImplemented)
    }

    func forceUnlock(_ request: RoomRequest) async throws {
        throw AppError(.notImplemented)
    }

    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
        throw AppError(.notImplemented)
    }

    func proposeReroll(_ request: RoomRequest) async throws {
        throw AppError(.notImplemented)
    }

    func voteReroll(_ request: VoteRerollRequest) async throws {
        throw AppError(.notImplemented)
    }

    func closeRoom(_ request: RoomRequest) async throws {
        throw AppError(.notImplemented)
    }

    func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
        throw AppError(.notImplemented)
    }

    func reportCandidate(_ request: ReportCandidateRequest) async throws {
        throw AppError(.notImplemented)
    }

    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
        throw AppError(.notImplemented)
    }

    func deleteAccount() async throws {
        throw AppError(.notImplemented)
    }
}

// MARK: - 検証と状態の変更

private extension InMemoryServer {
    /// 前後の空白を取り除き、名前として受け付けるか確かめる（backend の `requireTrimmedText`）。
    ///
    /// 規則は `NameValidation`（入力欄と同じ判定）。受け付けなければ `invalid-argument`
    static func trimmedText(_ text: String, length: ClosedRange<Int>) throws -> String {
        guard let trimmed = NameValidation.validated(text, length: length) else {
            throw error(.invalidArgument)
        }
        return trimmed
    }

    /// ドキュメントの ID として使えるか確かめる（backend の `requireDocumentId`）
    static func documentID(_ id: String) throws -> String {
        guard FirestorePath.isValidDocumentID(id) else {
            throw error(.invalidArgument)
        }
        return id
    }

    /// 締切日時を確かめる（backend の `parseCreateRoomInput`。`deadline` のときだけ必須で、今から 1 時間後（5 分の猶予）〜30 日後）
    static func deadline(_ request: CreateRoomRequest, now: Date) throws -> Date? {
        guard request.unlockRule == .deadline else {
            guard request.deadlineAt == nil else {
                throw error(.invalidArgument)
            }
            return nil
        }
        guard let milliseconds = request.deadlineAt else {
            throw error(.invalidArgument)
        }
        let deadline = CallableTime.date(fromMilliseconds: milliseconds)
        let earliest = now.addingTimeInterval(DomainConstants.Limits.deadlineEarliestFromNow - deadlineEarliestGrace)
        let latest = now.addingTimeInterval(DomainConstants.Limits.deadlineLatestFromNow)
        guard earliest...latest ~= deadline else {
            throw error(.invalidArgument)
        }
        return deadline
    }

    /// 参加したばかりのメンバー（準備OKは false から。`lastSeenAt` は `joinedAt` と同じ。logic.ts の `newMemberDoc`）
    static func newMember(_ profile: UserProfile, role: MemberRole, now: Date) -> Member {
        Member(displayName: profile.displayName, avatarColor: profile.avatarColor, role: role, ready: false, joinedAt: now, lastSeenAt: now)
    }

    /// 呼んだ人のプロフィール。無ければ `profile-required`（S-01 で表示名を登録していない）
    func requireProfile(_ userID: String) throws -> UserProfile {
        guard let profile = users[userID] else {
            throw Self.error(.profileRequired)
        }
        return profile
    }

    /// 使われていない招待コードを作る（05 の §3「コード重複時は再生成」）
    func allocateInviteCode() throws -> String {
        for _ in 0..<Self.maxInviteCodeAttempts {
            let code = InviteCode.generate(randomIndex: randomIndex).value
            if inviteCodes[code] == nil {
                return code
            }
        }
        throw Self.error(.inviteCodeUnavailable)
    }

    /// メンバーをルームから外す（退出と削除で共通。backend の `removeFromRoom`）。
    ///
    /// メンバーを消し、`memberIds`・`memberCount`・`readyCount`（onMemberWrite の数え直しに当たる）を更新し、その人のいいねと
    /// 引き直しの投票を取り除き、広告非表示の購入者だったら残りのメンバーから参加の早い順に探し直す。候補は残す
    func remove(_ memberID: String, from record: inout RoomRecord, notMember: AppError.Reason) throws {
        guard record.members.removeValue(forKey: memberID) != nil else {
            throw Self.error(notMember)
        }
        record.room.memberIds.removeAll { $0 == memberID }
        record.room.memberCount -= 1
        // backend の leaveRoom・removeMember は readyCount に触らず、onMemberWrite（タスク 23）が数え直す。
        // 擬似のサーバーにはトリガーが無いので、その数え直しをここで行う
        record.room.readyCount = record.members.values.filter(\.ready).count
        record.room.reroll.votesFor.removeAll { $0 == memberID }
        record.room.reroll.votesAgainst.removeAll { $0 == memberID }
        for (candidateID, candidate) in record.candidates where candidate.likedBy.contains(memberID) {
            record.candidates[candidateID]?.likedBy.removeAll { $0 == memberID }
        }
        if record.room.adFreeSponsor?.uid == memberID {
            let next = record.members
                .sorted { $0.value.joinedAt < $1.value.joinedAt }
                .first { users[$0.key]?.adFree == true }
            record.room.adFreeSponsor = next.map { AdFreeSponsor(uid: $0.key, displayName: $0.value.displayName) }
        }
    }
}
