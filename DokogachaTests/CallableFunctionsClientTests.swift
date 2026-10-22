//
//  CallableFunctionsClientTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import FirebaseFunctions
import Foundation
import Testing

/// Callable の呼び出し（名前・入力の形・結果）と、SDK のエラーからアプリのエラーへの変換を確かめる
struct CallableFunctionsClientTests {
    /// 呼ばれた名前と入力の JSON を覚え、決めた結果を返す擬似の SDK の窓口
    final class FakeTransport: CallableTransport {
        var calls: [(name: CallableName, json: [String: Any])] = []
        var responseJSON = Data("{}".utf8)
        var failure: (any Error)?

        func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
            _ name: CallableName,
            _ request: Request,
            responseType: Response.Type
        ) async throws -> Response {
            let data = try JSONEncoder().encode(request)
            calls.append((name, try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]))
            if let failure {
                throw failure
            }
            return try JSONDecoder().decode(Response.self, from: responseJSON)
        }
    }

    @Test
    func createRoomSendsDeadlineInMilliseconds() async throws {
        let transport = FakeTransport()
        transport.responseJSON = Data(#"{"roomId":"r1","inviteCode":"DK729Q"}"#.utf8)
        let deadline = Date(timeIntervalSince1970: 1_790_000_000.5)
        let request = CreateRoomRequest(name: "年末の旅行", postLimit: 3, unlockRule: .deadline, deadline: deadline, likeMode: .boost)
        let response = try await CallableFunctionsClient(transport: transport).createRoom(request)

        #expect(response == CreateRoomResponse(roomId: "r1", inviteCode: "DK729Q"))
        #expect(transport.calls.first?.name == .createRoom)
        let json = try #require(transport.calls.first?.json)
        #expect(json["deadlineAt"] as? Int64 == 1_790_000_000_500)
        #expect(json["unlockRule"] as? String == "deadline")
        #expect(json["likeMode"] as? String == "boost")
    }

    /// 締切日時は「締切日時」の条件のときだけ送る
    @Test
    func createRoomOmitsDeadlineForOtherRules() throws {
        let request = CreateRoomRequest(name: "a", postLimit: 1, unlockRule: .all, deadline: Date(), likeMode: .equal)
        #expect(request.deadlineAt == nil)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(json["deadlineAt"] == nil)
    }

    @Test
    func callsUseFunctionNames() async throws {
        let transport = FakeTransport()
        let client = CallableFunctionsClient(transport: transport)
        try await client.leaveRoom(RoomRequest(roomId: "r1"))
        try await client.removeMember(RemoveMemberRequest(roomId: "r1", memberId: "u2"))
        try await client.voteReroll(VoteRerollRequest(roomId: "r1", approve: true))
        try await client.deleteAccount()
        #expect(transport.calls.map(\.name) == [.leaveRoom, .removeMember, .voteReroll, .deleteAccount])
        #expect(transport.calls[1].json["memberId"] as? String == "u2")
        #expect(transport.calls[2].json["approve"] as? Bool == true)
    }

    @Test
    func addCandidateReturnsDuplicate() async throws {
        let transport = FakeTransport()
        let client = CallableFunctionsClient(transport: transport)
        let request = AddCandidateRequest(
            roomId: "r1",
            place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.29, longitude: 139.48, mapItemId: nil),
            category: .sea,
            note: "",
            url: nil,
            fromPastIdeaId: nil
        )
        transport.responseJSON = Data(#"{"duplicateOf":"c9"}"#.utf8)
        #expect(try await client.addCandidate(request) == .duplicate(of: "c9"))
        transport.responseJSON = Data(#"{"candidateId":"c10"}"#.utf8)
        #expect(try await client.addCandidate(request) == .added(candidateID: "c10"))
        transport.responseJSON = Data("{}".utf8)
        await #expect(throws: AppError(.internal)) {
            try await client.addCandidate(request)
        }
    }

    /// `previewRoom` は招待コードを送り、backend の `RoomPreview` の JSON（作成者名が null のときを含む）を読む
    @Test
    func previewRoomSendsCodeAndDecodesPreview() async throws {
        let transport = FakeTransport()
        let client = CallableFunctionsClient(transport: transport)
        transport.responseJSON = Data(#"""
        {"roomId":"r1","name":"夏の花火大会","ownerName":"はるか","memberCount":3,"candidateCount":2,"status":"unlocked","alreadyMember":false}
        """#.utf8)
        let preview = try await client.previewRoom(PreviewRoomRequest(inviteCode: "QW5-8RT"))
        #expect(preview == RoomPreview(
            roomId: "r1",
            name: "夏の花火大会",
            ownerName: "はるか",
            memberCount: 3,
            candidateCount: 2,
            status: .unlocked,
            alreadyMember: false
        ))
        #expect(transport.calls.first?.name == .previewRoom)
        #expect(transport.calls.first?.json["inviteCode"] as? String == "QW5-8RT")

        transport.responseJSON = Data(#"""
        {"roomId":"r1","name":"a","ownerName":null,"memberCount":1,"candidateCount":0,"status":"drawn","alreadyMember":true}
        """#.utf8)
        let withoutOwner = try await client.previewRoom(PreviewRoomRequest(inviteCode: "QW58RT"))
        #expect(withoutOwner.ownerName == nil)
        #expect(withoutOwner.alreadyMember)
    }

    /// 失敗は `AppError` にして投げる（理由で文言を選ぶ）
    @Test
    func failureBecomesAppError() async {
        let transport = FakeTransport()
        transport.failure = ServerFailure(code: .resourceExhausted, reason: "room-full")
        await #expect(throws: AppError(.roomFull, code: .resourceExhausted)) {
            try await CallableFunctionsClient(transport: transport).joinRoom(JoinRoomRequest(inviteCode: "DK7-29Q"))
        }
    }

    /// SDK の `HttpsError`（`FunctionsErrorDomain`・`details.reason`）を `ServerFailure` にする
    @Test
    func firebaseErrorCarriesCodeAndReason() {
        let error = NSError(
            domain: FunctionsErrorDomain,
            code: FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo: [FunctionsErrorDetailsKey: ["reason": "room-already-decided"]]
        )
        let failure = FirebaseCallableTransport.failure(from: error)
        #expect(failure == ServerFailure(code: .failedPrecondition, reason: "room-already-decided"))
        #expect(AppError.server(failure).message == "このルームはもう行き先が決まっています")
    }

    @Test
    func firebaseNetworkAndOtherErrors() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(FirebaseCallableTransport.failure(from: offline) == ServerFailure(code: .unavailable))
        let noDetails = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.unauthenticated.rawValue)
        #expect(AppError.server(FirebaseCallableTransport.failure(from: noDetails)).reason == .unauthenticated)
        struct DecodeFailure: Error {}
        #expect(FirebaseCallableTransport.failure(from: DecodeFailure()).code == .internal)
    }

    /// cancel（`Task` の cancel・URL の読み込みの cancel・SDK の `cancelled`）は、通信の失敗と見分けられる
    @Test
    func firebaseCancellationIsNotNetworkFailure() {
        let urlCancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        let sdkCancelled = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.cancelled.rawValue)
        for error in [CancellationError(), urlCancelled, sdkCancelled] as [any Error] {
            let failure = FirebaseCallableTransport.failure(from: error)
            #expect(failure.code == .cancelled)
            #expect(AppError.server(failure).isCancellation)
        }
    }

    /// `FunctionsErrorCode` と `ServerErrorCode` の番号が同じ（SDK の番号からそのまま作るため）
    @Test
    func functionsErrorCodesMatchGRPC() {
        for code in ServerErrorCode.allCases {
            #expect(FunctionsErrorCode(rawValue: code.rawValue) != nil)
        }
        #expect(FunctionsErrorCode.unauthenticated.rawValue == ServerErrorCode.unauthenticated.rawValue)
        #expect(FunctionsErrorCode.resourceExhausted.rawValue == ServerErrorCode.resourceExhausted.rawValue)
    }
}
