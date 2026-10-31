//
//  ResultCloseModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-14 の「この行き先で決定」（`ResultCloseModel`。F-44）。確認の後に `closeRoom` を呼び、終了できたらホームへ戻る・失敗したらトースト
struct ResultCloseModelTests {
    static let roomID = DemoScenario.drawnRoomID

    static func makeModel(_ functions: any FunctionsClient, toasts: DGToastCenter = HomeModelTests.makeToasts()) -> ResultCloseModel {
        ResultCloseModel(roomID: roomID, functions: functions, toasts: toasts)
    }

    /// 「この行き先で決定」で確認のダイアログを出し、「決定する」でルームを終了してからホームへ戻る処理を呼ぶ
    @Test
    func confirmClosesRoomThenGoesHome() async throws {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let model = Self.makeModel(server)
        model.decideTapped()
        #expect(model.isConfirming)

        await confirmation("ホームへ戻る") { wentHome in
            await withCheckedContinuation { continuation in
                model.confirmTapped {
                    wentHome()
                    continuation.resume()
                }
            }
        }
        #expect(server.rooms[Self.roomID]?.room.status == .closed)
        #expect(!model.isClosing)
    }

    /// 送っている途中は二重に送らない（確認のダイアログも出さない・もう一度「決定する」を押しても始めない）
    @Test
    func doesNotCloseTwiceWhileSending() async {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let functions = SuspendedCloseFunctions(server: server)
        let model = Self.makeModel(functions)
        var wentHome = 0
        model.confirmTapped { wentHome += 1 }
        #expect(await AsyncTestSupport.eventually { model.isClosing && functions.isWaiting })
        model.decideTapped()
        #expect(!model.isConfirming)
        model.confirmTapped { wentHome += 1 }
        #expect(await model.close() == false)
        functions.finish()
        #expect(await AsyncTestSupport.eventually { wentHome == 1 && !model.isClosing })
        #expect(functions.closeRoomRequests == [CloseRoomRequest(roomId: Self.roomID, reason: .decide)])
    }

    /// 失敗したら AppError の文言のトーストを出し、ホームへは戻らない（もう一度押せる）
    @Test
    func failureShowsToast() async {
        let toasts = HomeModelTests.makeToasts()
        let model = Self.makeModel(UnavailableServer(), toasts: toasts)
        #expect(await model.close() == false)
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(!model.isClosing)
    }

    /// 作成者以外が呼んだときのサーバーの文言（作成者以外には出さないボタンだが、サーバーでも断る）
    @Test
    func nonOwnerIsRejectedByServer() async {
        let server = InMemoryServer.demo(.drawnRooms) { RoomModelTests.now }
        let toasts = HomeModelTests.makeToasts()
        let model = ResultCloseModel(roomID: DemoScenario.othersDrawnRoomID, functions: server, toasts: toasts)
        #expect(await model.close() == false)
        #expect(toasts.current?.text == "作成者だけが操作できます")
        #expect(server.rooms[DemoScenario.othersDrawnRoomID]?.room.status == .drawn)
    }
}

/// `closeRoom` を `finish()` まで止める擬似の Functions（`DeleteControlledFunctions` と同じ形。ほかの Callable は擬似のサーバーに渡す）
final class SuspendedCloseFunctions: FunctionsClient {
    let server: InMemoryServer
    /// 送られた `closeRoom` の入力（送られた順）
    private(set) var closeRoomRequests: [CloseRoomRequest] = []
    private var pending: CheckedContinuation<Void, Never>?

    init(server: InMemoryServer) {
        self.server = server
    }

    /// `closeRoom` の途中で止まっているか
    var isWaiting: Bool {
        pending != nil
    }

    /// 止めていた `closeRoom` を進める
    func finish() {
        pending?.resume()
        pending = nil
    }

    func closeRoom(_ request: CloseRoomRequest) async throws {
        closeRoomRequests.append(request)
        await withCheckedContinuation { pending = $0 }
        try await server.closeRoom(request)
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
