//
//  InMemoryServer+Functions.swift
//  Dokogacha
//
//  擬似のサーバーの Callable Functions。backend の `users/`・`rooms/`・`candidates/` の `service.ts`・`logic.ts`・`input.ts` と
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
    /// 候補を追加・削除できる状態（02 の §2.1。backend の `CANDIDATE_EDITABLE_STATUSES`）
    static let candidateEditableStatuses: Set<RoomStatus> = [.open, .unlocked]

    // MARK: この端末（サインインしている人）からの呼び出し

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        try saveProfile(request, by: signedInUserID)
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        try createRoom(request, by: signedInUserID)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        try joinRoom(request, by: signedInUserID)
    }

    func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
        try previewRoom(request, by: signedInUserID)
    }

    func leaveRoom(_ request: RoomRequest) async throws {
        try leaveRoom(request, by: signedInUserID)
    }

    func removeMember(_ request: RemoveMemberRequest) async throws {
        try removeMember(request, by: signedInUserID)
    }

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        try addCandidate(request, by: signedInUserID)
    }

    func deleteCandidate(_ request: CandidateRequest) async throws {
        try deleteCandidate(request, by: signedInUserID)
    }

    // MARK: ユーザー（呼んだ人の uid を `callerID` で受け取る。ほかのメンバーの端末 `Device` からも呼ぶ）

    func saveProfile(_ request: SaveProfileRequest, by callerID: String?) throws -> SaveProfileResponse {
        let userID = try Self.requireCaller(callerID)
        let displayName = try Self.trimmedText(request.displayName, length: DomainConstants.Limits.displayNameLength)
        if var existing = users[userID] {
            existing.displayName = displayName
            users[userID] = existing
            // backend では `users/{uid}` の更新で動く `onUserProfileUpdate` が、参加中のルームの複製に反映する
            syncProfileCopies(of: userID)
            return SaveProfileResponse(displayName: displayName, avatarColor: existing.avatarColor, created: false)
        }
        let avatarColor = AvatarPalette.random(randomIndex: randomIndex)
        users[userID] = UserProfile(displayName: displayName, avatarColor: avatarColor, adFree: false, fcmTokens: [], createdAt: clock())
        return SaveProfileResponse(displayName: displayName, avatarColor: avatarColor, created: true)
    }

    // MARK: ルーム

    func createRoom(_ request: CreateRoomRequest, by callerID: String?) throws -> CreateRoomResponse {
        let userID = try Self.requireCaller(callerID)
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

    func joinRoom(_ request: JoinRoomRequest, by callerID: String?) throws -> JoinRoomResponse {
        let userID = try Self.requireCaller(callerID)
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
        try Self.assertJoinable(record.room)
        record.members[userID] = Self.newMember(profile, role: .member, now: clock())
        record.room.memberIds.append(userID)
        record.room.memberCount += 1
        if record.room.adFreeSponsor == nil, profile.adFree {
            record.room.adFreeSponsor = AdFreeSponsor(uid: userID, displayName: profile.displayName)
        }
        // backend では members の作成で動く onMemberWrite が判定し直す（解禁済みでも新しい人は準備OKでないので open に戻る。F-04）
        rejudgeUnlock(&record)
        rooms[roomID] = record
        return JoinRoomResponse(roomId: roomID, alreadyMember: false)
    }

    /// 参加する前にルームを確かめる（backend の `previewRoom`）。何も書き換えない。
    ///
    /// 招待コードの正規化・コードからルームを引く・参加できるかの判定（`assertJoinable`）は `joinRoom` と同じで、断る理由も同じ。
    /// すでにメンバーなら、状態・人数によらず `alreadyMember` を返す。表示名の登録は確かめない（読むだけなので）
    func previewRoom(_ request: PreviewRoomRequest, by callerID: String?) throws -> RoomPreview {
        let userID = try Self.requireCaller(callerID)
        guard let code = InviteCode(request.inviteCode),
              let roomID = inviteCodes[code.value]?.roomId,
              let record = rooms[roomID] else {
            throw Self.error(.inviteCodeNotFound)
        }
        let alreadyMember = record.members[userID] != nil
        if !alreadyMember {
            try Self.assertJoinable(record.room)
        }
        return RoomPreview(
            roomId: roomID,
            name: record.room.name,
            ownerName: record.members[record.room.ownerId]?.displayName,
            memberCount: record.room.memberCount,
            candidateCount: record.room.candidateCount,
            status: record.room.status,
            alreadyMember: alreadyMember
        )
    }

    func leaveRoom(_ request: RoomRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
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

    func removeMember(_ request: RemoveMemberRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
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

    // MARK: 候補

    /// 候補を追加する（backend の `candidates/service.ts` の `addCandidate`。判定の順は `logic.ts` の `decideAddCandidate`）。
    ///
    /// 入力の検証 → ルーム → メンバー → 状態（open・unlocked）→ 重複（作らずに既存の候補を返す。自分の投稿でも・上限でも）
    /// → 自分の投稿数の上限 → ルームの候補の上限（200 件）の順に確かめ、`colorIndex` は既存の最大 + 1 にする
    func addCandidate(_ request: AddCandidateRequest, by callerID: String?) throws -> AddCandidateResult {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard let place = CandidateRules.validatedPlace(request.place),
              let note = CandidateRules.validatedNote(request.note) else {
            throw Self.error(.invalidArgument)
        }
        let url = try Self.candidateURL(request.url)
        let fromPastIdeaID = try request.fromPastIdeaId.map(Self.documentID)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard let member = record.members[userID] else {
            throw Self.error(.notRoomMember)
        }
        guard Self.candidateEditableStatuses.contains(record.room.status) else {
            throw Self.error(.roomAlreadyDecided)
        }
        let existing = record.candidates.map { Identified(id: $0.key, value: $0.value) }
        if let duplicate = CandidateRules.duplicate(of: place, in: existing) {
            return .duplicate(of: duplicate)
        }
        guard existing.count(where: { $0.postedBy == userID }) < record.room.settings.postLimit else {
            throw Self.error(.postLimitReached)
        }
        guard existing.count < DomainConstants.Limits.maxCandidates else {
            throw Self.error(.roomCandidatesFull)
        }
        let candidateID = makeID()
        record.candidates[candidateID] = Candidate(
            place: place,
            category: request.category,
            note: note,
            url: url,
            postedBy: userID,
            postedByName: member.displayName,
            colorIndex: CandidateRules.nextColorIndex(existing.map(\.colorIndex)),
            likedBy: [],
            fromPastIdeaId: fromPastIdeaID,
            createdAt: clock()
        )
        record.room.candidateCount += 1
        rooms[roomID] = record
        return .added(candidateID: candidateID)
    }

    /// 候補を削除する（backend の `deleteCandidate`。投稿した人か作成者だけ・open・unlocked のときだけ。いいねも一緒に消える）。
    ///
    /// ガチャで当選した候補（今の当選・引き直しで除外した前の当選・抽選の記録が指す候補）は `candidate-drawn`（backend の `isDrawnCandidate`）
    func deleteCandidate(_ request: CandidateRequest, by callerID: String?) throws {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        let candidateID = try Self.documentID(request.candidateId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.members[userID] != nil else {
            throw Self.error(.notRoomMember)
        }
        guard let candidate = record.candidates[candidateID] else {
            throw Self.error(.candidateNotFound)
        }
        guard candidate.postedBy == userID || record.room.ownerId == userID else {
            throw Self.error(.notCandidateOwner)
        }
        guard Self.candidateEditableStatuses.contains(record.room.status) else {
            throw Self.error(.roomAlreadyDecided)
        }
        let referencedByDraw = record.draws.values.contains { $0.candidateId == candidateID }
        guard !referencedByDraw, !CandidatePermission.isDrawn(candidateID: candidateID, in: record.room) else {
            throw Self.error(.candidateDrawn)
        }
        record.candidates[candidateID] = nil
        record.room.candidateCount -= 1
        rooms[roomID] = record
    }

    // MARK: まだ backend に無い Callable（backend のタスクで足すときに、ここにも同じ検証を足す）

    func closeRoom(_ request: RoomRequest) async throws {
        try closeRoom(request, by: signedInUserID)
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

// MARK: - 入力の検証（ほかのファイルの Callable（`InMemoryServer+Unlock.swift`）でも使う）

extension InMemoryServer {
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
}

// MARK: - 検証と状態の変更

private extension InMemoryServer {
    /// 参考 URL（任意）を確かめる（backend の `parseUrl`）。無い・空白だけなら nil、受け付けなければ `invalid-argument`
    static func candidateURL(_ text: String?) throws -> String? {
        switch CandidateRules.validatedURL(text) {
        case .none:
            nil
        case let .valid(url):
            url
        case .invalid:
            throw error(.invalidArgument)
        }
    }

    /// まだメンバーでない人がルームに参加できるか確かめる（backend の `logic.ts` の `assertJoinable`。`joinRoom`・`previewRoom` で共通）。
    ///
    /// 状態を先に見る（drawn・closed の満員のルームは「もう行き先が決まっています」と出す）
    static func assertJoinable(_ room: Room) throws {
        guard joinableStatuses.contains(room.status) else {
            throw error(.roomAlreadyDecided)
        }
        guard room.memberCount < DomainConstants.Limits.maxMembers else {
            throw error(.roomFull)
        }
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
    /// メンバーを消し、`memberIds` と、`memberCount`・`readyCount`・`status`（onMemberWrite の数え直しと解禁の判定に当たる）を更新し、その人のいいねと
    /// 引き直しの投票を取り除き（投票中なら判定し直し）、広告非表示の購入者だったら残りのメンバーから参加の早い順（同着は uid の順）に探し直す。候補は残す
    func remove(_ memberID: String, from record: inout RoomRecord, notMember: AppError.Reason) throws {
        guard record.members.removeValue(forKey: memberID) != nil else {
            throw Self.error(notMember)
        }
        record.room.memberIds.removeAll { $0 == memberID }
        // backend の leaveRoom・removeMember は readyCount に触らず、members の削除で動く onMemberWrite が数え直して
        // 解禁を判定し直す。擬似のサーバーではここで続けて行う
        rejudgeUnlock(&record)
        record.room.reroll.votesFor.removeAll { $0 == memberID }
        record.room.reroll.votesAgainst.removeAll { $0 == memberID }
        // 投票中なら、残りのメンバーで判定し直す（賛成が過半数になれば、その場で可決する。backend の `planAfterLeave`）
        Self.settleReroll(in: &record)
        for (candidateID, candidate) in record.candidates where candidate.likedBy.contains(memberID) {
            record.candidates[candidateID]?.likedBy.removeAll { $0 == memberID }
        }
        if record.room.adFreeSponsor?.uid == memberID {
            // backend の `orderBy("joinedAt")` と同じ順（同着は Firestore が暗黙に付けるドキュメントの ID の順）
            let next = record.members
                .sorted { ($0.value.joinedAt, $0.key) < ($1.value.joinedAt, $1.key) }
                .first { users[$0.key]?.adFree == true }
            record.room.adFreeSponsor = next.map { AdFreeSponsor(uid: $0.key, displayName: $0.value.displayName) }
        }
    }
}
