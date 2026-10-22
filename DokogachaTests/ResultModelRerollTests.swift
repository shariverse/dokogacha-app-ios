//
//  ResultModelRerollTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-14 の引き直し（F-43）の提案・投票（`ResultModel`）を擬似のサーバーで動かして確かめる。
///
/// デモのルームは `several-rooms` の解禁済みのルーム（週末のランチ。自分・はるか・そうたの 3 人）。はるかの端末から回した後に開く
struct ResultModelRerollTests {
    /// サーバー・画面の状態・トースト
    struct Fixture {
        let server: InMemoryServer
        let model: ResultModel
        let toasts: DGToastCenter
        let drawID: String
    }

    static func makeFixture() async throws -> Fixture {
        let (server, drawID) = try await ResultModelTests.drawnServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = ResultModel(
            roomID: ResultModelTests.roomID,
            drawID: drawID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: toasts,
            mapOpener: RecordingMapOpener(),
            resubscribeDelay: RoomModelTests.immediateResubscribe
        )
        return Fixture(server: server, model: model, toasts: toasts, drawID: drawID)
    }

    /// 提案すると、自分は自動で賛成になり「賛成を集めています…（1/3人）」の投票中になる
    @Test
    func proposeStartsVotingWithMyApproval() async throws {
        let fixture = try await Self.makeFixture()
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.rerollPanel == .proposable })

        await fixture.model.proposeReroll()
        #expect(fixture.server.rooms[ResultModelTests.roomID]?.room.reroll.proposedBy == DemoScenario.myUserID)
        #expect(await AsyncTestSupport.eventually {
            fixture.model.rerollPanel == .voting(approvals: 1, memberCount: 3, myVote: .approve)
        })
        #expect(!fixture.model.isSendingReroll)
        #expect(fixture.toasts.current == nil)
    }

    /// ほかの人の提案に反対・賛成で投票でき、票を変えられる。過半数（2/3）で可決して「もう一度引けます」になる
    @Test
    func voteChangesAndPasses() async throws {
        let fixture = try await Self.makeFixture()
        try await fixture.server.device(of: ResultModelTests.haruka).proposeReroll(RoomRequest(roomId: ResultModelTests.roomID))
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually {
            fixture.model.rerollPanel == .voting(approvals: 1, memberCount: 3, myVote: nil)
        })

        await fixture.model.vote(approve: false)
        #expect(await AsyncTestSupport.eventually {
            fixture.model.rerollPanel == .voting(approvals: 1, memberCount: 3, myVote: .reject)
        })
        await fixture.model.vote(approve: true)
        #expect(await AsyncTestSupport.eventually { fixture.model.rerollPanel == .passed })
        let room = try #require(fixture.server.rooms[ResultModelTests.roomID]?.room)
        #expect(room.status == .unlocked)
        #expect(room.excludedCandidateIds == [room.winnerCandidateId].compactMap(\.self))
    }

    /// 今の票と同じ票は送らない。投票中でなければ送らない
    @Test
    func doesNotSendSameVoteOrOutsideVoting() async throws {
        let fixture = try await Self.makeFixture()
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.rerollPanel == .proposable })
        await fixture.model.vote(approve: true)
        #expect(fixture.server.rooms[ResultModelTests.roomID]?.room.reroll == .initial)

        await fixture.model.proposeReroll()
        #expect(await AsyncTestSupport.eventually { fixture.model.rerollPanel != .proposable })
        await fixture.model.vote(approve: true)
        #expect(fixture.server.rooms[ResultModelTests.roomID]?.room.reroll.votesFor == [DemoScenario.myUserID])
        #expect(fixture.toasts.current == nil)
    }

    /// サーバーに断られたら（画面を開いている間にほかの人が提案して否決された）、その文言のトーストを出す
    @Test
    func showsToastWhenServerRejects() async throws {
        let fixture = try await Self.makeFixture()
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.rerollPanel == .proposable })

        // 購読がまだ届けていない（画面は提案前のまま）うちに、サーバーでは権利を使い終えている
        fixture.server.rooms[ResultModelTests.roomID]?.room.reroll = RerollState(
            used: true, proposedBy: ResultModelTests.haruka, proposedAt: nil, votesFor: [], votesAgainst: [], status: .rejected
        )
        await fixture.model.proposeReroll()
        #expect(fixture.toasts.current?.text == "引き直しは使用済みです")
        #expect(await AsyncTestSupport.eventually { fixture.model.rerollPanel == .used })
    }

    /// closed のルームは閲覧のみで、引き直しの欄を出さない
    @Test
    func hiddenWhenClosed() async throws {
        let fixture = try await Self.makeFixture()
        fixture.server.rooms[ResultModelTests.roomID]?.room.status = .closed
        let observing = Task { await fixture.model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { fixture.model.loadState == .loaded })
        #expect(fixture.model.rerollPanel == .hidden)
        await fixture.model.proposeReroll()
        #expect(fixture.server.rooms[ResultModelTests.roomID]?.room.reroll == .initial)
    }
}
