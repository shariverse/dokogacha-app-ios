//
//  InMemoryServer+Repository.swift
//  Dokogacha
//
//  擬似のサーバーの購読と、クライアントから直接書いてよい項目（05 の §4）。
//  読み書きできる範囲は backend の `firestore.rules` と同じにする（メンバーだけが読める・自分の分だけ書ける）。
//  直接の書き込みは Firestore と同じく送った時点で返り、ルールで拒まれたら状態を変えずに `rejectedWrites` に残す。
//

import Foundation

extension InMemoryServer: RoomRepository {
    /// 準備OK・いいねを変えられる状態（02 の §2.1）
    static let interactiveStatuses: Set<RoomStatus> = [.open, .unlocked]

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        let statuses = Set(FirestoreRoomRepository.activeStatuses)
        return subscribe { server in
            guard server.signedInUserID == userID else {
                return .failure(Self.permissionDenied)
            }
            let rooms = server.rooms
                .filter { $0.value.room.memberIds.contains(userID) && statuses.contains($0.value.room.status) }
                .map { Identified(id: $0.key, value: $0.value.room) }
                .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
            return .value(rooms)
        }
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        // 無いルームはルールの `resource.data.memberIds` を読めず permission-denied になる（本番と同じく失敗で終わる）
        subscribe { server in
            server.readableRecord(roomID).map { Identified(id: roomID, value: $0.room) }
        }
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        subscribe { server in
            server.readableRecord(roomID).map { record in
                record.members
                    .map { Identified(id: $0.key, value: $0.value) }
                    .sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }
            }
        }
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        subscribe { server in
            server.readableRecord(roomID).map { record in
                record.candidates
                    .map { Identified(id: $0.key, value: $0.value) }
                    .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
            }
        }
    }

    func draw(roomID: String, drawID: String) -> AsyncStream<LiveUpdate<Draw?>> {
        // ルール: `draws/{drawId}` はメンバーだけが読める
        subscribe { server in
            server.readableRecord(roomID).map { $0.draws[drawID] }
        }
    }

    // 直接の書き込みは、Firestore と同じく送った時点で返る（`RoomRepository` の説明）。
    // ルールで拒まれたら状態を変えずに `rejectedWrites` に残し、投げない（購読には元の値のまま）

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        applyDirectWrite { try writeReady(ready, roomID: roomID, userID: userID, by: signedInUserID) }
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        applyDirectWrite { try writeLike(liked, candidateID: candidateID, roomID: roomID, userID: userID, by: signedInUserID) }
    }

    func markSeen(roomID: String, userID: String) async throws {
        applyDirectWrite { try writeSeen(roomID: roomID, userID: userID, by: signedInUserID) }
    }
}

// MARK: - 直接の書き込み（書いた人の uid を `authUserID` で受け取る。ほかのメンバーの端末 `Device` からも呼ぶ）

extension InMemoryServer {
    /// 直接の書き込みを行う。ルールで拒まれたら（`body` が投げたら）状態を変えずに `rejectedWrites` に残す
    func applyDirectWrite(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            rejectedWrites.append(AppError.wrapping(error))
        }
    }

    /// 準備OKを変える（ルールの検証つき）
    func writeReady(_ ready: Bool, roomID: String, userID: String, by authUserID: String?) throws {
        var record = try writableRecord(roomID, userID: userID, authUserID: authUserID)
        guard Self.interactiveStatuses.contains(record.room.status) else {
            throw Self.permissionDenied
        }
        record.members[userID]?.ready = ready
        // backend では members の更新で動く onMemberWrite が数え直して解禁を判定し直す
        rejudgeUnlock(&record)
        rooms[roomID] = record
    }

    /// いいねを付ける・外す（ルールの検証つき）
    func writeLike(_ liked: Bool, candidateID: String, roomID: String, userID: String, by authUserID: String?) throws {
        var record = try writableRecord(roomID, userID: userID, authUserID: authUserID)
        guard Self.interactiveStatuses.contains(record.room.status) else {
            throw Self.permissionDenied
        }
        guard var candidate = record.candidates[candidateID] else {
            throw AppError.server(ServerFailure(code: .notFound))
        }
        // 自分の投稿にはいいねできない（F-20）
        guard candidate.postedBy != userID else {
            throw Self.permissionDenied
        }
        // `arrayUnion`・`arrayRemove` と同じ: 付け直しても位置を変えず、外すときはすべて取り除く
        if liked {
            if !candidate.likedBy.contains(userID) {
                candidate.likedBy.append(userID)
            }
        } else {
            candidate.likedBy.removeAll { $0 == userID }
        }
        record.candidates[candidateID] = candidate
        rooms[roomID] = record
    }

    /// 最後に見た日時をサーバーの今の時刻にする（ルールの検証つき）
    func writeSeen(roomID: String, userID: String, by authUserID: String?) throws {
        var record = try writableRecord(roomID, userID: userID, authUserID: authUserID)
        record.members[userID]?.lastSeenAt = clock()
        rooms[roomID] = record
    }
}

private extension InMemoryServer {
    /// サインインしている人がルームのメンバーか（ルールの `isMember`）
    func isSignedInMember(of record: RoomRecord) -> Bool {
        guard let signedInUserID else {
            return false
        }
        return record.room.memberIds.contains(signedInUserID)
    }

    /// サインインしている人が読めるルーム。ルームが無い・メンバーでなければ権限のエラー（ルールの `isMember`）
    func readableRecord(_ roomID: String) -> LiveUpdate<RoomRecord> {
        guard let record = rooms[roomID], isSignedInMember(of: record) else {
            return .failure(Self.permissionDenied)
        }
        return .value(record)
    }

    /// 自分（`userID` が書いた人 `authUserID`）のメンバーのドキュメントがあるルーム。無ければ権限のエラー
    func writableRecord(_ roomID: String, userID: String, authUserID: String?) throws -> RoomRecord {
        guard userID == authUserID, let record = rooms[roomID], record.members[userID] != nil else {
            throw Self.permissionDenied
        }
        return record
    }
}

private extension LiveUpdate {
    /// 値を変える（失敗はそのまま）
    func map<Other: Sendable>(_ transform: (Value) -> Other) -> LiveUpdate<Other> {
        switch self {
        case let .value(value):
            .value(transform(value))
        case let .failure(error):
            .failure(error)
        }
    }
}
