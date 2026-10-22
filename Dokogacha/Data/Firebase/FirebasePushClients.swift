//
//  FirebasePushClients.swift
//  Dokogacha
//

@preconcurrency import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// `UNUserNotificationCenter` を使う `NotificationAuthorizationClient`
struct SystemNotificationAuthorizationClient: NotificationAuthorizationClient {
    func authorizationStatus() async -> PushAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// `UIApplication` を使う `RemoteNotificationRegistrar`
struct SystemRemoteNotificationRegistrar: RemoteNotificationRegistrar {
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// `Messaging` を使う `PushTokenProvider`。`FirebaseApp.configure` の後でだけ作る
struct FirebasePushTokenProvider: PushTokenProvider {
    /// FCM のトークンが届く先を付ける（`Messaging.delegate` は弱い参照なので、呼んだ側が持ち続ける）
    static func setDelegate(_ observer: MessagingTokenObserver) {
        Messaging.messaging().delegate = observer
    }

    func setAPNSToken(_ token: Data) {
        Messaging.messaging().apnsToken = token
    }

    // firebase-ios-sdk 13 は登録トークンの API を非推奨にし、Firebase Installations の ID で登録する方式（`register`）を勧めている。
    // このアプリは 05 の §3 のとおり登録トークン（`users.fcmTokens`）で送るので、非推奨の API を使う。
    // 非推奨の印を付けた関数の中では、非推奨の API を使っても警告にならない（protocol を通して呼ぶので、呼ぶ側にも警告は出ない）

    @available(*, deprecated, message: "FCM の登録トークン（users.fcmTokens）で送るため、非推奨の deleteToken を使う")
    func deleteToken() async throws {
        try await Messaging.messaging().deleteToken()
    }

    @available(*, deprecated, message: "FCM の登録トークン（users.fcmTokens）で送るため、非推奨の token を使う")
    func fetchToken() async throws -> String {
        try await Messaging.messaging().token()
    }
}

/// `MessagingDelegate` を受ける。SDK はどのスレッドからも呼びうるので nonisolated にし、トークンは MainActor に渡す。
///
/// 状態を持たない（渡す先の関数だけを持つ）ので `Sendable`
nonisolated final class MessagingTokenObserver: NSObject, MessagingDelegate, Sendable {
    private let onToken: @MainActor @Sendable (String?) -> Void

    /// - Parameter onToken: FCM のトークンが届いたとき（作られた・作り直された）の処理
    init(onToken: @escaping @MainActor @Sendable (String?) -> Void) {
        self.onToken = onToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            onToken(fcmToken)
        }
    }
}

/// `UNUserNotificationCenterDelegate` を受ける（前面で届いた通知の出し方と、通知を開いたとき）。
///
/// SDK は MainActor の外から呼びうるので nonisolated にし、ペイロードを値（`PushDestination`）にしてから MainActor に渡す。
/// 状態を持たない（渡す先の関数だけを持つ）ので `Sendable`。
///
/// FCM の AppDelegate の差し替え（swizzling）を止めているので、届いた・開いた通知は自分で `Messaging.appDidReceiveMessage` に渡す
/// （渡さないと、FCM の配信・開封の計測（Analytics の `notification_foreground`・`notification_open`）が記録されない）。
/// この delegate は Firebase に繋いだときだけ付ける（`AppDelegate.startPushNotifications`）
nonisolated final class NotificationCenterObserver: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let showsBanner: @MainActor @Sendable (PushDestination?) -> Bool
    private let onOpen: @MainActor @Sendable (PushDestination) -> Void

    /// - Parameters:
    ///   - showsBanner: 前面で届いた通知をバナーで出すか
    ///   - onOpen: 通知を開いた（タップした）ときの処理
    init(
        showsBanner: @escaping @MainActor @Sendable (PushDestination?) -> Bool,
        onOpen: @escaping @MainActor @Sendable (PushDestination) -> Void
    ) {
        self.showsBanner = showsBanner
        self.onOpen = onOpen
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
        let destination = PushDestination(userInfo: notification.request.content.userInfo)
        return await showsBanner(destination) ? [.banner, .list, .sound] : []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let destination = PushDestination(userInfo: response.notification.request.content.userInfo) else {
            return
        }
        await onOpen(destination)
    }
}
