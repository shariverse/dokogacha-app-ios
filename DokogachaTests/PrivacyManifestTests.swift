//
//  PrivacyManifestTests.swift
//  DokogachaTests
//

import Foundation
import Testing

/// プライバシーマニフェスト（`PrivacyInfo.xcprivacy`）の申告が、実装と 06 の §5（プライバシーポリシーの「取得する情報」）に合っていることを確かめる（タスク 45）。
///
/// マニフェストの書き損じ（種類の名前の打ち間違い・目的の書き忘れ）があってもビルドは通り、App Store Connect への提出で初めて分かるので、
/// ビルドしたアプリに入ったファイルを読んで確かめる。App Store Connect の「App のプライバシー」はこの一覧と揃える
struct PrivacyManifestTests {
    /// 収集するデータの種類（`NSPrivacyCollectedDataType` の接頭辞を除いた名前）と、アカウントに紐付けるか
    private static let expectedLinkedTypes: [String: Bool] = [
        // 06 の §5: ユーザー ID・表示名・投稿内容
        "UserID": true,
        "Name": true,
        "OtherUserContent": true,
        // 広告非表示の購入（F-51）
        "PurchaseHistory": true,
        // 通知のトークン・Analytics のインスタンスの ID・広告 ID
        "DeviceID": true,
        // 06 の §5: 広告データ（Google Mobile Ads）
        "AdvertisingData": true,
        "ProductInteraction": true,
        "CoarseLocation": true,
        // 06 の §5: 診断データ（Crashlytics・Analytics。ユーザー ID を渡さないので紐付けない）
        "CrashData": false,
        "PerformanceData": false,
        "OtherDiagnosticData": false
    ]

    /// 種類の名前の接頭辞
    private static let typePrefix = "NSPrivacyCollectedDataType"
    /// 目的の名前の接頭辞
    private static let purposePrefix = "NSPrivacyCollectedDataTypePurpose"
    /// Apple が定める目的
    private static let knownPurposes: Set<String> = [
        "ThirdPartyAdvertising", "DeveloperAdvertising", "Analytics", "ProductPersonalization", "AppFunctionality", "Other"
    ]

    /// ビルドしたアプリに入ったマニフェスト
    private static func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        return try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
    }

    /// 収集するデータの一覧（種類の名前 → 申告）
    private static func collectedTypes() throws -> [String: [String: Any]] {
        let entries = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        var types: [String: [String: Any]] = [:]
        for entry in entries {
            let fullName = try #require(entry["NSPrivacyCollectedDataType"] as? String)
            #expect(fullName.hasPrefix(typePrefix))
            let type = String(fullName.dropFirst(typePrefix.count))
            // 同じ種類を 2 回書くと、App Store Connect の申告とどちらを合わせるか分からなくなる
            #expect(types[type] == nil, "\(type) が 2 回あります")
            types[type] = entry
        }
        return types
    }

    @Test
    func declaresTrackingForAds() throws {
        // ATT で許可した人にはパーソナライズした広告を出す（F-50）
        #expect(try Self.manifest()["NSPrivacyTracking"] as? Bool == true)
    }

    @Test
    func collectedTypesMatchImplementation() throws {
        let types = try Self.collectedTypes()
        #expect(Set(types.keys) == Set(Self.expectedLinkedTypes.keys))
        for (type, linked) in Self.expectedLinkedTypes {
            #expect(types[type]?["NSPrivacyCollectedDataTypeLinked"] as? Bool == linked, "\(type) の Linked")
        }
    }

    /// トラッキングに使うのは、ATT で許可した人の広告 ID（DeviceID）だけ
    @Test
    func onlyDeviceIDIsUsedForTracking() throws {
        let tracked = try Self.collectedTypes().filter { $0.value["NSPrivacyCollectedDataTypeTracking"] as? Bool == true }
        #expect(Set(tracked.keys) == ["DeviceID"])
        for (type, entry) in try Self.collectedTypes() {
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] is Bool, "\(type) の Tracking")
        }
    }

    /// どの種類にも、Apple が定める目的が 1 つ以上ある
    @Test
    func everyTypeHasKnownPurposes() throws {
        for (type, entry) in try Self.collectedTypes() {
            let purposes = try #require(entry["NSPrivacyCollectedDataTypePurposes"] as? [String], "\(type) の目的")
            #expect(!purposes.isEmpty, "\(type) の目的が空です")
            for purpose in purposes {
                #expect(purpose.hasPrefix(Self.purposePrefix))
                #expect(Self.knownPurposes.contains(String(purpose.dropFirst(Self.purposePrefix.count))), "\(type) の \(purpose)")
            }
        }
    }

    /// 理由の申告が必要な API は、アプリのコードが使う UserDefaults（アプリ自身の設定・状態の保存 CA92.1）だけ
    @Test
    func declaresUserDefaultsReason() throws {
        let entries = try #require(try Self.manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(entries.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
