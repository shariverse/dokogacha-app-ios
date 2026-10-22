//
//  ReportedContentTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 報告した候補のひとこと・参考 URL を隠す規則（`ReportedContent`）と、報告した候補を端末に覚える窓口（02 の §3.5 F-14）
struct ReportedContentTests {
    /// テストだけで使う `UserDefaults`（ほかのテスト・アプリの値と混ぜない）
    static func makeDefaults() throws -> UserDefaults {
        let name = "ReportedContentTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 報告した候補はひとことを出さない。報告していなければ、空でないひとことだけを出す
    @Test
    func noteIsHiddenOnlyWhenReported() {
        #expect(ReportedContent.visibleNote("海！", isReported: false) == "海！")
        #expect(ReportedContent.visibleNote("海！", isReported: true) == nil)
        #expect(ReportedContent.visibleNote("", isReported: false) == nil)
    }

    /// 参考 URL は http・https だけ。報告した候補は出さない
    @Test
    func urlIsHiddenWhenReportedOrNotWeb() {
        #expect(ReportedContent.visibleURL("https://example.com/a", isReported: false)?.absoluteString == "https://example.com/a")
        #expect(ReportedContent.visibleURL("HTTP://example.com", isReported: false) != nil)
        #expect(ReportedContent.visibleURL("https://example.com/a", isReported: true) == nil)
        #expect(ReportedContent.visibleURL("javascript:alert(1)", isReported: false) == nil)
        #expect(ReportedContent.visibleURL(nil, isReported: false) == nil)
    }

    /// 鍵はルームと候補で決まり、別のルームの同じ ID の候補と取り違えない
    @Test
    func keyIncludesRoom() {
        #expect(ReportedContent.key(roomID: "r1", candidateID: "c1") == "r1/c1")
        #expect(ReportedContent.key(roomID: "r1", candidateID: "c1") != ReportedContent.key(roomID: "r2", candidateID: "c1"))
    }

    /// 覚えた候補は、作り直した窓口からも見える（アプリを閉じても残る）。同じ候補を重ねない
    @Test
    func userDefaultsStoreRemembersAcrossInstances() throws {
        let defaults = try Self.makeDefaults()
        let store = UserDefaultsReportedCandidateStore(defaults: defaults)
        #expect(!store.hasReported(roomID: "r1", candidateID: "c1"))
        store.markReported(roomID: "r1", candidateID: "c1")
        store.markReported(roomID: "r1", candidateID: "c1")
        #expect(store.hasReported(roomID: "r1", candidateID: "c1"))
        #expect(!store.hasReported(roomID: "r2", candidateID: "c1"))
        #expect(UserDefaultsReportedCandidateStore(defaults: defaults).hasReported(roomID: "r1", candidateID: "c1"))
        #expect(defaults.stringArray(forKey: UserDefaultsReportedCandidateStore.key) == ["r1/c1"])
    }

    /// 上限を超えたら、古いものから捨てる
    @Test
    func userDefaultsStoreDropsOldestOverCapacity() throws {
        let store = UserDefaultsReportedCandidateStore(defaults: try Self.makeDefaults())
        for index in 0...UserDefaultsReportedCandidateStore.capacity {
            store.markReported(roomID: "r", candidateID: "c\(index)")
        }
        #expect(!store.hasReported(roomID: "r", candidateID: "c0"))
        #expect(store.hasReported(roomID: "r", candidateID: "c1"))
        #expect(store.keys.count == UserDefaultsReportedCandidateStore.capacity)
    }

    /// メモリの窓口は空から始め、覚えた候補だけを報告済みにする
    @Test
    func inMemoryStore() {
        let store = InMemoryReportedCandidateStore()
        #expect(!store.hasReported(roomID: "r1", candidateID: "c1"))
        store.markReported(roomID: "r1", candidateID: "c1")
        #expect(store.hasReported(roomID: "r1", candidateID: "c1"))
    }
}
