//
//  AddCandidateTestDoubles.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation

/// 待ちを手で終わらせる `sleep`（検索のデバウンスを、固定の時間を待たずに確かめる）
final class ManualSleeper {
    /// 頼まれた待ち時間（頼まれた順）
    private(set) var requested: [Duration] = []
    /// 待っている呼び出し
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// 待っている呼び出しの数
    var waitingCount: Int {
        waiters.count
    }

    /// `AddCandidateModel`・`PlaceSearchModel` に渡す待ち方
    var sleep: PlaceSearchModel.Sleep {
        { [self] duration in
            await wait(duration)
        }
    }

    /// `releaseAll()` まで待つ
    func wait(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    /// 待っている呼び出しをすべて進める
    func releaseAll() {
        let resumed = waiters
        waiters = []
        for waiter in resumed {
            waiter.resume()
        }
    }
}

/// 呼ばれた語を記録し、結果・失敗・止めておくを決められる場所検索
final class RecordingPlaceSearch: PlaceSearchService {
    /// 呼ばれた語（呼ばれた順）
    private(set) var queries: [String] = []
    /// 呼ばれたエリア（呼ばれた順。`queries` と同じ並び）
    private(set) var scopes: [SearchScope] = []
    /// 投げるエラー（nil なら擬似の検索の結果を返す）
    var error: (any Error)?
    /// true なら `release()` を呼ぶまで返さない
    var holds = false
    /// 止めている呼び出し
    private var held: [CheckedContinuation<Void, Never>] = []

    /// 止めている呼び出しの数
    var heldCount: Int {
        held.count
    }

    func search(_ query: String, in scope: SearchScope) async throws -> [SearchedPlace] {
        queries.append(query)
        scopes.append(scope)
        if holds {
            await withCheckedContinuation { held.append($0) }
        }
        if let error {
            throw error
        }
        return DemoPlaceSearchService.results(for: query, in: scope)
    }

    /// 止めている呼び出しを古い順に 1 つ進める
    func releaseFirst() {
        guard !held.isEmpty else {
            return
        }
        held.removeFirst().resume()
    }
}

/// `AddCandidateControlledFunctions` の `addCandidate` のふるまい
enum AddCandidateCallBehavior {
    /// 擬似のサーバーで処理する
    case pass
    /// このエラーを投げる
    case fail(any Error)
    /// `finish()` を呼ぶまで止まり、その後で擬似のサーバーで処理する
    case suspend
}

/// `addCandidate` の結果を決められ、送られた入力を記録する擬似の Functions（ほかの Callable は擬似のサーバーに渡す）
final class AddCandidateControlledFunctions: FunctionsClient {
    let server: InMemoryServer
    var behavior: AddCandidateCallBehavior = .pass
    /// 送られた `addCandidate` の入力（送られた順）
    private(set) var requests: [AddCandidateRequest] = []
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

    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
        requests.append(request)
        switch behavior {
        case .pass:
            break
        case let .fail(error):
            throw error
        case .suspend:
            await withCheckedContinuation { pending = $0 }
        }
        return try await server.addCandidate(request)
    }

    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
        try await server.saveProfile(request)
    }

    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
        try await server.createRoom(request)
    }

    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
        try await server.joinRoom(request)
    }

    func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
        try await server.previewRoom(request)
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
