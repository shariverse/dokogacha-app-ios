//
//  AccountDeviceDataTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// アカウントを削除した後（02 の F-06）に、この端末に残す値（見た抽選・報告した候補）を消すこと（PR #91 の持ち越し）
struct AccountDeviceDataTests {
    /// テストだけで使う `UserDefaults`（ほかのテスト・アプリの値と混ぜない）
    static func makeDefaults() throws -> UserDefaults {
        let name = "AccountDeviceDataTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 端末に残す窓口は、すべて忘れると作り直した窓口からも見えなくなる
    @Test
    func userDefaultsStoresForgetEverything() throws {
        let defaults = try Self.makeDefaults()
        let seen = UserDefaultsSeenDrawStore(defaults: defaults)
        let reported = UserDefaultsReportedCandidateStore(defaults: defaults)
        seen.markSeen(drawID: "d1")
        reported.markReported(roomID: "r1", candidateID: "c1")

        seen.removeAll()
        reported.removeAll()
        #expect(!seen.hasSeen(drawID: "d1"))
        #expect(!reported.hasReported(roomID: "r1", candidateID: "c1"))
        #expect(reported.keys.isEmpty)
        #expect(!UserDefaultsSeenDrawStore(defaults: defaults).hasSeen(drawID: "d1"))
        #expect(!UserDefaultsReportedCandidateStore(defaults: defaults).hasReported(roomID: "r1", candidateID: "c1"))
        #expect(defaults.object(forKey: UserDefaultsSeenDrawStore.key) == nil)
        #expect(defaults.object(forKey: UserDefaultsReportedCandidateStore.key) == nil)
    }

    /// データ層の窓口から作ると、見た抽選と報告した候補を消す（通知・購入のまとめ役が無くても動く）
    @Test
    func clearsServicesStores() {
        let services = DataServices.inMemory(InMemoryServer(), scenario: .empty)
        services.seenDraws.markSeen(drawID: "d1")
        services.reportedCandidates.markReported(roomID: "r1", candidateID: "c1")

        AccountDeviceData.make(services: services, push: nil, purchases: .disabled).clear()
        #expect(!services.seenDraws.hasSeen(drawID: "d1"))
        #expect(!services.reportedCandidates.hasReported(roomID: "r1", candidateID: "c1"))
    }
}
