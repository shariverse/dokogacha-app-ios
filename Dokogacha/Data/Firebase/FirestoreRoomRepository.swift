//
//  FirestoreRoomRepository.swift
//  Dokogacha
//

import Foundation

/// Firestore の `RoomRepository`。購読は `addSnapshotListener` を `AsyncStream` にしたもの（05 の §6）。
///
/// SDK には `FirestoreGateway` を通して触る（テストでは擬似の Gateway に差し替える）。
/// 書き込みは 05 の §4 のとおり「自分の準備OK」「いいね」「lastSeenAt」だけで、セキュリティルールが同じ範囲を許す。
final class FirestoreRoomRepository: RoomRepository {
    /// ホームに出す、進行中のルームの状態（`closed` 以外。`firestore.indexes.json` の `memberIds`＋`status`＋`createdAt` の索引を使う）
    static let activeStatuses: [RoomStatus] = [.open, .unlocked, .drawn]

    private let gateway: any FirestoreGateway

    /// SDK の窓口を受け取って作る
    init(gateway: any FirestoreGateway) {
        self.gateway = gateway
    }

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        let query = FirestoreQuerySpec(
            collectionPath: FirestorePath.rooms,
            filters: [
                .arrayContains(field: "memberIds", value: userID),
                .isIn(field: "status", values: Self.activeStatuses.map(\.rawValue))
            ],
            order: .init(field: "createdAt", descending: true)
        )
        return FirestoreSubscription.query(query, gateway: gateway) { FirestoreDecoding.list($0, FirestoreDecoding.room) }
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        FirestoreSubscription.document(FirestorePath.room(roomID), gateway: gateway) { document in
            try document.map(FirestoreDecoding.room)
        }
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        let query = FirestoreQuerySpec(
            collectionPath: FirestorePath.members(roomID),
            order: .init(field: "joinedAt", descending: false)
        )
        return FirestoreSubscription.query(query, gateway: gateway) { FirestoreDecoding.list($0, FirestoreDecoding.member) }
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        let query = FirestoreQuerySpec(
            collectionPath: FirestorePath.candidates(roomID),
            order: .init(field: "createdAt", descending: true)
        )
        return FirestoreSubscription.query(query, gateway: gateway) { FirestoreDecoding.list($0, FirestoreDecoding.candidate) }
    }

    func draw(roomID: String, drawID: String) -> AsyncStream<LiveUpdate<Draw?>> {
        FirestoreSubscription.document(FirestorePath.draw(drawID, roomID: roomID), gateway: gateway) { document in
            try document.map(FirestoreDecoding.draw)
        }
    }

    // 直接の書き込みは送った時点で返る（`RoomRepository` の説明）。Firestore の実装では送る前に分かる失敗は無いので投げない

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        gateway.update(path: FirestorePath.member(userID, roomID: roomID), fields: ["ready": .bool(ready)])
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        let change: FirestoreFieldUpdate = liked ? .arrayUnion([userID]) : .arrayRemove([userID])
        gateway.update(path: FirestorePath.candidate(candidateID, roomID: roomID), fields: ["likedBy": change])
    }

    func markSeen(roomID: String, userID: String) async throws {
        gateway.update(path: FirestorePath.member(userID, roomID: roomID), fields: ["lastSeenAt": .serverTimestamp])
    }
}

/// `FirestoreGateway` の購読を `AsyncStream` にする（`RoomRepository` と `AuthService` で共通）。
///
/// - スナップショットが届くたびにモデルにして `.value` を流す。古い値は要らないので、読む側が遅れたら最新の 1 つだけを残す
/// - 購読が失敗したら `.failure` を流して終わる（SDK はリスナーを外している）
/// - 読む側が `Task` を cancel する・ストリームを捨てると、`onTermination` で MainActor に戻ってリスナーを外す
enum FirestoreSubscription {
    /// ドキュメントを購読する。`transform` が投げたら（読めないドキュメント）`.failure(.unreadableData)` を流して購読は続ける。
    ///
    /// `waitsForServerWhenMissing` が true なら、キャッシュから届いた「無い」は流さず、サーバーの返事を待つ
    /// （オフラインでキャッシュが空のとき、まだ確かめていない「無い」を「本当に無い」と取り違えないため。プロフィールで使う）
    static func document<Value: Sendable>(
        _ path: String,
        gateway: any FirestoreGateway,
        waitsForServerWhenMissing: Bool = false,
        transform: @escaping (FirestoreDocument?) throws -> Value
    ) -> AsyncStream<LiveUpdate<Value>> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<Value>.self, bufferingPolicy: .bufferingNewest(1))
        // キャッシュの「無い」の後にサーバーの「無い」が来ても中身は変わらないので、メタデータの変化も受け取る
        let token = gateway.listenDocument(path: path, includeMetadataChanges: waitsForServerWhenMissing) { result in
            if waitsForServerWhenMissing, case let .success(snapshot) = result, snapshot.document == nil, snapshot.isFromCache {
                return
            }
            deliver(result.map(\.document), to: continuation, transform: transform)
        }
        continuation.onTermination = { _ in
            Task { @MainActor in token.remove() }
        }
        return stream
    }

    /// クエリを購読する
    static func query<Value: Sendable>(
        _ query: FirestoreQuerySpec,
        gateway: any FirestoreGateway,
        transform: @escaping ([FirestoreDocument]) throws -> Value
    ) -> AsyncStream<LiveUpdate<Value>> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<Value>.self, bufferingPolicy: .bufferingNewest(1))
        let token = gateway.listenQuery(query) { result in
            deliver(result, to: continuation, transform: transform)
        }
        continuation.onTermination = { _ in
            Task { @MainActor in token.remove() }
        }
        return stream
    }

    /// SDK の結果をストリームに流す
    private static func deliver<Snapshot, Value: Sendable>(
        _ result: Result<Snapshot, ServerFailure>,
        to continuation: AsyncStream<LiveUpdate<Value>>.Continuation,
        transform: (Snapshot) throws -> Value
    ) {
        switch result {
        case let .success(snapshot):
            do {
                continuation.yield(.value(try transform(snapshot)))
            } catch {
                continuation.yield(.failure(AppError(.unreadableData)))
            }
        case let .failure(failure):
            continuation.yield(.failure(AppError.server(failure)))
            continuation.finish()
        }
    }
}
