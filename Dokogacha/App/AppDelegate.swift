//
//  AppDelegate.swift
//  Dokogacha
//

import UIKit
import UserNotifications

/// アプリの起動時の処理（Firebase・広告の初期化と、データ層の実装の選択）と、プッシュ通知（APNs・FCM・通知を開いたとき）の受け口
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// サーバーへの接続とサインインの状態。`DokoGachaApp` が `@Environment` で画面に渡す
    let serverSession = ServerSession()
    /// 招待リンク・通知で開かれたときの行き先。`DokoGachaApp` が URL を渡し、`RootView` が画面に渡す
    let deepLinks = DeepLinkRouter()
    /// プッシュ通知のまとめ役（`DokoGachaApp` が `@Environment` で画面に渡す）。Firebase に繋いだときだけ通知を使う
    let push: PushNotificationCoordinator
    /// 広告のまとめ役（`DokoGachaApp` が `@Environment` で画面に渡す）。テストでは広告を読み込まず、撮影モードでは固定の枠を出す
    let ads: AdCoordinator

    /// `UNUserNotificationCenter`・`Messaging` の delegate（どちらも弱い参照なので、ここで持つ）
    private var notificationObserver: NotificationCenterObserver?
    private var messagingObserver: MessagingTokenObserver?

    override init() {
        push = PushNotificationCoordinator(router: deepLinks)
        let adUnitID = Bundle.main.object(forInfoDictionaryKey: AdCoordinator.adUnitIDInfoKey) as? String
        ads = AdCoordinator(mode: AdMode.make(launch: .current, adUnitID: adUnitID), service: GoogleMobileAdsService())
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let launch = LaunchContext.current
        let connection = FirebaseBootstrap.configure(plan: FirebaseBootstrap.currentPlan())
        // Firebase を初期化したら Firebase の実装、テスト・撮影なら擬似のサーバー（`-demo-scenario` のデータ）を使う
        serverSession.start(connection: connection, services: DataServices.make(connection: connection, launch: launch))
        // 本物の広告を読み込むときだけ Google Mobile Ads を初期化する（Unit テストのホスト・`-uiTesting`・撮影モードでは初期化しない）
        ads.start()
        if PushNotificationPolicy.isEnabled(connection: connection) {
            startPushNotifications()
        }
        // UI テスト・撮影モードでは、起動引数の URL で招待リンクから開かれたことにする（Simulator では Universal Links で開けないため）
        if let url = launch.openURL {
            deepLinks.handle(url)
        }
        // UI テスト・撮影モードでは、起動引数のペイロードで通知から開かれたことにする（擬似のサーバーでは通知が届かないため）
        if let destination = launch.openNotification.flatMap(PushDestination.init(userInfo:)) {
            deepLinks.handle(destination)
        }
        return true
    }

    /// 通知を使うとき（Firebase に繋いだとき）だけ、FCM と通知の delegate を付け、許可済みなら APNs に登録する。
    ///
    /// 起動していないときに通知を開かれたら、その通知は起動の直後に `UNUserNotificationCenterDelegate` に届くので、
    /// `didFinishLaunching` を返す前に delegate を付ける
    private func startPushNotifications() {
        push.enable(
            authorization: SystemNotificationAuthorizationClient(),
            registrar: SystemRemoteNotificationRegistrar(),
            tokens: FirebasePushTokenProvider(),
            writer: FirestorePushTokenWriter(gateway: FirebaseFirestoreGateway()),
            store: UserDefaultsPushTokenRegistrationStore()
        )
        let push = push
        let notificationObserver = NotificationCenterObserver(
            showsBanner: { destination in push.showsBanner(for: destination) },
            onOpen: { destination in push.open(destination) }
        )
        let messagingObserver = MessagingTokenObserver { token in
            Task { await push.didReceiveFCMToken(token) }
        }
        UNUserNotificationCenter.current().delegate = notificationObserver
        FirebasePushTokenProvider.setDelegate(messagingObserver)
        self.notificationObserver = notificationObserver
        self.messagingObserver = messagingObserver
        Task { await push.registerIfAuthorized() }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didReceiveAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushNotificationCoordinator.logRegistrationFailure(error)
    }
}
