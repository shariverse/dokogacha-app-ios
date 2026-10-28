//
//  ReportedCandidateStore.swift
//  Dokogacha
//

import Foundation
import Observation

/// この端末で報告した候補を覚える（02 の §3.5「報告した人の画面では、その候補のひとこととURLを非表示にする」）。
///
/// 報告（`reports`）はルールでクライアントから読めない（報告した人を投稿した人・ほかのメンバーに知られないため）ので、
/// 報告できた（または、もう報告済みと返った）候補を端末に覚えて隠す。候補のドキュメントに報告した人を書くと、
/// メンバー全員が読めてしまうため使わない。
/// 端末に覚えるだけなので、別の端末・入れ直したアプリでは隠れない（もう一度報告すると、サーバーは 2 つ目を作らずに成功を返し、また隠れる）。
///
/// 実装は `@Observable` にし、覚えた候補が増えたら画面の値（候補の行・詳細）を計算し直させる。
///
/// 鍵はルームと候補だけで、報告した人（uid）を含めない。この端末でサインインするアカウントが替わるのは、
/// アカウントを削除したとき（F-06。`removeAll` ですべて忘れる）と、Sign in with Apple で前の端末のアカウントに
/// サインインし直したとき（同じ人なので、隠したままにする）だけなので、uid ごとに分けなくてよい
protocol ReportedCandidateStore: AnyObject {
    /// この候補を報告したか
    func hasReported(roomID: String, candidateID: String) -> Bool
    /// 報告した候補として覚える
    func markReported(roomID: String, candidateID: String)
    /// 覚えた候補をすべて忘れる（アカウントを削除した後）
    func removeAll()
}

/// `UserDefaults` に覚える `ReportedCandidateStore`（アプリを閉じても残す）。
///
/// 覚えるのは新しい順に `capacity` 件まで（それより古い報告は、ひとこととURLがまた見えるようになる）
@Observable
final class UserDefaultsReportedCandidateStore: ReportedCandidateStore {
    /// 覚えておく件数の上限（1 人が報告する数としては十分に多い）
    static let capacity = 500
    /// `UserDefaults` の鍵
    static let key = "reportedCandidateKeys"

    /// 覚えている候補の鍵（`ReportedContent.key`。古い順）
    private(set) var keys: [String]

    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter defaults: 覚える先（テストでは専用の suite を渡す）
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = defaults.stringArray(forKey: Self.key) ?? []
    }

    func hasReported(roomID: String, candidateID: String) -> Bool {
        keys.contains(ReportedContent.key(roomID: roomID, candidateID: candidateID))
    }

    func markReported(roomID: String, candidateID: String) {
        let key = ReportedContent.key(roomID: roomID, candidateID: candidateID)
        var updated = keys.filter { $0 != key }
        updated.append(key)
        keys = Array(updated.suffix(Self.capacity))
        defaults.set(keys, forKey: Self.key)
    }

    func removeAll() {
        keys = []
        defaults.removeObject(forKey: Self.key)
    }
}

/// メモリにだけ覚える `ReportedCandidateStore`（擬似のサーバー・Unit テスト・`-uiTesting` で、起動ごとに空から始める）
@Observable
final class InMemoryReportedCandidateStore: ReportedCandidateStore {
    /// 覚えている候補の鍵（`ReportedContent.key`）
    private(set) var keys: Set<String>

    /// - Parameter keys: 初めから報告したことにする候補の鍵
    init(keys: Set<String> = []) {
        self.keys = keys
    }

    func hasReported(roomID: String, candidateID: String) -> Bool {
        keys.contains(ReportedContent.key(roomID: roomID, candidateID: candidateID))
    }

    func markReported(roomID: String, candidateID: String) {
        keys.insert(ReportedContent.key(roomID: roomID, candidateID: candidateID))
    }

    func removeAll() {
        keys.removeAll()
    }
}
