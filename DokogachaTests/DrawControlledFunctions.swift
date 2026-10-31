//
//  DrawControlledFunctions.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation

/// `drawGacha` の結果を決められ、送られた入力を記録する擬似の Functions（ほかの Callable は擬似のサーバーに渡す。`GachaModelTests` で使う）。
///
/// ふるまいは `JoinCallBehavior` と同じ（擬似のサーバーで処理する・エラーを投げる・`finish()` まで止まる）
final class DrawControlledFunctions: FunctionsClient {
    let server: InMemoryServer
    var drawBehavior: JoinCallBehavior = .pass
    /// 擬似のサーバーで抽選を書き込んだ後に投げるエラー（タイムアウトで失敗したが、サーバーでは書き込み済みのとき）
    var failureAfterWriting: AppError?
    /// `failureAfterWriting` のとき、書き込んだ後で `finish()` を呼ぶまで止まるか（失敗が返る前に drawn を届けるため）
    var holdsAfterWriting = false
    /// 送られた `drawGacha` の入力（送られた順）
    private(set) var drawRequests: [RoomRequest] = []
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
        try await server.previewRoom(request)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        try await server.joinRoom(request)
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
        drawRequests.append(request)
        try await perform(drawBehavior)
        let response = try await server.drawGacha(request)
        if let failureAfterWriting {
            if holdsAfterWriting {
                await withCheckedContinuation { pending = $0 }
            }
            throw failureAfterWriting
        }
        return response
    }

    func proposeReroll(_ request: RoomRequest) async throws {
        try await server.proposeReroll(request)
    }

    func voteReroll(_ request: VoteRerollRequest) async throws {
        try await server.voteReroll(request)
    }

    func closeRoom(_ request: CloseRoomRequest) async throws {
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
