//
//  GachaModelRecoveryTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-13 で `drawGacha` が失敗として返ったが、サーバーでは書き込み済みだったとき（タイムアウト）に、止まらずに結果の演出へ進むことを確かめる（PR #67 の持ち越し）
struct GachaModelRecoveryTests {
    static let roomID = GachaModelTests.roomID

    /// 送っている途中に drawn が届き（見送る）、その後で失敗が返ったら、待機に戻した後で同じ抽選を再生する。
    /// 自分が回した抽選なので「◯◯さんが回しました！」に自分の名前は出さず、失敗のトーストも出さない
    @Test
    func failureAfterServerWroteReplaysDraw() async throws {
        let fixture = GachaModelTests.makeFixture(holdsClock: false)
        fixture.functions.failureAfterWriting = AppError(.network, code: .deadlineExceeded)
        fixture.functions.holdsAfterWriting = true
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        model.leverTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting && model.room?.status == .drawn })
        // 自分が送っている途中に届いた drawn では、まだ再生しない
        #expect(model.drawID == nil)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.phase == .opened })
        let room = try #require(fixture.server.rooms[Self.roomID]?.room)
        #expect(model.drawID == room.currentDrawId)
        #expect(model.winnerCandidateID == room.winnerCandidateId)
        #expect(model.drawnByName == nil)
        #expect(model.caption == .landed)
        #expect(fixture.toasts.current == nil)
        #expect(!model.isDrawing)
        #expect(fixture.server.rooms[Self.roomID]?.draws.count == 1)
    }

    /// 失敗が返った後で drawn が届いたときも、届いた時点で再生する（そのときは失敗のトーストが先に出ている）
    @Test
    func failureBeforeDrawnArrivesReplaysLater() async throws {
        let fixture = GachaModelTests.makeFixture(holdsClock: false)
        let repository = DrawDelayedRepository(server: fixture.server)
        let model = GachaModel(
            roomID: Self.roomID,
            userID: DemoScenario.myUserID,
            repository: repository,
            functions: fixture.functions,
            toasts: fixture.toasts,
            seenDraws: fixture.seenDraws,
            sleep: fixture.clock.sleep,
            now: fixture.clock.now,
            resubscribeDelay: RoomModelTests.immediateResubscribe
        )
        fixture.functions.failureAfterWriting = AppError(.network, code: .deadlineExceeded)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await GachaModelTests.waitUntilLoaded(model))

        repository.holdsRoom = true
        await model.turnLever()
        #expect(model.phase == .idle)
        #expect(fixture.toasts.current?.text == "通信できませんでした。もう一度回してください")
        #expect(model.room?.status == .unlocked)

        repository.releaseRoom()
        #expect(await AsyncTestSupport.eventually { model.phase == .opened })
        #expect(model.drawID == fixture.server.rooms[Self.roomID]?.room.currentDrawId)
        #expect(model.drawnByName == nil)
    }
}

/// ルームの購読の値を止めておける窓口（止めている間に届いた値は、`releaseRoom()` で最新の 1 つだけを流す）
final class DrawDelayedRepository: RoomRepository {
    let server: InMemoryServer
    /// true なら、ルームの値を流さずに覚えておく
    var holdsRoom = false
    private var heldRoom: Identified<Room>??
    private var roomFeed: AsyncStream<LiveUpdate<Identified<Room>?>>.Continuation?
    private var forwarding: Task<Void, Never>?

    init(server: InMemoryServer) {
        self.server = server
    }

    deinit {
        forwarding?.cancel()
    }

    /// 止めていたルームの値を流し、これからは止めずに流す
    func releaseRoom() {
        holdsRoom = false
        if let heldRoom {
            roomFeed?.yield(.value(heldRoom))
            self.heldRoom = nil
        }
    }

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        server.activeRooms(userID: userID)
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<Identified<Room>?>.self)
        roomFeed = continuation
        let source = server.room(id: roomID)
        forwarding = Task { [weak self] in
            for await update in source {
                guard let self else {
                    return
                }
                if self.holdsRoom, case let .value(value) = update {
                    self.heldRoom = .some(value)
                } else {
                    continuation.yield(update)
                }
            }
            continuation.finish()
        }
        return stream
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        server.members(roomID: roomID)
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        server.candidates(roomID: roomID)
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
        try await server.setReady(ready, roomID: roomID, userID: userID)
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        try await server.setLike(liked, candidateID: candidateID, roomID: roomID, userID: userID)
    }

    func markSeen(roomID: String, userID: String) async throws {
        try await server.markSeen(roomID: roomID, userID: userID)
    }
}
