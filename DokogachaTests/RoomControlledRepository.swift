//
//  RoomControlledRepository.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation

/// `RoomModelTests` で使う、いいねの書き込みを止めておく・失敗させる窓口と、購読を決めた回数だけ失敗させる窓口（それ以外は擬似のサーバーのまま）
final class RoomControlledRepository: RoomRepository {
    let server: InMemoryServer
    /// true なら、`release()` を呼ぶまでいいねの書き込みを返さない（送っている途中を確かめる）
    var holdsLikes = false
    /// いいねの書き込みで投げるエラー（送る前に分かる失敗）
    var likeError: AppError?
    /// 購読ごとに、最初に流す失敗（1 回の購読で 1 つ使う。無くなったら擬似のサーバーのまま）
    var roomFailures: [AppError] = []
    var memberFailures: [AppError] = []
    var candidateFailures: [AppError] = []
    /// いいねの書き込みを呼んだ回数
    private(set) var likeCallCount = 0
    /// 止めているいいねの書き込み
    private var heldLike: CheckedContinuation<Void, Never>?

    init(server: InMemoryServer) {
        self.server = server
    }

    /// いいねの書き込みを止めているか
    var isHoldingLike: Bool {
        heldLike != nil
    }

    /// 止めているいいねの書き込みを進める
    func release() {
        heldLike?.resume()
        heldLike = nil
    }

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        server.activeRooms(userID: userID)
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        guard roomFailures.isEmpty else {
            return Self.failing(roomFailures.removeFirst())
        }
        return server.room(id: roomID)
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        guard memberFailures.isEmpty else {
            return Self.failing(memberFailures.removeFirst())
        }
        return server.members(roomID: roomID)
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        guard candidateFailures.isEmpty else {
            return Self.failing(candidateFailures.removeFirst())
        }
        return server.candidates(roomID: roomID)
    }

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        try await server.setReady(ready, roomID: roomID, userID: userID)
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        likeCallCount += 1
        if holdsLikes {
            await withCheckedContinuation { heldLike = $0 }
        }
        if let likeError {
            throw likeError
        }
        try await server.setLike(liked, candidateID: candidateID, roomID: roomID, userID: userID)
    }

    func markSeen(roomID: String, userID: String) async throws {
        try await server.markSeen(roomID: roomID, userID: userID)
    }

    /// 失敗を 1 つ流して終わる購読
    private static func failing<Value: Sendable>(_ error: AppError) -> AsyncStream<LiveUpdate<Value>> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<Value>.self)
        continuation.yield(.failure(error))
        continuation.finish()
        return stream
    }
}
