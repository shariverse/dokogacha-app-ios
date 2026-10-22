//
//  PushNotificationClients.swift
//  Dokogacha
//

import Foundation
import os

/// 通知の許可（`UNUserNotificationCenter`）の窓口。テストでは差し替えて、尋ねる時機を確かめる
protocol NotificationAuthorizationClient {
    /// いまの許可の状態
    func authorizationStatus() async -> PushAuthorizationStatus
    /// 許可を尋ねる（バナー・音・バッジ）。許可されたら true
    func requestAuthorization() async throws -> Bool
}

/// APNs への登録（`UIApplication.registerForRemoteNotifications`）の窓口
protocol RemoteNotificationRegistrar {
    /// APNs に登録する（結果は `AppDelegate` の `didRegisterForRemoteNotificationsWithDeviceToken` に届く）
    func registerForRemoteNotifications()
}

/// FCM のトークン（`Messaging`）の窓口
protocol PushTokenProvider {
    /// APNs のトークンを FCM に渡す（渡すと FCM のトークンができ、`MessagingDelegate` に届く）
    func setAPNSToken(_ token: Data)
    /// いまのトークンを無効にする（別の人に替わったとき）
    func deleteToken() async throws
    /// トークンを取り出す（無ければ作る）
    func fetchToken() async throws -> String
}

/// `users/{uid}.fcmTokens` に書く窓口（05 の §4。自分のドキュメントの `fcmTokens` だけはクライアントが直接書ける）
protocol PushTokenWriter {
    /// トークンを足す（`arrayUnion`。完了は待たない）
    func add(token: String, userID: String)
    /// トークンを外す（`arrayRemove`。完了は待たない）
    func remove(token: String, userID: String)
}

/// 最後に書いたトークンを端末に残す窓口
protocol PushTokenRegistrationStore {
    /// 残してあるもの（無ければ nil）
    func load() -> PushTokenRegistration?
    /// 残す（nil なら消す）
    func save(_ registration: PushTokenRegistration?)
}

/// Firestore に直接書く `PushTokenWriter`（`FirestoreGateway.update`。ルールで本人の `fcmTokens` だけ・10 個まで）
struct FirestorePushTokenWriter: PushTokenWriter {
    /// Firestore の窓口
    let gateway: any FirestoreGateway

    func add(token: String, userID: String) {
        gateway.update(path: FirestorePath.user(userID), fields: ["fcmTokens": .arrayUnion([token])])
    }

    func remove(token: String, userID: String) {
        gateway.update(path: FirestorePath.user(userID), fields: ["fcmTokens": .arrayRemove([token])])
    }
}

/// `UserDefaults` に残す `PushTokenRegistrationStore`
struct UserDefaultsPushTokenRegistrationStore: PushTokenRegistrationStore {
    /// 残すキー
    static let key = "push.tokenRegistration"
    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Push")

    /// 残す先
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PushTokenRegistration? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(PushTokenRegistration.self, from: data)
        } catch {
            Self.logger.error("残したトークンを読めない: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ registration: PushTokenRegistration?) {
        guard let registration else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(registration), forKey: Self.key)
        } catch {
            Self.logger.error("トークンを残せない: \(error.localizedDescription, privacy: .public)")
        }
    }
}
