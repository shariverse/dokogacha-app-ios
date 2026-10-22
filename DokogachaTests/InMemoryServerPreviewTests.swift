//
//  InMemoryServerPreviewTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの `previewRoom`（参加前の確認。S-06）が、backend と同じ値を返し、`joinRoom` と同じ理由で断ることを確かめる
/// （backend の `test/emulator/rooms-preview.test.ts` と同じ観点）
struct InMemoryServerPreviewTests {
    /// "guest" の端末から確かめる
    static func preview(_ server: InMemoryServer, _ userID: String = "guest", code: String) async throws -> RoomPreview {
        try await server.device(of: userID).previewRoom(PreviewRoomRequest(inviteCode: code))
    }

    /// ルーム名・作成者名・メンバー数・候補数・状態を返し、何も書き換えない
    @Test
    func returnsRoomValuesWithoutWriting() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        server.rooms[room.roomId]?.room.candidateCount = 2
        let before = try #require(server.rooms[room.roomId])

        let preview = try await Self.preview(server, code: room.inviteCode)
        #expect(preview == RoomPreview(
            roomId: room.roomId,
            name: "年末の旅行",
            ownerName: "owner",
            memberCount: 1,
            candidateCount: 2,
            status: .open,
            alreadyMember: false
        ))
        #expect(server.rooms[room.roomId] == before)
    }

    /// 小文字・ハイフン・全角・空白の入力も正規化して引く
    @Test
    func acceptsLooseCode() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        let fullWidth = String(room.inviteCode.lowercased().unicodeScalars.map { scalar in
            Character(Unicode.Scalar(scalar.value + 0xFEE0) ?? scalar)
        })
        for input in [InviteCode.formatted(room.inviteCode).lowercased(), " \(fullWidth)\u{3000}"] {
            #expect(try await Self.preview(server, code: input).roomId == room.roomId)
        }
    }

    /// 存在しない・形が正しくないコードは「招待コードが見つかりません」（F-04 の AC）
    @Test(arguments: ["ZZZZZZ", "123", "OOOOOO", ""])
    func rejectsUnknownCode(code: String) async throws {
        let server = InMemoryServerTests.makeServer()
        _ = try await InMemoryServerTests.makeRoom(server)
        let error = await #expect(throws: AppError.self) {
            try await Self.preview(server, code: code)
        }
        #expect(error?.message == "招待コードが見つかりません")
    }

    /// 20 人のルームは「このルームは満員です（最大20人）」（F-04 の AC。joinRoom と同じ理由）
    @Test
    func rejectsFullRoom() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        server.rooms[room.roomId]?.room.memberCount = DomainConstants.Limits.maxMembers
        let error = await #expect(throws: AppError.self) {
            try await Self.preview(server, code: room.inviteCode)
        }
        #expect(error?.message == "このルームは満員です（最大20人）")
    }

    /// `drawn`・`closed` は「このルームはもう行き先が決まっています」（F-04 の AC。満員でも状態の理由を先に返す）
    @Test(arguments: [RoomStatus.drawn, .closed])
    func rejectsDecidedRoom(status: RoomStatus) async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        server.rooms[room.roomId]?.room.status = status
        server.rooms[room.roomId]?.room.memberCount = DomainConstants.Limits.maxMembers
        await #expect(throws: InMemoryServer.error(.roomAlreadyDecided)) {
            try await Self.preview(server, code: room.inviteCode)
        }
    }

    /// すでにメンバーなら、決定後・満員でも断らずに `alreadyMember` を返す（S-06 を出さずにルームへ）
    @Test
    func memberGetsAlreadyMemberEvenIfDecided() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        try await InMemoryServerTests.addUser(server, "guest")
        _ = try await InMemoryServerTests.join(server, "guest", code: room.inviteCode)
        server.rooms[room.roomId]?.room.status = .drawn
        server.rooms[room.roomId]?.room.memberCount = DomainConstants.Limits.maxMembers

        let preview = try await Self.preview(server, code: room.inviteCode)
        #expect(preview.alreadyMember)
        #expect(preview.status == .drawn)
        #expect(try await Self.preview(server, "owner", code: room.inviteCode).alreadyMember)
    }

    /// 表示名を登録していなくても確かめられる（参加は `joinRoom` が「表示名を登録してください」で断る）
    @Test
    func previewDoesNotRequireProfile() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        #expect(try await Self.preview(server, "nobody", code: room.inviteCode).alreadyMember == false)
        await #expect(throws: InMemoryServer.error(.profileRequired)) {
            try await InMemoryServerTests.join(server, "nobody", code: room.inviteCode)
        }
    }

    /// サインインしていなければ断る
    @Test
    func rejectsSignedOutCaller() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        #expect(throws: AppError.self) {
            try server.previewRoom(PreviewRoomRequest(inviteCode: room.inviteCode), by: nil)
        }
    }
}
