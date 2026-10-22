//
//  PushNotificationCoordinator.swift
//  Dokogacha
//

import Foundation
import os

/// プッシュ通知（02 の §8 F-60）の端末側のまとめ役。`AppDelegate` が 1 つ持つ。
///
/// - 許可: 初めてルームを作成・参加したとき（`requestAuthorizationIfNeeded`。まだ尋ねていないときだけ）に尋ねる。
///   許可したら APNs に登録する。起動したときに許可済みなら、そのまま登録する（設定で後から許可した人も、次の起動で登録される）
/// - トークン: APNs のトークンを FCM に渡し、届いた FCM のトークンを、サインインしている人の `users/{uid}.fcmTokens` に足す
///   （`PushTokenSync`。表示名を登録してホームが出たとき（`activate`）と、トークンが替わったときに書く）
/// - 通知を開いた: 行き先を `DeepLinkRouter` に渡す（起動していない・バックグラウンドのとき。ホームが出たら開く）
/// - 前面で届いた: いま出しているルームの画面（`visibleRoomScreen`）と比べて、バナーで出すかを決める（`PushForegroundPolicy`）
///
/// 通知を使わないとき（Unit テストのホスト・`-uiTesting`・撮影モード・サーバーに接続できない。`PushNotificationPolicy`）は、
/// 尋ねない・登録しない・書かない
@Observable
final class PushNotificationCoordinator {
    /// 通知を使うか（`enable` で true になる）
    @ObservationIgnored private(set) var isEnabled = false
    /// いま前面に出しているルームの画面（`MainNavigationView` が入れる）
    @ObservationIgnored var visibleRoomScreen: VisibleRoomScreen?

    @ObservationIgnored private var authorization: any NotificationAuthorizationClient = DisabledPushClients()
    @ObservationIgnored private var registrar: any RemoteNotificationRegistrar = DisabledPushClients()
    @ObservationIgnored private var tokens: any PushTokenProvider = DisabledPushClients()
    @ObservationIgnored private var writer: any PushTokenWriter = DisabledPushClients()
    @ObservationIgnored private var store: any PushTokenRegistrationStore = DisabledPushClients()
    @ObservationIgnored private let router: DeepLinkRouter
    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Push")

    /// サインインしていて、表示名を登録済みの人（`activate` で入る）
    @ObservationIgnored private var userID: String?
    /// 届いた FCM のトークン
    @ObservationIgnored private var fcmToken: String?
    /// 書いている途中の処理（順に書くため、次の書き込みは前の書き込みの後に始める）
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// 最後に始めた、通知の許可を尋ねる処理（`waitForAuthorizationRequest` で待つ）
    @ObservationIgnored private var authorizationRequest: Task<Void, Never>?

    /// 通知を使わない状態で作る（`enable` を呼ぶまでは、尋ねない・登録しない・書かない）
    /// - Parameter router: 通知を開いたときの行き先を渡す先
    init(router: DeepLinkRouter) {
        self.router = router
    }

    /// 通知を使う（Firebase に繋いだときに、起動の処理から一度だけ呼ぶ）
    /// - Parameters:
    ///   - authorization: 通知の許可の窓口
    ///   - registrar: APNs への登録の窓口
    ///   - tokens: FCM のトークンの窓口
    ///   - writer: `users/{uid}.fcmTokens` に書く窓口
    ///   - store: 最後に書いたトークンを残す窓口
    func enable(
        authorization: any NotificationAuthorizationClient,
        registrar: any RemoteNotificationRegistrar,
        tokens: any PushTokenProvider,
        writer: any PushTokenWriter,
        store: any PushTokenRegistrationStore
    ) {
        isEnabled = true
        self.authorization = authorization
        self.registrar = registrar
        self.tokens = tokens
        self.writer = writer
        self.store = store
    }

    /// APNs への登録に失敗したことをログに残す（Simulator・署名に Push Notifications が無いときなど。通知が届かないだけで、ほかは動く）
    nonisolated static func logRegistrationFailure(_ error: any Error) {
        logger.error("APNs に登録できない: \(error.localizedDescription, privacy: .public)")
    }

    /// 起動したとき。許可済みなら APNs に登録する（まだ尋ねていなければ、ここでは尋ねない）
    func registerIfAuthorized() async {
        guard isEnabled else {
            return
        }
        if PushNotificationPolicy.shouldRegister(status: await authorization.authorizationStatus()) {
            registrar.registerForRemoteNotifications()
        }
    }

