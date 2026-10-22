//
//  SeenDrawStoreTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 演出を見終えた抽選を端末に覚える（F-41「すでに見た抽選をもう一度再生しない」）
struct SeenDrawStoreTests {
    /// テストだけで使う `UserDefaults`（ほかのテスト・アプリの値と混ぜない）
    static func makeDefaults() throws -> UserDefaults {
        let name = "SeenDrawStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 覚えた抽選は、作り直した窓口からも見える（アプリを閉じても残る）
    @Test
    func remembersAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let store = UserDefaultsSeenDrawStore(defaults: defaults)
        #expect(!store.hasSeen(drawID: "d1"))
        store.markSeen(drawID: "d1")
        store.markSeen(drawID: "d1")
        #expect(store.hasSeen(drawID: "d1"))
        #expect(UserDefaultsSeenDrawStore(defaults: defaults).hasSeen(drawID: "d1"))
        #expect(defaults.stringArray(forKey: UserDefaultsSeenDrawStore.key) == ["d1"])
    }

    /// 上限を超えたら、古いものから捨てる
    @Test
    func dropsOldestOverCapacity() throws {
        let store = UserDefaultsSeenDrawStore(defaults: try Self.makeDefaults())
        for index in 0...UserDefaultsSeenDrawStore.capacity {
            store.markSeen(drawID: "d\(index)")
        }
        #expect(!store.hasSeen(drawID: "d0"))
        #expect(store.hasSeen(drawID: "d1"))
        #expect(store.hasSeen(drawID: "d\(UserDefaultsSeenDrawStore.capacity)"))
    }

    /// 擬似のサーバーの窓口は、メモリだけに覚える
    @Test
    func inMemoryServicesUseInMemoryStore() {
        let services = DataServices.inMemory(InMemoryServer(), scenario: .empty)
        #expect(services.seenDraws is InMemorySeenDrawStore)
        services.seenDraws.markSeen(drawID: "d1")
        #expect(services.seenDraws.hasSeen(drawID: "d1"))
    }
}
