//
//  CallableTransport.swift
//  Dokogacha
//

import Foundation

/// Callable Functions の SDK の窓口。名前と入力を渡して、出力を受け取る。
///
/// `CallableFunctionsClient` はこの protocol を通して SDK を使う（テストでは擬似の実装に差し替える）。
/// 失敗したら、SDK のエラーを `ServerFailure`（gRPC の分類と `details.reason`）にして投げる。
protocol CallableTransport {
    /// Callable を呼ぶ
    func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: CallableName,
        _ request: Request,
        responseType: Response.Type
    ) async throws -> Response
}

/// `CallableTransport` で Callable を呼ぶ `FunctionsClient`。
///
/// どの Callable の失敗も `AppError.wrapping(_:)` を通して `AppError` にする（エラーの文言の対応はそこ 1 か所）。
final class CallableFunctionsClient: FunctionsClient {
    private let transport: any CallableTransport

    /// SDK の窓口を受け取って作る
    init(transport: any CallableTransport) {
        self.transport = transport
    }

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        try await call(.saveProfile, request)
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        try await call(.createRoom, request)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        try await call(.joinRoom, request)
    }

    func leaveRoom(_ request: RoomRequest) async throws {
        try await callWithoutResult(.leaveRoom, request)
    }

    func removeMember(_ request: RemoveMemberRequest) async throws {
        try await callWithoutResult(.removeMember, request)
    }

    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
        try await callWithoutResult(.updateRoomSettings, request)
    }

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        let response: AddCandidateResponse = try await call(.addCandidate, request)
        if let duplicateOf = response.duplicateOf {
            return .duplicate(of: duplicateOf)
        }
        guard let candidateID = response.candidateId else {
            // どちらも無い戻り値は backend の誤り。画面には通信の失敗として出す
            throw AppError(.internal)
        }
        return .added(candidateID: candidateID)
    }

    func deleteCandidate(_ request: CandidateRequest) async throws {
        try await callWithoutResult(.deleteCandidate, request)
    }

    func forceUnlock(_ request: RoomRequest) async throws {
        try await callWithoutResult(.forceUnlock, request)
    }

    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
        try await call(.drawGacha, request)
    }

    func proposeReroll(_ request: RoomRequest) async throws {
        try await callWithoutResult(.proposeReroll, request)
    }

    func voteReroll(_ request: VoteRerollRequest) async throws {
        try await callWithoutResult(.voteReroll, request)
    }

    func closeRoom(_ request: RoomRequest) async throws {
        try await callWithoutResult(.closeRoom, request)
    }

    func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
        try await call(.inviteLastMembers, request)
    }

    func reportCandidate(_ request: ReportCandidateRequest) async throws {
        try await callWithoutResult(.reportCandidate, request)
    }

    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
        try await call(.verifyPurchase, request)
    }

    func deleteAccount() async throws {
        try await callWithoutResult(.deleteAccount, EmptyCallablePayload())
    }

    /// Callable を呼び、失敗を `AppError` にする
    private func call<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: CallableName,
        _ request: Request
    ) async throws -> Response {
        do {
            return try await transport.call(name, request, responseType: Response.self)
        } catch {
            throw AppError.wrapping(error)
        }
    }

    /// 戻り値の無い Callable を呼ぶ
    private func callWithoutResult<Request: Encodable & Sendable>(_ name: CallableName, _ request: Request) async throws {
        let _: EmptyCallablePayload = try await call(name, request)
    }
}
