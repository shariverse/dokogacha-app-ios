//
//  OnlineRequiredServices.swift
//  Dokogacha
//

import Foundation

/// オンライン必須の Callable Functions を、オフラインのときは送らずに止める窓口（02 の §9）。
///
/// どの Callable もサーバーの返事が要るので、すべて送る前に `NetworkStatus.requireOnline()` で確かめ、
/// オフラインなら `AppError(.offline)`（「オフラインのため操作できません」）を投げる。
/// 送ると、SDK はタイムアウトまで返らず、画面は送信中のまま止まる。止めた後の扱い（トースト・送信中の表示を戻す）は、
/// どの画面も通信エラーと同じ（`DGToastCenter.showFailure(_:)`）なので、画面ごとに回線を見なくて済む。
struct OnlineRequiredFunctionsClient: FunctionsClient {
    /// 包む窓口
    let base: any FunctionsClient
    /// 回線の状態
    let network: NetworkStatus

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        try network.requireOnline()
        return try await base.saveProfile(request)
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        try network.requireOnline()
        return try await base.createRoom(request)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        try network.requireOnline()
        return try await base.joinRoom(request)
    }

    func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
        try network.requireOnline()
        return try await base.previewRoom(request)
    }

    func leaveRoom(_ request: RoomRequest) async throws {
        try network.requireOnline()
        try await base.leaveRoom(request)
    }

    func removeMember(_ request: RemoveMemberRequest) async throws {
        try network.requireOnline()
        try await base.removeMember(request)
    }

    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
        try network.requireOnline()
        try await base.updateRoomSettings(request)
    }

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        try network.requireOnline()
        return try await base.addCandidate(request)
    }

    func deleteCandidate(_ request: CandidateRequest) async throws {
        try network.requireOnline()
        try await base.deleteCandidate(request)
    }

    func forceUnlock(_ request: RoomRequest) async throws {
        try network.requireOnline()
        try await base.forceUnlock(request)
    }

    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
        try network.requireOnline()
        return try await base.drawGacha(request)
    }

    func proposeReroll(_ request: RoomRequest) async throws {
        try network.requireOnline()
        try await base.proposeReroll(request)
    }

    func voteReroll(_ request: VoteRerollRequest) async throws {
        try network.requireOnline()
        try await base.voteReroll(request)
    }

    func closeRoom(_ request: CloseRoomRequest) async throws {
        try network.requireOnline()
        try await base.closeRoom(request)
    }

    func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
        try network.requireOnline()
        return try await base.inviteLastMembers(request)
    }

    func reportCandidate(_ request: ReportCandidateRequest) async throws {
        try network.requireOnline()
        try await base.reportCandidate(request)
    }

    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
        try network.requireOnline()
        return try await base.verifyPurchase(request)
    }

    func deleteAccount() async throws {
        try network.requireOnline()
        try await base.deleteAccount()
    }
}

/// 直接の書き込みのうち、オンライン必須のもの（いいね・準備OK）を、オフラインのときは送らずに止める窓口（02 の §9）。
///
/// Firestore の直接の書き込みはキャッシュに書いた時点で返り、繋がるまでサーバーに送られない（`RoomRepository`）。
/// そのままだと、オフラインで押したいいね・準備OKが自分の画面だけで付き、ほかの人には届かないまま「付いた」ように見えるので、
/// 送る前に止めて `AppError(.offline)` を投げる（画面は楽観的な表示を戻してトーストを出す）。
/// 購読（閲覧）はキャッシュで続けられるので、そのまま通す。`lastSeenAt` は画面を離れるときの裏の書き込みで、
/// 繋がってから送られても困らない（NEW の判定が少し遅れるだけ）ので止めない。
struct OnlineRequiredRoomRepository: RoomRepository {
    /// 包む窓口
    let base: any RoomRepository
    /// 回線の状態
    let network: NetworkStatus

    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        base.activeRooms(userID: userID)
    }

    func closedRooms(userID: String, limit: Int?) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
        base.closedRooms(userID: userID, limit: limit)
    }

    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
        base.room(id: roomID)
    }

    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
        base.members(roomID: roomID)
    }

    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
        base.candidates(roomID: roomID)
    }

    func draw(roomID: String, drawID: String) -> AsyncStream<LiveUpdate<Draw?>> {
        base.draw(roomID: roomID, drawID: drawID)
    }

    func candidate(roomID: String, candidateID: String) -> AsyncStream<LiveUpdate<Identified<Candidate>?>> {
        base.candidate(roomID: roomID, candidateID: candidateID)
    }

    func pastIdeas(userID: String) -> AsyncStream<LiveUpdate<[Identified<PastIdea>]>> {
        base.pastIdeas(userID: userID)
    }

    func setReady(_ ready: Bool, roomID: String, userID: String) async throws {
        try network.requireOnline()
        try await base.setReady(ready, roomID: roomID, userID: userID)
    }

    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {
        try network.requireOnline()
        try await base.setLike(liked, candidateID: candidateID, roomID: roomID, userID: userID)
    }

    func markSeen(roomID: String, userID: String) async throws {
        try await base.markSeen(roomID: roomID, userID: userID)
    }
}

/// 場所検索（MapKit。サーバーに問い合わせる）を、オフラインのときは問い合わせずに止める窓口（02 の §9）
struct OnlineRequiredPlaceSearchService: PlaceSearchService {
    /// 包む窓口
    let base: any PlaceSearchService
    /// 回線の状態
    let network: NetworkStatus

    func search(_ query: String, in area: SearchArea) async throws -> [SearchedPlace] {
        try network.requireOnline()
        return try await base.search(query, in: area)
    }
}

extension DataServices {
    /// オンライン必須の操作（Callable・いいね・準備OK・場所検索）を、オフラインのときは送らずに止める窓口にする（02 の §9）。
    ///
    /// 購読（閲覧）はそのまま通すので、Firestore のキャッシュで見られる。認証の窓口は包まない
    /// （Firebase の実装は中で `functions` を使うので、`firebase(network:)` で包んだものを渡してある。匿名のサインインは
    /// オフラインならすぐ失敗し、起動の流れが繋がってからやり直す）
    /// - Parameter network: 回線の状態
    func requiringOnline(_ network: NetworkStatus) -> Self {
        var services = self
        services.functions = OnlineRequiredFunctionsClient(base: functions, network: network)
        services.rooms = OnlineRequiredRoomRepository(base: rooms, network: network)
        services.places = OnlineRequiredPlaceSearchService(base: places, network: network)
        return services
    }
}
