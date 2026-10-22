//
//  InMemoryServerReportTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの投稿の報告（backend の `reportCandidate`。02 の §3.5 F-14）が、backend の Emulator のテスト
/// （`backend/test/emulator/reports.test.ts`）と同じ順で検証し、同じ理由で失敗すること
struct InMemoryServerReportTests {
    static let roomID = DemoScenario.roomID
    /// サンシャイン水族館（はるかの投稿）
    static let aquarium = RoomModelTests.aquarium
    /// 江の島（自分の投稿）
    static let mine = RoomModelTests.mine

    static func request(_ candidateID: String = aquarium, roomID: String = roomID, reason: ReportReason = .spam) -> ReportCandidateRequest {
        ReportCandidateRequest(roomId: roomID, candidateId: candidateID, reason: reason)
    }

    /// メンバーが他人の候補を報告すると、報告を 1 つ残す。同じ人の 2 回目は何も足さずに「もう報告済み」を返す（理由も変えない）
    @Test
    func reportsOncePerReporterAndCandidate() throws {
        let server = RoomModelTests.makeServer()
        #expect(try server.reportCandidate(Self.request(reason: .inappropriate), by: DemoScenario.myUserID) == false)
        #expect(try server.reportCandidate(Self.request(reason: .other), by: DemoScenario.myUserID) == true)
        #expect(server.reports.count == 1)
        let report = try #require(server.reports.values.first)
        #expect(report == CandidateReport(
            roomId: Self.roomID,
            candidateId: Self.aquarium,
            reporterId: DemoScenario.myUserID,
            reason: .inappropriate,
            createdAt: RoomModelTests.now
        ))
        // ほかのメンバーは別に報告できる
        #expect(try server.reportCandidate(Self.request(), by: "demo-sota") == false)
        #expect(server.reports.count == 2)
    }

    /// 自分の投稿は cannot-report-own-candidate・メンバー以外は not-room-member・無いルームは room-not-found・無い候補は candidate-not-found
    @Test
    func rejectsInTheSameOrderAsBackend() {
        let server = RoomModelTests.makeServer()
        InMemoryServerCloseTests.expectReason(.cannotReportOwnCandidate) {
            try server.reportCandidate(Self.request(Self.mine), by: DemoScenario.myUserID)
        }
        InMemoryServerCloseTests.expectReason(.notRoomMember) {
            try server.reportCandidate(Self.request(), by: "demo-outsider")
        }
        InMemoryServerCloseTests.expectReason(.roomNotFound) {
            try server.reportCandidate(Self.request(roomID: "nothing"), by: DemoScenario.myUserID)
        }
        InMemoryServerCloseTests.expectReason(.candidateNotFound) {
            try server.reportCandidate(Self.request("nothing"), by: DemoScenario.myUserID)
        }
        InMemoryServerCloseTests.expectReason(.invalidArgument) {
            try server.reportCandidate(Self.request("a/b"), by: DemoScenario.myUserID)
        }
        InMemoryServerCloseTests.expectReason(.unauthenticated) {
            try server.reportCandidate(Self.request(), by: nil)
        }
        #expect(server.reports.isEmpty)
    }

    /// 終了したルームの候補も報告できる（状態を問わない）。候補そのものは変えない
    @Test
    func reportsInClosedRoomWithoutChangingCandidate() throws {
        let server = RoomModelTests.makeServer()
        server.rooms[Self.roomID]?.room.status = .closed
        let before = server.rooms[Self.roomID]?.candidates[Self.aquarium]
        try server.reportCandidate(Self.request(), by: DemoScenario.myUserID)
        #expect(server.reports.count == 1)
        #expect(server.rooms[Self.roomID]?.candidates[Self.aquarium] == before)
    }
}
