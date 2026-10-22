//
//  RoomControlledRepository.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation

/// `RoomModelTests` で使う、いいね・準備OKの書き込みを止めておく・失敗させる窓口と、購読を決めた回数だけ失敗させる窓口と、
/// 候補・メンバーの購読にテストが決めた値を流す窓口（それ以外は擬似のサーバーのまま）
final class RoomControlledRepository: RoomRepository {
    let server: InMemoryServer
    /// true なら、`release()` を呼ぶまでいいねの書き込みを返さない（送っている途中を確かめる）
    var holdsLikes = false
    /// いいねの書き込みで投げるエラー（送る前に分かる失敗）
    var likeError: AppError?
    /// true なら、`releaseReady()` を呼ぶまで準備OKの書き込みを返さない
    var holdsReady = false
    /// 準備OKの書き込みで投げるエラー（送る前に分かる失敗）
    var readyError: AppError?
    /// 購読ごとに、最初に流す失敗（1 回の購読で 1 つ使う。無くなったら擬似のサーバーのまま）
    var roomFailures: [AppError] = []
    var memberFailures: [AppError] = []
    var candidateFailures: [AppError] = []
    /// いいねの書き込みを呼んだ回数
    private(set) var likeCallCount = 0
    /// 準備OKの書き込みを呼んだ回数
    private(set) var readyCallCount = 0
    /// 止めているいいねの書き込み
    private var heldLike: CheckedContinuation<Void, Never>?
    /// 止めている準備OKの書き込み
    private var heldReady: CheckedContinuation<Void, Never>?
    /// 候補の購読に、擬似のサーバーの代わりにテストが値を流す口（`feedCandidates()` で作る）
    private var candidateFeed: AsyncStream<LiveUpdate<[Identified<Candidate>]>>.Continuation?
    private var candidateFeedStream: AsyncStream<LiveUpdate<[Identified<Candidate>]>>?
    /// メンバーの購読に、擬似のサーバーの代わりにテストが値を流す口（`feedMembers()` で作る）
    private var memberFeed: AsyncStream<LiveUpdate<[Identified<Member>]>>.Continuation?
    private var memberFeedStream: AsyncStream<LiveUpdate<[Identified<Member>]>>?

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

    /// 準備OKの書き込みを止めているか
    var isHoldingReady: Bool {
        heldReady != nil
    }

    /// 止めている準備OKの書き込みを進める
    func releaseReady() {
        heldReady?.resume()
        heldReady = nil
    }

    /// これからの候補の購読を、擬似のサーバーではなく `sendCandidates` で流す値にする（届く順をテストで決めるため）
    func feedCandidates() {
        (candidateFeedStream, candidateFeed) = AsyncStream.makeStream(of: LiveUpdate<[Identified<Candidate>]>.self)
    }

    /// 候補の購読に、擬似のサーバーの今の候補を流す（`feedCandidates()` の後）
    func sendCandidates(roomID: String = DemoScenario.roomID) {
        sendCandidates(server.rooms[roomID]?.candidates ?? [:])
    }

    /// 候補の購読に、決めた候補を流す（古い値・サーバーに無い値を届けるため）
    func sendCandidates(_ values: [String: Candidate]) {
        let candidates = values
            .map { Identified(id: $0.key, value: $0.value) }
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
        candidateFeed?.yield(.value(candidates))
    }

    /// これからのメンバーの購読を、擬似のサーバーではなく `sendMembers` で流す値にする
    func feedMembers() {
        (memberFeedStream, memberFeed) = AsyncStream.makeStream(of: LiveUpdate<[Identified<Member>]>.self)
    }

    /// メンバーの購読に、擬似のサーバーの今のメンバーを流す（`feedMembers()` の後）
    func sendMembers(roomID: String = DemoScenario.roomID) {
        sendMembers(server.rooms[roomID]?.members ?? [:])
    }

    /// メンバーの購読に、決めたメンバーを流す（古い値・サーバーに無い値を届けるため）
    func sendMembers(_ values: [String: Member]) {
        let members = values
            .map { Identified(id: $0.key, value: $0.value) }
            .sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }
        memberFeed?.yield(.value(members))
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
        if let memberFeedStream {
            return memberFeedStream
        }
        return server.members(roomID: roomID)
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        guard candidateFailures.isEmpty else {
            return Self.failing(candidateFailures.removeFirst())
        }
        if let candidateFeedStream {
            return candidateFeedStream
        }
        return server.candidates(roomID: roomID)
    }

    func draw(roomID: String, drawID: String) -> AsyncStream<LiveUpdate<Draw?>> {
        server.draw(roomID: roomID, drawID: drawID)
    }

    func closedRooms(userID: String, limit: Int?) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        server.closedRooms(userID: userID, limit: limit)
    }

    func candidate(roomID: String, candidateID: String) -> AsyncStream<LiveUpdate<Identified<Candidate>?>> {
        server.candidate(roomID: roomID, candidateID: candidateID)
    }

    func pastIdeas(userID: String) -> AsyncStream<LiveUpdate<[Identified<PastIdea>]>> {
        server.pastIdeas(userID: userID)
    }

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        readyCallCount += 1
        if holdsReady {
            await withCheckedContinuation { heldReady = $0 }
        }
        if let readyError {
            throw readyError
        }
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
