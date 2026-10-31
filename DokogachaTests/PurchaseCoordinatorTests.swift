//
//  PurchaseCoordinatorTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 広告非表示の買い切りのまとめ役（端末の購入の読み込み・`Transaction.updates` の購読・`verifyPurchase` を呼ぶ時機・購入と復元）を、
/// StoreKit を差し替えて確かめる（02 の §7.2 F-51・05 の §8）
struct PurchaseCoordinatorTests {
    /// StoreKit を差し替えたもの（購入・復元の結果を決められ、`Transaction.updates` の代わりに値を流せる）
    private final class FakePurchaseService: PurchaseService {
        var entitlement: SignedPurchase?
        var purchaseOutcome: PurchaseOutcome = .cancelled
        var restored: SignedPurchase?
        /// `Transaction.updates` の代わりに流す口
        let updates: AsyncStream<SignedPurchase?>
        let continuation: AsyncStream<SignedPurchase?>.Continuation
        /// 購読が止まったか
        private(set) var isTerminated = false

        init() {
            (updates, continuation) = AsyncStream.makeStream(of: SignedPurchase?.self)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.isTerminated = true
                }
            }
        }

        func product() async throws -> PurchaseProduct? {
            PurchaseProduct(id: DomainConstants.RemoveAds.productID, displayPrice: "¥480")
        }

        func purchase() async throws -> PurchaseOutcome {
            purchaseOutcome
        }

        func currentEntitlement() async -> SignedPurchase? {
            entitlement
        }

        func restore() async throws -> SignedPurchase? {
            restored
        }

        func transactionUpdates() -> AsyncStream<SignedPurchase?> {
            updates
        }
    }

    /// `verifyPurchase` に送られた入力を記録し、結果を決められる擬似の Functions（ほかの Callable は擬似のサーバーに渡す）
    private final class PurchaseSpyFunctions: FunctionsClient {
        let server: InMemoryServer
        /// 送られた `verifyPurchase` の入力（送られた順）
        private(set) var verifyRequests: [VerifyPurchaseRequest] = []
        /// `verifyPurchase` を失敗させるエラー（nil なら擬似のサーバーで処理する）
        var verifyError: AppError?

        init(server: InMemoryServer) {
            self.server = server
        }

        func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
            verifyRequests.append(request)
            if let verifyError {
                throw verifyError
            }
            return try await server.verifyPurchase(request)
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

        func closeRoom(_ request: CloseRoomRequest) async throws {
            try await server.closeRoom(request)
        }

        func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
            try await server.inviteLastMembers(request)
        }

        func reportCandidate(_ request: ReportCandidateRequest) async throws {
            try await server.reportCandidate(request)
        }

        func deleteAccount() async throws {
            try await server.deleteAccount()
        }
    }

    nonisolated private static let purchase = SignedPurchase(
        productID: "remove_ads",
        transactionID: "2000000000000001",
        signedTransaction: "eyJhbGciOiJFUzI1NiJ9.eyJ0ZXN0Ijp0cnVlfQ.c2ln"
    )
    nonisolated private static let me = DemoScenario.myUserID

    /// デモのルーム（年末の旅行）がある擬似のサーバーと、それを包んだ Functions
    private static func makeFunctions() -> PurchaseSpyFunctions {
        PurchaseSpyFunctions(server: InMemoryServer.demo(.roomWithCandidates))
    }

    /// 起動して、端末の購入を読み終えるまで待つ（`Transaction.updates` の代わりの口は閉じる）
    private static func startAndFinishUpdates(_ purchases: PurchaseCoordinator, _ fake: FakePurchaseService) async {
        purchases.start()
        fake.continuation.finish()
        await purchases.updatesTask?.value
    }

    /// 起動時に端末の購入を読み、プロフィールが読めてサーバーが未記録なら 1 回だけ verifyPurchase を呼ぶ（05 の §8「初回のみ」）
    @Test
    func startReadsEntitlementAndVerifiesOnceAfterConnect() async {
        let fake = FakePurchaseService()
        fake.entitlement = Self.purchase
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        await Self.startAndFinishUpdates(purchases, fake)

        #expect(purchases.entitlement == Self.purchase)
        // 端末の購入があれば、サーバーの記録が届く前から自分を広告非表示にする
        #expect(purchases.isAdFree(serverAdFree: false))
        // プロフィールが読めるまでは送らない
        #expect(purchases.verifyTask == nil)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: nil)
        #expect(purchases.verifyTask == nil)

        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests == [VerifyPurchaseRequest(signedTransaction: Self.purchase.signedTransaction)])
        #expect(functions.server.users[Self.me]?.adFree == true)
        // サーバーの記録が届く前にもう一度プロフィールが届いても、同じ購入は送り直さない
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 1)
    }

    /// サーバーが記録済み・端末に購入が無いときは送らない
    @Test
    func doesNotVerifyWhenServerHasPurchaseOrDeviceHasNone() async {
        let fake = FakePurchaseService()
        fake.entitlement = Self.purchase
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        await Self.startAndFinishUpdates(purchases, fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: true)
        #expect(purchases.verifyTask == nil)

        let none = FakePurchaseService()
        let notPurchased = PurchaseCoordinator(service: none)
        await Self.startAndFinishUpdates(notPurchased, none)
        notPurchased.connect(functions: functions, userID: Self.me, serverAdFree: false)
        #expect(notPurchased.verifyTask == nil)
        #expect(!notPurchased.isAdFree(serverAdFree: false))
        #expect(notPurchased.isAdFree(serverAdFree: true))
        #expect(functions.verifyRequests.isEmpty)
    }

    /// アプリの外での購入（`Transaction.updates`。承認待ちの承認・別の端末での購入）が届いたら、広告非表示にしてサーバーに送る
    @Test
    func transactionUpdateMakesAdFreeAndVerifies() async {
        let fake = FakePurchaseService()
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        purchases.start()
        fake.continuation.yield(Self.purchase)
        fake.continuation.finish()
        await purchases.updatesTask?.value
        await purchases.verifyTask?.value

        #expect(purchases.entitlement == Self.purchase)
        #expect(functions.verifyRequests.count == 1)
        #expect(functions.server.users[Self.me]?.adFree == true)
    }

    /// 拒まれて送れなかったら、同じユーザーには送り直さず（次の起動で送る）、ユーザーが替わったら新しいユーザーに送る
    @Test
    func failedVerificationIsNotRetriedUntilUserChanges() async {
        let fake = FakePurchaseService()
        fake.entitlement = Self.purchase
        let functions = Self.makeFunctions()
        functions.verifyError = AppError(.purchaseInvalid)
        let purchases = PurchaseCoordinator(service: fake)
        await Self.startAndFinishUpdates(purchases, fake)

        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        await purchases.verifyTask?.value
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 1)

        functions.verifyError = nil
        purchases.connect(functions: functions, userID: "new-user", serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 2)
    }

    /// 通信の失敗で送れなかったら、回線が戻ったとき・次にプロフィールが届いたときに、同じ起動のうちに送り直す（PR #97 の持ち越し）
    @Test
    func networkFailureIsRetriedInTheSameLaunch() async {
        let fake = FakePurchaseService()
        fake.entitlement = Self.purchase
        let functions = Self.makeFunctions()
        functions.verifyError = AppError(.network, code: .unavailable)
        let purchases = PurchaseCoordinator(service: fake)
        await Self.startAndFinishUpdates(purchases, fake)

        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 1)

        functions.verifyError = nil
        purchases.retryVerificationIfNeeded()
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 2)
        #expect(functions.server.users[Self.me]?.adFree == true)
        // 通った後は送り直さない
        purchases.retryVerificationIfNeeded()
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 2)
    }

    /// アカウントを削除した後（F-06）は、送ったトランザクションとサーバーの記録を忘れ、次のプロフィールが読めるまで送らない。
    /// 次のユーザーのプロフィールが読めたら、端末の購入（Apple ID に付く）をその人にもう一度送る
    @Test
    func forgetAccountSendsEntitlementToNextUser() async {
        let fake = FakePurchaseService()
        fake.entitlement = Self.purchase
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        await Self.startAndFinishUpdates(purchases, fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 1)

        purchases.forgetAccount()
        // 端末の購入は残るので、広告は出さないまま
        #expect(purchases.isAdFree(serverAdFree: false))
        #expect(purchases.verifyTask == nil)

        functions.server.signedInUserID = "next-user"
        _ = try? await functions.server.saveProfile(SaveProfileRequest(displayName: "つぎ"))
        purchases.connect(functions: functions, userID: "next-user", serverAdFree: false)
        await purchases.verifyTask?.value
        #expect(functions.verifyRequests.count == 2)
        #expect(functions.server.users["next-user"]?.adFree == true)
    }

    /// 買えたら端末の購入にし、サーバーにも送る（S-15 の「広告を非表示にする」。タスク 38 の画面から呼ぶ）
    @Test
    func purchaseSendsToServer() async throws {
        let fake = FakePurchaseService()
        fake.purchaseOutcome = .purchased(Self.purchase)
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)

        #expect(try await purchases.purchase() == .purchased(Self.purchase))
        #expect(purchases.entitlement == Self.purchase)
        #expect(functions.verifyRequests.count == 1)
        #expect(functions.server.users[Self.me]?.adFree == true)
    }

    /// 購入の確認でやめた・承認待ちなら、何も送らない
    @Test(arguments: [PurchaseOutcome.cancelled, .pending])
    func cancelledOrPendingPurchaseSendsNothing(outcome: PurchaseOutcome) async throws {
        let fake = FakePurchaseService()
        fake.purchaseOutcome = outcome
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)

        #expect(try await purchases.purchase() == outcome)
        #expect(purchases.entitlement == nil)
        #expect(functions.verifyRequests.isEmpty)
    }

    /// サーバーに送れなければ、購入の結果ではなくエラーを返す（画面がトーストを出す）。端末の購入は持ったまま（広告は消える）
    @Test
    func purchaseThrowsWhenServerFails() async {
        let fake = FakePurchaseService()
        fake.purchaseOutcome = .purchased(Self.purchase)
        let functions = Self.makeFunctions()
        functions.verifyError = AppError(.purchaseInvalid)
        let purchases = PurchaseCoordinator(service: fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)

        await #expect(throws: AppError(.purchaseInvalid)) {
            try await purchases.purchase()
        }
        #expect(purchases.isAdFree(serverAdFree: false))
    }

    /// 購入を復元すると広告が消える（02 の F-51 の AC）。復元するものが無ければ false で、何も送らない
    @Test
    func restoreMakesAdFreeAndVerifies() async throws {
        let fake = FakePurchaseService()
        let functions = Self.makeFunctions()
        let purchases = PurchaseCoordinator(service: fake)
        purchases.connect(functions: functions, userID: Self.me, serverAdFree: false)

        let restoredNothing = try await purchases.restore()
        #expect(!restoredNothing)
        #expect(functions.verifyRequests.isEmpty)

        fake.restored = Self.purchase
        let restoredPurchase = try await purchases.restore()
        #expect(restoredPurchase)
        #expect(purchases.isAdFree(serverAdFree: false))
        #expect(functions.verifyRequests.count == 1)
        #expect(functions.server.users[Self.me]?.adFree == true)
    }

    /// `Transaction.updates` の購読は、まとめ役が無くなったら止まる（持ち主の寿命）
    @Test
    func updatesStopWhenCoordinatorIsReleased() async {
        let fake = FakePurchaseService()
        var purchases: PurchaseCoordinator? = PurchaseCoordinator(service: fake)
        purchases?.start()
        #expect(!fake.isTerminated)
        purchases = nil
        #expect(await AsyncTestSupport.eventually { fake.isTerminated })
    }

    /// テスト・撮影モードでは StoreKit を使わない（購入の確認のシートが画面を塞がない）。2 回 start しても購読は 1 つ
    @Test
    func testLaunchesUseDisabledService() async {
        for arguments in [["-uiTesting"], ["-screenshot-demo"]] {
            let purchases = PurchaseCoordinator.make(launch: LaunchContext(arguments: arguments, environment: [:]))
            purchases.start()
            let task = purchases.updatesTask
            purchases.start()
            #expect(purchases.updatesTask == task)
            await purchases.updatesTask?.value
            #expect(purchases.entitlement == nil)
            await #expect(throws: AppError(.notImplemented)) {
                try await purchases.purchase()
            }
        }
    }
}
