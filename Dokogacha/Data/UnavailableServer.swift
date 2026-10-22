//
//  UnavailableServer.swift
//  Dokogacha
//

import Foundation

/// サーバーに接続できないとき（plist が無い Stg・起動前）の窓口。
///
/// アプリを落とさないよう、どの操作も `AppError(.serverUnavailable)`（「通信できませんでした」）で失敗し、
/// 購読はその失敗を 1 つ流して終わる。
final class UnavailableServer: AuthService, RoomRepository, FunctionsClient {
    private var error: AppError {
        AppError(.serverUnavailable)
    }

    /// 失敗を 1 つ流して終わる購読
    private func failedStream<Value: Sendable>(_: Value.Type = Value.self) -> AsyncStream<LiveUpdate<Value>> {
        AsyncStream { continuation in
            continuation.yield(.failure(error))
            continuation.finish()
        }
    }

    // MARK: AuthService

    var currentUserID: String? {
        nil
    }

    func userIDChanges() -> AsyncStream<String?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }

    func signInAnonymously() async throws -> String {
        throw error
    }

    func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
        failedStream()
    }

    func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse {
        throw error
    }

    func linkWithApple(_ credential: AppleIDCredential) async throws {
        throw error
    }

    // MARK: RoomRepository

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        failedStream()
    }

    func closedRooms(userID: String, limit: Int?) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        failedStream()
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        failedStream()
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        failedStream()
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        failedStream()
    }

    func draw(roomID: String, drawID: String) -> AsyncStream<LiveUpdate<Draw?>> {
        failedStream()
    }

    func candidate(roomID: String, candidateID: String) -> AsyncStream<LiveUpdate<Identified<Candidate>?>> {
        failedStream()
    }

    func pastIdeas(userID: String) -> AsyncStream<LiveUpdate<[Identified<PastIdea>]>> {
        failedStream()
    }

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        throw error
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        throw error
    }

    func markSeen(roomID: String, userID: String) async throws {
        throw error
    }

    // MARK: FunctionsClient

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        throw error
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        throw error
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        throw error
    }

    func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
        throw error
    }

    func leaveRoom(_ request: RoomRequest) async throws {
        throw error
    }

    func removeMember(_ request: RemoveMemberRequest) async throws {
        throw error
    }

    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
        throw error
    }

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        throw error
    }

    func deleteCandidate(_ request: CandidateRequest) async throws {
        throw error
    }

    func forceUnlock(_ request: RoomRequest) async throws {
        throw error
    }

    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
        throw error
    }

    func proposeReroll(_ request: RoomRequest) async throws {
        throw error
    }

    func voteReroll(_ request: VoteRerollRequest) async throws {
        throw error
    }

    func closeRoom(_ request: RoomRequest) async throws {
        throw error
    }

    func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
        throw error
    }

    func reportCandidate(_ request: ReportCandidateRequest) async throws {
        throw error
    }

    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
        throw error
    }

    func deleteAccount() async throws {
        throw error
    }
}
