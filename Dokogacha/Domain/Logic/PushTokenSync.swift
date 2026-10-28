//
//  PushTokenSync.swift
//  Dokogacha
//

import Foundation

/// この端末が最後に `users/{uid}.fcmTokens` に書いた FCM のトークンと、その持ち主（端末に残す）
nonisolated struct PushTokenRegistration: Codable, Equatable, Sendable {
    /// 書いた先のユーザーの uid
    let userID: String
    /// 書いた FCM のトークン
    let token: String
}

/// FCM のトークンを `users/{uid}.fcmTokens` にどう書くか（05 の §3）。
///
/// - 前に書いたものが無い・同じ人の同じトークン → 足す（`arrayUnion` なので冪等。起動のたびに足し直し、サーバーが外した後でも戻す）
/// - 同じ人でトークンが替わった（FCM が作り直した） → 古いトークンを外して新しいトークンを足す
/// - 別の人に替わった（サーバー側でサインアウトされ、匿名でサインインし直した） → 端末のトークンを作り直す。
///   前の人のドキュメントは今の人からは書き換えられない（ルールで本人だけ）ので、トークンを無効にして、
///   前の人のルームの通知がこの端末に届かないようにする（無効になったトークンは、送ったときにサーバーが外す）
nonisolated enum PushTokenSync {
    /// どう書くか
    enum Action: Equatable, Sendable {
        /// `token` を足す
        case add(token: String)
        /// `old` を外して `new` を足す
        case replace(old: String, new: String)
        /// 端末のトークンを作り直してから、新しいトークンを足す
        case rotateToken
    }

    /// どう書くかを決める
    /// - Parameters:
    ///   - saved: 前に書いたトークンと持ち主（無ければ nil）
    ///   - userID: いまサインインしている人
    ///   - token: いまの FCM のトークン
    static func action(saved: PushTokenRegistration?, userID: String, token: String) -> Action {
        guard let saved else {
            return .add(token: token)
        }
        if saved.userID != userID {
            return .rotateToken
        }
        if saved.token != token {
            return .replace(old: saved.token, new: token)
        }
        return .add(token: token)
    }
}

/// 通知の許可の状態（`UNAuthorizationStatus` から、このアプリで使う区別だけを取り出したもの）
nonisolated enum PushAuthorizationStatus: Equatable, Sendable {
    /// まだ尋ねていない
    case notDetermined
    /// 許可しなかった（設定で切った）
    case denied
    /// 許可した（仮の許可を含む）
    case authorized
}

/// 通知の許可を尋ねるか・APNs に登録するかの決まり（02 の §8「通知の許可ダイアログは、初めてルームを作成または参加したときに表示」）。
///
/// Firebase に繋いだとき（Emulator・dev・prod）だけ通知を使う。Unit テストのホスト・`-uiTesting`・撮影モード
/// （Firebase を初期化しない）と、サーバーに接続できないときは、尋ねない・登録しない（ダイアログがテストの画面を塞がないように）
nonisolated enum PushNotificationPolicy {
    /// 通知を使うか
    /// - Parameter connection: 起動時の接続の状態
    static func isEnabled(connection: ServerConnection) -> Bool {
        connection.isFirebaseConfigured
    }

    /// ルームを作成・参加したときに許可を尋ねるか（まだ尋ねていないときだけ。初めて作成・参加したときに当たる）
    /// - Parameter status: いまの許可の状態
    static func shouldRequestAuthorization(status: PushAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    /// APNs に登録してトークンを作るか（許可したときだけ。許可しなかった人のトークンは保存しない）
    /// - Parameter status: いまの許可の状態
    static func shouldRegister(status: PushAuthorizationStatus) -> Bool {
        status == .authorized
    }
}
