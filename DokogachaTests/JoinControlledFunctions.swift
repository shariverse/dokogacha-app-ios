//
//  JoinControlledFunctions.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation

/// `JoinControlledFunctions` の `previewRoom`・`joinRoom` のふるまい
enum JoinCallBehavior {
    /// 擬似のサーバーで処理する
    case pass
    /// このエラーを投げる
    case fail(any Error)
    /// `finish()` を呼ぶまで止まり、その後で擬似のサーバーで処理する
    case suspend
}

/// `previewRoom`・`joinRoom` の結果を決められ、送られた入力を記録する擬似の Functions（ほかの Callable は擬似のサーバーに渡す）
final class JoinControlledFunctions: FunctionsClient {
    let server: InMemoryServer
    var previewBehavior: JoinCallBehavior = .pass
    var joinBehavior: JoinCallBehavior = .pass
    /// 送られた `previewRoom` の入力（送られた順）
    private(set) var previewRequests: [PreviewRoomRequest] = []
    /// 送られた `joinRoom` の入力（送られた順）
    private(set) var joinRequests: [JoinRoomRequest] = []
    private var pending: CheckedContinuation<Void, Never>?

    init(server: InMemoryServer) {
        self.server = server
    }

    /// 呼び出しの途中で止まっているか
    var isWaiting: Bool {
        pending != nil
    }

    /// 止めていた呼び出しを進める
    func finish() {
        pending?.resume()
        pending = nil
    }

    /// ふるまいに合わせて、投げる・止まる・そのまま進む
    private func perform(_ behavior: JoinCallBehavior) async throws {
        switch behavior {
        case .pass:
            break
        case let .fail(error):
            throw error
        case .suspend:
            await withCheckedContinuation { pending = $0 }
        }
    }

    func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
        previewRequests.append(request)
        try await perform(previewBehavior)
        return try await server.previewRoom(request)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        joinRequests.append(request)
        try await perform(joinBehavior)
        return try await server.joinRoom(request)
    }

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        try await server.saveProfile(request)
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        try await server.createRoom(request)
    }

    func leaveRoom(_ request: RoomRequest) async throws {
        try await server.leaveRoom(request)
    }

    func removeMember(_ request: RemoveMemberRequest) async throws {
        try await server.removeMember(request)
    }

    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
        try await server.updateRoomSettings(request)
    }

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        try await server.addCandidate(request)
    }

    func deleteCandidate(_ request: CandidateRequest) async throws {
        try await server.deleteCandidate(request)
    }

    func forceUnlock(_ request: RoomRequest) async throws {
        try await server.forceUnlock(request)
    }

    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
        try await server.drawGacha(request)
    }

    func proposeReroll(_ request: RoomRequest) async throws {
        try await server.proposeReroll(request)
    }

    func voteReroll(_ request: VoteRerollRequest) async throws {
        try await server.voteReroll(request)
    }

    func closeRoom(_ request: RoomRequest) async throws {
        try await server.closeRoom(request)
    }

    func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
        try await server.inviteLastMembers(request)
    }

    func reportCandidate(_ request: ReportCandidateRequest) async throws {
        try await server.reportCandidate(request)
    }

    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
        try await server.verifyPurchase(request)
    }

    func deleteAccount() async throws {
        try await server.deleteAccount()
    }
}
