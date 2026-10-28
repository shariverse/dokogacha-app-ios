//
//  PlaceSearchModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-08「場所を探す」の検索欄・エリアと結果の状態（03 の S-08 の 1〜3・5・6）。
///
/// - 入力のたびには検索しない。入力から 0.3 秒待ち（03 の S-08「入力から0.3秒後に MKLocalSearch を実行」）、待つ間に入力が変わったら前の検索は捨てる
/// - クイックカテゴリ・キーボードの検索は、待たずにその語で検索する
/// - エリアを選び直すと、端末に覚えて、語があれば待たずにそのエリアで検索し直す（初めは覚えているエリア。Issue #131）
/// - 結果が届いたときに語かエリアが変わっていれば、その結果は映さない（遅れて届いた古い結果で上書きしない）
/// - 通信できなければトーストを出す（結果は出さない）
///
/// 待ち方（`sleep`）を差し替えられるので、テストは固定の時間を待たずにデバウンスを確かめられる。
@Observable
final class PlaceSearchModel {
    /// 検索の状態
    enum Phase: Equatable {
        /// 語が空（何も出さない）
        case idle
        /// 検索している途中（前の結果は消し、行の形を保った読み込み中を出す）
        case searching
        /// 結果が 1 件以上
        case results([SearchedPlace])
        /// 結果が 0 件（「見つかりませんでした」）
        case noResults
        /// 通信できなかった（トーストを出し、結果は出さない）
        case failed
    }

    /// 待つ処理の型（テストでは、待ちを手で終わらせられるものに差し替える）
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// 入力してから検索するまで待つ時間（03 の S-08「入力から0.3秒後」）
    static let debounce: Duration = .milliseconds(300)
    /// クイックカテゴリ（03 の S-08 の 2。押すとその語で検索）
    static let quickCategories: [LocalizedStringResource] = ["水族館", "自然", "グルメ", "テーマパーク", "街歩き"]

    /// 検索欄の語（`updateQuery(_:)`・`searchNow(_:)` で変える）
    private(set) var query = ""
    /// 検索の状態
    private(set) var phase = Phase.idle
    /// 検索するエリア（`selectArea(_:)` で変える）
    private(set) var area: SearchArea

    @ObservationIgnored private let places: any PlaceSearchService
    @ObservationIgnored private let areaStore: any SearchAreaStore
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let sleep: Sleep
    /// 待っている・動いている検索（新しい語で検索するとき・画面が消えたときに止める）
    @ObservationIgnored private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - places: 場所検索の窓口（MapKit か擬似の検索）
    ///   - areaStore: 選んだエリアを覚える先（既定はメモリだけ）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - sleep: 検索まで待つ処理（テストでは手で進めるものを渡す）
    init(
        places: any PlaceSearchService,
        areaStore: any SearchAreaStore = InMemorySearchAreaStore(),
        toasts: DGToastCenter,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.places = places
        self.areaStore = areaStore
        self.toasts = toasts
        self.sleep = sleep
        area = areaStore.area
    }

    /// いま検索している語（前後の空白を取り除いたもの）
    var trimmedQuery: String {
        NameValidation.trimWhitespace(query)
    }

    /// 検索欄の語が変わった。0.3 秒待ってから検索する（待つ間にまた変わったら、前の検索はしない）。空なら結果を消す
    func updateQuery(_ text: String) {
        guard text != query else {
            return
        }
        guard let word = begin(text) else {
            return
        }
        let sleep = sleep
        task = Task { [weak self] in
            do {
                try await sleep(Self.debounce)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.run(word)
        }
    }

    /// クイックカテゴリ・キーボードの検索が押された。その語を検索欄の語にし、待たずに検索する（空なら結果を消す）
    func searchNow(_ text: String) {
        guard let word = begin(text) else {
            return
        }
        task = Task { [weak self] in
            await self?.run(word)
        }
    }

    /// エリアのチップ・「全国で探す」が押された。覚えて、語があれば待たずにそのエリアで検索し直す（同じエリアなら何もしない）
    func selectArea(_ newArea: SearchArea) {
        guard newArea != area else {
            return
        }
        area = newArea
        areaStore.save(newArea)
        searchNow(query)
    }

    /// 語を入れ替えて前の検索を止める。空なら結果を消して nil
    private func begin(_ text: String) -> String? {
        query = text
        task?.cancel()
        task = nil
        let word = trimmedQuery
        if word.isEmpty {
            phase = .idle
            return nil
        }
        return word
    }

    /// いまのエリアで検索して結果を映す（同じ ID の結果は 1 件にする）。cancel された・語かエリアが変わったときは映さない
    func run(_ word: String) async {
        let area = area
        phase = .searching
        do {
            let results = SearchedPlace.uniqued(try await places.search(word, in: area))
            guard !Task.isCancelled, trimmedQuery == word, self.area == area else {
                return
            }
            phase = results.isEmpty ? .noResults : .results(results)
        } catch {
            let appError = AppError.wrapping(error)
            guard !Task.isCancelled, !appError.isCancellation, trimmedQuery == word, self.area == area else {
                return
            }
            phase = .failed
            toasts.show(text: appError.message)
        }
    }

    /// 待っている・動いている検索を止める（画面が消えたとき。Task は self を弱く持つが、待ちを残さない）
    func cancel() {
        task?.cancel()
        task = nil
    }
}
