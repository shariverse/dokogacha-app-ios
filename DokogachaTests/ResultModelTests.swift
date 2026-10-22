//
//  ResultModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing
import UIKit

/// S-14 結果（`ResultModel`）を擬似のサーバーで動かし、行き先きっぷの値（F-42）・レア当選・閲覧のみ・マップで開く・共有画像を確かめる。
///
/// デモのルームは `several-rooms` の解禁済みのルーム（週末のランチ。自分・はるか・そうた、候補 3 件）。はるかの端末から回す
struct ResultModelTests {
    static let roomID = DemoScenario.unlockedRoomID
    static let haruka = "demo-haruka"

    /// はるかが回した後のサーバーと抽選の ID
    static func drawnServer() async throws -> (InMemoryServer, String) {
        let server = InMemoryServer.demo(.severalRooms) { RoomModelTests.now }
        let response = try await server.device(of: haruka).drawGacha(RoomRequest(roomId: roomID))
        return (server, response.drawId)
    }

    static func makeModel(
        _ server: InMemoryServer,
        drawID: String,
        mapOpener: any MapOpener = RecordingMapOpener()
    ) -> ResultModel {
        ResultModel(
            roomID: roomID,
            drawID: drawID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: UnavailableServer(),
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            mapOpener: mapOpener,
            resubscribeDelay: RoomModelTests.immediateResubscribe
        )
    }

    /// 抽選の記録・ルーム・候補がそろったら、きっぷに当選した候補の場所・投稿者・いいね数・当選確率・抽選日を出す
    @Test
    func ticketShowsWinnerAndDraw() async throws {
        let (server, drawID) = try await Self.drawnServer()
        let model = Self.makeModel(server, drawID: drawID)
        #expect(model.loadState == .loading)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .loaded })
        let draw = try #require(server.rooms[Self.roomID]?.draws[drawID])
        let candidate = try #require(server.rooms[Self.roomID]?.candidates[draw.candidateId])
        let ticket = try #require(model.ticket)
        #expect(ticket.roomName == "週末のランチ")
        #expect(ticket.destinationName == candidate.place.name)
        #expect(ticket.area == candidate.place.area)
        #expect(ticket.category == candidate.category)
        #expect(ticket.note == (candidate.note.isEmpty ? nil : candidate.note))
        #expect(ticket.likeCount == candidate.likedBy.count)
        #expect(ticket.percent == Probability.displayPercent(probability: draw.probability))
        #expect(ticket.drawnAt == draw.createdAt)
        #expect(ticket.author == (candidate.postedBy == DemoScenario.myUserID ? .me : .member(candidate.postedByName)))
        #expect(!model.isReadOnly)
        #expect(model.canOpenMap)
    }

    /// 抽選の記録がサーバーに無いときは、読み込み中のまま止めずに「読み込めませんでした」にする（PR #72 の持ち越し）
    @Test
    func missingDrawRecordIsUnavailable() async throws {
        let (server, _) = try await Self.drawnServer()
        let model = Self.makeModel(server, drawID: "no-such-draw")
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .unavailable })
        #expect(model.ticket == nil)
        #expect(!model.canOpenMap)
    }

    /// 抽選の記録の当選した候補が候補に無いときも、読み込み中のまま止めない
    @Test
    func missingWinnerCandidateIsUnavailable() async throws {
        let (server, drawID) = try await Self.drawnServer()
        let winnerID = try #require(server.rooms[Self.roomID]?.draws[drawID]?.candidateId)
        server.rooms[Self.roomID]?.candidates[winnerID] = nil
        let model = Self.makeModel(server, drawID: drawID)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .unavailable })
    }

    /// 当選確率が平均の 0.85 倍より小さければレア当選、そうでなければ出さない
    @Test(arguments: [(0.2, true), (0.3, false)])
    func rareFollowsDrawProbability(_ probability: Double, _ isRare: Bool) async throws {
        let (server, drawID) = try await Self.drawnServer()
        server.rooms[Self.roomID]?.draws[drawID]?.probability = probability
        let model = Self.makeModel(server, drawID: drawID)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .loaded })
        // 候補 3 件の平均は 1/3。0.85 倍は 0.283
        #expect(model.ticket?.isRare == isRare)
        #expect(model.ticket?.percent == Probability.displayPercent(probability: probability))
    }

    /// `closed` のルームは閲覧のみ
    @Test
    func closedRoomIsReadOnly() async throws {
        let (server, drawID) = try await Self.drawnServer()
        server.rooms[Self.roomID]?.room.status = .closed
        let model = Self.makeModel(server, drawID: drawID)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .loaded })
        #expect(model.isReadOnly)
    }

    /// 「マップで開く」は当選した場所の座標と名前で開く
    @Test
    func openInMapsOpensWinnerPlace() async throws {
        let (server, drawID) = try await Self.drawnServer()
        let opener = RecordingMapOpener()
        let model = Self.makeModel(server, drawID: drawID, mapOpener: opener)
        model.openInMapsTapped()
        #expect(opener.opened.isEmpty)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.canOpenMap })
        model.openInMapsTapped()
        let winnerID = try #require(server.rooms[Self.roomID]?.room.winnerCandidateId)
        #expect(opener.opened == [server.rooms[Self.roomID]?.candidates[winnerID]?.place].compactMap(\.self))
    }

    /// メンバーから外れて読めなくなったら「ルームが見つかりません」
    @Test
    func removedMemberSeesMissing() async throws {
        let (server, drawID) = try await Self.drawnServer()
        server.rooms[Self.roomID]?.members[DemoScenario.myUserID] = nil
        server.rooms[Self.roomID]?.room.memberIds.removeAll { $0 == DemoScenario.myUserID }
        let model = Self.makeModel(server, drawID: drawID)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .missing })
        #expect(model.ticket == nil)
    }

    /// 共有画像は、きっぷとアプリ名の帯を幅 390pt の 3 倍の解像度で書き出した PNG
    @Test
    func shareImageIsThreeTimesResolution() throws {
        let ticket = ResultTicket(
            roomName: "週末のランチ",
            destinationName: "江の島",
            area: "神奈川・藤沢市",
            category: .sea,
            note: "しらす丼を食べたい",
            author: .me,
            likeCount: 1,
            percent: 37,
            drawnAt: RoomModelTests.now,
            isRare: false
        )
        let data = try #require(TicketShareImage(ticket: ticket).pngData())
        let image = try #require(UIImage(data: data))
        #expect(image.size.width * image.scale == TicketShareCard.width * TicketShareCard.scale)
        #expect(image.size.height > 0)
    }
}
