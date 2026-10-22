//
//  PushNotificationCoordinatorTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 差し替えた SDK が投げるエラー
private struct FakeFailure: Error {}

/// プッシュ通知の端末側のまとめ役（許可を尋ねる時機・APNs への登録・`fcmTokens` への書き込み・通知を開いたとき）を、
/// SDK を差し替えて確かめる（02 の §8・05 の §3）
struct PushNotificationCoordinatorTests {
    /// 通知の許可・APNs・FCM・Firestore・端末の保存を差し替えたもの（呼ばれたことを残す）
    private final class FakePush: NotificationAuthorizationClient, RemoteNotificationRegistrar, PushTokenProvider, PushTokenWriter,
        PushTokenRegistrationStore {
        var status = PushAuthorizationStatus.notDetermined
        var grants = true
        var requestCount = 0
        var registerCount = 0
        var apnsTokens: [Data] = []
        var deleteCount = 0
        var deleteFails = false
        var freshToken = "fresh"
        var writes: [String] = []
        var saved: PushTokenRegistration?
        /// true なら、許可を尋ねたときに答え（`answer`）を渡されるまで待つ（尋ねている途中を作る）
        var holdsAnswer = false
        /// 待っている答えの渡し先（尋ねている途中だけある）
        var pendingAnswer: CheckedContinuation<Bool, Never>?
        /// 起きたことの順
        var events: [String] = []

        func authorizationStatus() async -> PushAuthorizationStatus {
            status
        }

        func requestAuthorization() async throws -> Bool {
            requestCount += 1
            let granted = holdsAnswer ? await withCheckedContinuation { pendingAnswer = $0 } : grants
            status = granted ? .authorized : .denied
            return granted
        }

        /// 尋ねている途中の許可に答える
        func answer(_ granted: Bool) {
            pendingAnswer?.resume(returning: granted)
            pendingAnswer = nil
        }

        func registerForRemoteNotifications() {
            registerCount += 1
            events.append("register")
        }

        func setAPNSToken(_ token: Data) {
            apnsTokens.append(token)
        }

        func deleteToken() async throws {
            deleteCount += 1
            if deleteFails {
                throw FakeFailure()
            }
        }

        func fetchToken() async throws -> String {
            freshToken
        }

        func add(token: String, userID: String) {
            writes.append("add \(token) \(userID)")
        }

        func remove(token: String, userID: String) {
            writes.append("remove \(token) \(userID)")
        }

        func load() -> PushTokenRegistration? {
            saved
        }

        func save(_ registration: PushTokenRegistration?) {
            saved = registration
        }
    }

    /// 通知を使う状態のまとめ役
    private func makeEnabled(_ fake: FakePush, router: DeepLinkRouter = DeepLinkRouter()) -> PushNotificationCoordinator {
        let coordinator = PushNotificationCoordinator(router: router)
        coordinator.enable(authorization: fake, registrar: fake, tokens: fake, writer: fake, store: fake)
        return coordinator
    }

    /// 初めてルームを作成・参加したとき（まだ尋ねていない）だけ許可を尋ね、許可されたら APNs に登録する
    @Test
    func requestsAuthorizationOnlyWhenNotDetermined() async {
        let fake = FakePush()
        let coordinator = makeEnabled(fake)
        await coordinator.requestAuthorizationIfNeeded()
        #expect(fake.requestCount == 1)
        #expect(fake.registerCount == 1)

        // 2 回目のルーム（もう尋ねた）では尋ねない
        await coordinator.requestAuthorizationIfNeeded()
        #expect(fake.requestCount == 1)
    }

    /// 許可されなかったら登録しない。許可しなかった人には、次のルームでも尋ねない
    @Test
    func doesNotRegisterWhenDenied() async {
        let fake = FakePush()
        fake.grants = false
        let coordinator = makeEnabled(fake)
        await coordinator.requestAuthorizationIfNeeded()
        await coordinator.requestAuthorizationIfNeeded()
        #expect(fake.requestCount == 1)
        #expect(fake.registerCount == 0)
    }

