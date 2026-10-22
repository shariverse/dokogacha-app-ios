//
//  PushTokenSyncTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// FCM のトークンを `users/{uid}.fcmTokens` にどう書くかと、通知の許可を尋ねる時機の決まり（02 の §8）を確かめる
struct PushTokenSyncTests {
    /// 初めて・同じ人の同じトークンなら足す（起動のたびに足し直す）
    @Test
    func addsTokenForFirstTimeAndSameRegistration() {
        #expect(PushTokenSync.action(saved: nil, userID: "u1", token: "t1") == .add(token: "t1"))
        let saved = PushTokenRegistration(userID: "u1", token: "t1")
        #expect(PushTokenSync.action(saved: saved, userID: "u1", token: "t1") == .add(token: "t1"))
    }

    /// 同じ人でトークンが替わったら、古いトークンを外して新しいトークンを足す
    @Test
    func replacesRefreshedToken() {
        let saved = PushTokenRegistration(userID: "u1", token: "t1")
        #expect(PushTokenSync.action(saved: saved, userID: "u1", token: "t2") == .replace(old: "t1", new: "t2"))
    }

    /// 別の人に替わったら、トークンを作り直す（前の人のルームの通知をこの端末に届けない）
    @Test
    func rotatesTokenWhenUserChanges() {
        let saved = PushTokenRegistration(userID: "u1", token: "t1")
        #expect(PushTokenSync.action(saved: saved, userID: "u2", token: "t1") == .rotateToken)
    }

    /// Firebase に繋いだときだけ通知を使う（テストのホスト・UI テスト・撮影モード・接続できないときは使わない）
    @Test
    func enablesOnlyWithFirebase() {
        #expect(PushNotificationPolicy.isEnabled(connection: .firebase(.emulator)))
        #expect(PushNotificationPolicy.isEnabled(connection: .firebase(.prod)))
        #expect(!PushNotificationPolicy.isEnabled(connection: .disabled(.unitTestHost)))
        #expect(!PushNotificationPolicy.isEnabled(connection: .disabled(.uiTesting)))
        #expect(!PushNotificationPolicy.isEnabled(connection: .disabled(.screenshotDemo)))
        #expect(!PushNotificationPolicy.isEnabled(connection: .unavailable(.missingOptionsFile(nil))))
        #expect(!PushNotificationPolicy.isEnabled(connection: .notStarted))
    }

    /// 許可はまだ尋ねていないときだけ尋ね、APNs には許可したときだけ登録する
    @Test
    func asksOnlyOnceAndRegistersWhenAuthorized() {
        #expect(PushNotificationPolicy.shouldRequestAuthorization(status: .notDetermined))
        #expect(!PushNotificationPolicy.shouldRequestAuthorization(status: .denied))
        #expect(!PushNotificationPolicy.shouldRequestAuthorization(status: .authorized))
        #expect(PushNotificationPolicy.shouldRegister(status: .authorized))
        #expect(!PushNotificationPolicy.shouldRegister(status: .denied))
        #expect(!PushNotificationPolicy.shouldRegister(status: .notDetermined))
    }
}
