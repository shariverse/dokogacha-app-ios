//
//  InMemoryServer+Repository.swift
//  Dokogacha
//
//  擬似のサーバーの購読と、クライアントから直接書いてよい項目（05 の §4）。
//  読み書きできる範囲は backend の `firestore.rules` と同じにする（メンバーだけが読める・自分の分だけ書ける）。
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
        subscribe { server in
            guard let record = server.rooms[roomID] else {
                return .value(nil)
            }
            guard server.isSignedInMember(of: record) else {
                return .failure(Self.permissionDenied)
            }
            return .value(Identified(id: roomID, value: record.room))
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

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        var record = try writableRecord(roomID, userID: userID)
        guard Self.interactiveStatuses.contains(record.room.status) else {
            throw Self.permissionDenied
        }
        record.members[userID]?.ready = ready
        // `readyCount` は backend では onMemberWrite（タスク 23）が数え直す。解禁の判定はそのタスクで足す
        record.room.readyCount = record.members.values.filter(\.ready).count
        rooms[roomID] = record
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        var record = try writableRecord(roomID, userID: userID)
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
        candidate.likedBy.removeAll { $0 == userID }
        if liked {
            candidate.likedBy.append(userID)
        }
        record.candidates[candidateID] = candidate
        rooms[roomID] = record
    }

    func markSeen(roomID: String, userID: String) async throws {
        var record = try writableRecord(roomID, userID: userID)
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

    /// サインインしている人が読めるルーム。メンバーでなければ権限のエラー
    func readableRecord(_ roomID: String) -> LiveUpdate<RoomRecord> {
        guard let record = rooms[roomID], isSignedInMember(of: record) else {
            return .failure(Self.permissionDenied)
        }
        return .value(record)
    }

    /// 自分（`userID` がサインインしている人）のメンバーのドキュメントがあるルーム。無ければ権限のエラー
    func writableRecord(_ roomID: String, userID: String) throws -> RoomRecord {
        guard userID == signedInUserID, let record = rooms[roomID], record.members[userID] != nil else {
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