    /// 通知の許可を尋ねている途中なら、答えが出て（登録まで済んで）から返る（ATT のダイアログを重ねて出さないため）
    @Test(.timeLimit(.minutes(1)))
    func waitForAuthorizationRequestWaitsForAnswer() async {
        let fake = FakePush()
        fake.holdsAnswer = true
        let coordinator = makeEnabled(fake)
        let request = Task { await coordinator.requestAuthorizationIfNeeded() }
        // 尋ねている途中になるまで待つ（譲る回数に上限を付け、届かなければ失敗にして止める）
        guard await AsyncTestSupport.eventually({ fake.pendingAnswer != nil }) else {
            Issue.record("通知の許可を尋ねている途中になりませんでした")
            request.cancel()
            return
        }

        let waiter = Task {
            await coordinator.waitForAuthorizationRequest()
            fake.events.append("waited")
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(fake.events.isEmpty)

        fake.answer(true)
        await waiter.value
        await request.value
        #expect(fake.events == ["register", "waited"])
    }

    /// 尋ねていなければ（まだ・もう終わった・通知を使わない）、待たずにすぐ返る
    @Test
    func waitForAuthorizationRequestReturnsImmediatelyWhenNotAsking() async {
        let fake = FakePush()
        let coordinator = makeEnabled(fake)
        await coordinator.waitForAuthorizationRequest()
        #expect(fake.requestCount == 0)

        await coordinator.requestAuthorizationIfNeeded()
        await coordinator.waitForAuthorizationRequest()
        #expect(fake.requestCount == 1)

        await PushNotificationCoordinator(router: DeepLinkRouter()).waitForAuthorizationRequest()
    }

    /// 起動したときは尋ねず、許可済みのときだけ APNs に登録する
    @Test
    func registersOnLaunchOnlyWhenAuthorized() async {
        let fake = FakePush()
        let coordinator = makeEnabled(fake)
        await coordinator.registerIfAuthorized()
        #expect(fake.requestCount == 0)
        #expect(fake.registerCount == 0)

        fake.status = .authorized
        await coordinator.registerIfAuthorized()
        #expect(fake.registerCount == 1)
    }

    /// 通知を使わないとき（テスト・撮影・接続できない）は、尋ねない・登録しない・書かない
    @Test
    func disabledDoesNothing() async {
        let coordinator = PushNotificationCoordinator(router: DeepLinkRouter())
        await coordinator.requestAuthorizationIfNeeded()
        await coordinator.registerIfAuthorized()
        coordinator.didReceiveAPNSToken(Data([1]))
        await coordinator.didReceiveFCMToken("t1")
        await coordinator.activate(userID: "u1")
        #expect(!coordinator.isEnabled)
    }

    /// APNs のトークンを FCM に渡す
    @Test
    func passesAPNSTokenToFCM() {
        let fake = FakePush()
        makeEnabled(fake).didReceiveAPNSToken(Data([1, 2]))
        #expect(fake.apnsTokens == [Data([1, 2])])
    }

    /// トークンはホームが出てから（`users/{uid}` ができてから）書く。どちらが先に届いても、両方そろったら書く
    @Test
    func writesTokenAfterActivation() async {
        let fake = FakePush()
        let coordinator = makeEnabled(fake)
        await coordinator.didReceiveFCMToken("t1")
        #expect(fake.writes.isEmpty)
        await coordinator.activate(userID: "u1")
        #expect(fake.writes == ["add t1 u1"])
        #expect(fake.saved == PushTokenRegistration(userID: "u1", token: "t1"))

        let other = FakePush()
        let second = makeEnabled(other)
        await second.activate(userID: "u1")
        #expect(other.writes.isEmpty)
        await second.didReceiveFCMToken("t1")
        #expect(other.writes == ["add t1 u1"])
    }

    /// トークンが替わったら、古いトークンを外して新しいトークンを足す
    @Test
    func replacesRefreshedToken() async {
        let fake = FakePush()
        let coordinator = makeEnabled(fake)
        await coordinator.activate(userID: "u1")
        await coordinator.didReceiveFCMToken("t1")
        await coordinator.didReceiveFCMToken("t2")
        #expect(fake.writes == ["add t1 u1", "remove t1 u1", "add t2 u1"])
        #expect(fake.saved == PushTokenRegistration(userID: "u1", token: "t2"))
    }

    /// 前に別の人で書いていたら、トークンを作り直してから今の人に書く
    @Test
    func rotatesTokenForAnotherUser() async {
        let fake = FakePush()
        fake.saved = PushTokenRegistration(userID: "old", token: "t1")
        let coordinator = makeEnabled(fake)
        await coordinator.didReceiveFCMToken("t1")
        await coordinator.activate(userID: "u2")
        #expect(fake.deleteCount == 1)
        #expect(fake.writes == ["add fresh u2"])
        #expect(fake.saved == PushTokenRegistration(userID: "u2", token: "fresh"))
    }

    /// 作り直せなければ、いまのトークンのまま今の人に書く（自分のルームの通知は届くように）
    @Test
    func keepsTokenWhenRotationFails() async {
        let fake = FakePush()
        fake.saved = PushTokenRegistration(userID: "old", token: "t1")
        fake.deleteFails = true
        let coordinator = makeEnabled(fake)
        await coordinator.didReceiveFCMToken("t1")
        await coordinator.activate(userID: "u2")
        #expect(fake.writes == ["add t1 u2"])
        #expect(fake.saved == PushTokenRegistration(userID: "u2", token: "t1"))
    }

    /// 通知を開いたら、行き先を `DeepLinkRouter` に渡す（ホームが出たら受け取って開く）
    @Test
    func openingNotificationHandsDestinationToRouter() {
        let router = DeepLinkRouter()
        let destination = PushDestination(kind: .drawn, roomID: "r1", target: .result, drawID: "d1")
        PushNotificationCoordinator(router: router).open(destination)
        #expect(router.pendingNotification == destination)
        #expect(router.takePendingNotification() == destination)
        #expect(router.pendingNotification == nil)
    }

    /// 前面で届いた通知は、いま出しているルームの画面と比べて出すかを決める（`PushForegroundPolicy`）
    @Test
    func foregroundBannerFollowsVisibleScreen() {
        let coordinator = PushNotificationCoordinator(router: DeepLinkRouter())
        let destination = PushDestination(kind: .unlocked, roomID: "r1", target: .room)
        #expect(coordinator.showsBanner(for: destination))
        coordinator.visibleRoomScreen = VisibleRoomScreen(roomID: "r1", isGachaCover: false)
        #expect(!coordinator.showsBanner(for: destination))
    }

    /// UI テスト・撮影モードでは、起動引数のペイロードで通知から開かれたことにする（それ以外の起動では読まない）
    @Test
    func launchArgumentOpensNotificationOnlyInTesting() throws {
        let json = #"{"roomId":"demo-room","target":"room","type":"unlocked"}"#
        let testing = LaunchContext(arguments: ["-uiTesting", "-open-notification", json], environment: [:])
        let payload = try #require(testing.openNotification)
        #expect(PushDestination(userInfo: payload) == PushDestination(kind: .unlocked, roomID: "demo-room", target: .room))

        let normal = LaunchContext(arguments: ["-open-notification", json], environment: [:])
        #expect(normal.openNotification == nil)
        let broken = LaunchContext(arguments: ["-uiTesting", "-open-notification", "{"], environment: [:])
        #expect(broken.openNotification == nil)
    }
}