    /// ルームを作成・参加したとき。まだ尋ねていなければ通知の許可を尋ね、許可されたら APNs に登録する
    func requestAuthorizationIfNeeded() async {
        guard isEnabled else {
            return
        }
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.performAuthorizationRequest()
        }
        authorizationRequest = task
        await task.value
    }

    /// 通知の許可を尋ねている途中なら、答えが出るまで待つ（ATT のダイアログを通知のダイアログと重ねて出さないため）
    func waitForAuthorizationRequest() async {
        await authorizationRequest?.value
    }

    /// まだ尋ねていなければ通知の許可を尋ね、許可されたら APNs に登録する
    private func performAuthorizationRequest() async {
        guard PushNotificationPolicy.shouldRequestAuthorization(status: await authorization.authorizationStatus()) else {
            return
        }
        do {
            if try await authorization.requestAuthorization() {
                registrar.registerForRemoteNotifications()
            }
        } catch {
            Self.logger.error("通知の許可を尋ねられない: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 表示名を登録した人のホームが出たとき（`users/{uid}` があるので書ける）。トークンが届いていれば書く
    /// - Parameter userID: サインインしている人
    func activate(userID: String) async {
        guard isEnabled else {
            return
        }
        self.userID = userID
        await sync()
    }

    /// アカウントを削除した後（02 の F-06）。今の人と、最後に書いたトークンの持ち主の記録を忘れる。
    ///
    /// 前の人の `users/{uid}`（`fcmTokens`）はサーバーが消したので、次にサインインした人には、端末のトークンを作り直さずにそのまま足す
    /// （記録が残っていると「別の人に替わった」と判定して作り直す。`PushTokenSync`）。端末のトークンそのもの（FCM）は残す
    func forgetAccount() {
        userID = nil
        store.save(nil)
    }

    /// APNs のトークンが届いた（`AppDelegate` の `didRegisterForRemoteNotificationsWithDeviceToken`）
    func didReceiveAPNSToken(_ token: Data) {
        guard isEnabled else {
            return
        }
        tokens.setAPNSToken(token)
    }

    /// FCM のトークンが届いた（`MessagingDelegate`）。サインインしていれば書く
    func didReceiveFCMToken(_ token: String?) async {
        guard isEnabled, let token, !token.isEmpty else {
            return
        }
        fcmToken = token
        await sync()
    }

    /// 前面で届いた通知をバナーで出すか
    func showsBanner(for destination: PushDestination?) -> Bool {
        PushForegroundPolicy.showsBanner(for: destination, visible: visibleRoomScreen)
    }

    /// 通知を開いた。行き先を `DeepLinkRouter` に渡す（ホームが出ていれば、すぐに開く）
    func open(_ destination: PushDestination) {
        router.handle(destination)
    }

    /// 書き込みを、前の書き込みの後に順に行う
    private func sync() async {
        let previous = syncTask
        let task = Task { [weak self] in
            await previous?.value
            await self?.writeToken()
        }
        syncTask = task
        await task.value
    }

    /// いまの人といまのトークンで `fcmTokens` を書く（`PushTokenSync`）
    private func writeToken() async {
        guard let userID, let token = fcmToken else {
            return
        }
        switch PushTokenSync.action(saved: store.load(), userID: userID, token: token) {
        case let .add(token):
            writer.add(token: token, userID: userID)
            store.save(PushTokenRegistration(userID: userID, token: token))
        case let .replace(old, new):
            writer.remove(token: old, userID: userID)
            writer.add(token: new, userID: userID)
            store.save(PushTokenRegistration(userID: userID, token: new))
        case .rotateToken:
            store.save(nil)
            let fresh: String
            do {
                try await tokens.deleteToken()
                fresh = try await tokens.fetchToken()
            } catch {
                // 作り直せなければ、いまのトークンのまま今の人に書く（自分のルームの通知が届かなくなるより、前の人の通知が届く方を選ぶ）
                Self.logger.error("FCM のトークンを作り直せない: \(error.localizedDescription, privacy: .public)")
                fresh = token
            }
            fcmToken = fresh
            writer.add(token: fresh, userID: userID)
            store.save(PushTokenRegistration(userID: userID, token: fresh))
        }
    }
}

/// 通知を使わないときの窓口（何もしない）
private struct DisabledPushClients: NotificationAuthorizationClient, RemoteNotificationRegistrar, PushTokenProvider,
    PushTokenWriter, PushTokenRegistrationStore {
    func authorizationStatus() async -> PushAuthorizationStatus {
        .denied
    }

    func requestAuthorization() async throws -> Bool {
        false
    }

    func registerForRemoteNotifications() {}

    func setAPNSToken(_ token: Data) {}

    func deleteToken() async throws {}

    func fetchToken() async throws -> String {
        ""
    }

    func add(token: String, userID: String) {}

    func remove(token: String, userID: String) {}

    func load() -> PushTokenRegistration? {
        nil
    }

    func save(_ registration: PushTokenRegistration?) {}
}
