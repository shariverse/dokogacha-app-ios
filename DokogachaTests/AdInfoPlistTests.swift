//
//  AdInfoPlistTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 広告と ATT のために Info.plist（xcconfig の値を含む）とプライバシーマニフェストに入れた値が、ビルドしたアプリに入っていることを確かめる。
///
/// 鍵の書き間違い・xcconfig の変数の設定漏れがあってもビルドは通り、広告が出ない・ATT のダイアログで落ちるだけなので、ここで検出する
struct AdInfoPlistTests {
    /// Google のテスト用の広告ユニット ID（アダプティブバナー）。本番の ID は公開前に人間が差し替える
    private static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"

    private static var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    @Test
    func bannerAdUnitIDComesFromXcconfig() {
        #expect(Self.info[AdCoordinator.adUnitIDInfoKey] as? String == Self.testBannerAdUnitID)
    }

    @Test
    func trackingUsageDescriptionMatchesSpec() {
        // 06 の §5 の文言
        #expect(Self.info["NSUserTrackingUsageDescription"] as? String == "あなたに合った広告を表示するために使用します")
    }

    @Test
    func skAdNetworkItemsIncludeGoogle() throws {
        let items = try #require(Self.info["SKAdNetworkItems"] as? [[String: String]])
        let identifiers = items.compactMap { $0["SKAdNetworkIdentifier"] }
        #expect(identifiers.count == items.count)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.contains("cstr6suwn9.skadnetwork"))
        #expect(identifiers.allSatisfy { $0.hasSuffix(".skadnetwork") })
    }

    @Test
    func privacyManifestDeclaresAdTracking() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        #expect(manifest["NSPrivacyTracking"] as? Bool == true)
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let types = collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        #expect(types.contains("NSPrivacyCollectedDataTypeDeviceID"))
        #expect(types.contains("NSPrivacyCollectedDataTypeAdvertisingData"))
    }
}
