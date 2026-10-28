//
//  PlaceSearchModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の検索欄（`PlaceSearchModel`）を確かめる: 入力から 0.3 秒のデバウンス（待ちは手で進める）・クイックカテゴリは待たない・
/// 遅れて届いた古い結果で上書きしない・0 件・通信エラーのトースト
struct PlaceSearchModelTests {
    static func makeModel(
        places: RecordingPlaceSearch = RecordingPlaceSearch(),
        sleeper: ManualSleeper = ManualSleeper(),
        toasts: DGToastCenter = DGToastCenter(visibleFor: .seconds(3_600))
    ) -> PlaceSearchModel {
        PlaceSearchModel(places: places, toasts: toasts, sleep: sleeper.sleep)
    }

    /// 結果の場所名
    static func names(_ phase: PlaceSearchModel.Phase) -> [String]? {
        guard case let .results(places) = phase else {
            return nil
        }
        return places.map(\.place.name)
    }

    /// 続けて入力しても、0.3 秒待った後の最後の語でだけ検索する（入力のたびに検索しない）
    @Test
    func debouncesTyping() async {
        let places = RecordingPlaceSearch()
        let sleeper = ManualSleeper()
        let model = Self.makeModel(places: places, sleeper: sleeper)

        model.updateQuery("水")
        model.updateQuery("水族")
        model.updateQuery("水族館")
        #expect(await AsyncTestSupport.eventually { sleeper.waitingCount == 3 })
        #expect(sleeper.requested.allSatisfy { $0 == PlaceSearchModel.debounce })
        #expect(PlaceSearchModel.debounce == .milliseconds(300))
        #expect(places.queries.isEmpty)

        sleeper.releaseAll()
        #expect(await AsyncTestSupport.eventually { Self.names(model.phase) != nil })
        #expect(places.queries == ["水族館"])
        #expect(Self.names(model.phase) == ["すみだ水族館", "サンシャイン水族館", "しながわ水族館", "鴨川シーワールド"])
    }

    /// 同じ語をもう一度入れても検索し直さない。前後の空白は取り除いて検索する
    @Test
    func sameQueryDoesNotRestartAndTrims() async {
        let places = RecordingPlaceSearch()
        let sleeper = ManualSleeper()
        let model = Self.makeModel(places: places, sleeper: sleeper)

        model.updateQuery(" 海 ")
        model.updateQuery(" 海 ")
        #expect(await AsyncTestSupport.eventually { sleeper.waitingCount == 1 })
        sleeper.releaseAll()
        #expect(await AsyncTestSupport.eventually { Self.names(model.phase) != nil })
        #expect(places.queries == ["海"])
        #expect(sleeper.requested.count == 1)
    }

    /// 語を空にしたら、待っている検索をやめて結果を消す
    @Test
    func emptyQueryClearsResults() async {
        let places = RecordingPlaceSearch()
        let sleeper = ManualSleeper()
        let model = Self.makeModel(places: places, sleeper: sleeper)

        model.searchNow("水族館")
        #expect(await AsyncTestSupport.eventually { Self.names(model.phase) != nil })
        model.updateQuery("高尾")
        #expect(await AsyncTestSupport.eventually { sleeper.waitingCount == 1 })
        model.updateQuery("  ")
        #expect(model.phase == .idle)
        sleeper.releaseAll()
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(places.queries == ["水族館"])
        #expect(model.phase == .idle)
    }

    /// クイックカテゴリ（・キーボードの検索）は待たずにその語で検索し、検索欄の語もその語にする
    @Test
    func searchNowSkipsDebounce() async {
        let places = RecordingPlaceSearch()
        let sleeper = ManualSleeper()
        let model = Self.makeModel(places: places, sleeper: sleeper)

        model.searchNow("グルメ")
        #expect(model.query == "グルメ")
        #expect(await AsyncTestSupport.eventually { Self.names(model.phase) != nil })
        #expect(Self.names(model.phase) == ["築地場外市場"])
        #expect(places.queries == ["グルメ"])
        #expect(sleeper.requested.isEmpty)
        #expect(PlaceSearchModel.quickCategories.map { String(localized: $0) } == ["水族館", "自然", "グルメ", "テーマパーク", "街歩き"])
    }

    /// 検索している途中は「検索中」。終わる前に語が変わったら、遅れて届いた古い結果は映さない
    @Test
    func staleResultsAreIgnored() async {
        let places = RecordingPlaceSearch()
        places.holds = true
        let model = Self.makeModel(places: places)

        model.searchNow("水族館")
        #expect(await AsyncTestSupport.eventually { places.heldCount == 1 })
        #expect(model.phase == .searching)
        model.searchNow("海")
        #expect(await AsyncTestSupport.eventually { places.heldCount == 2 })

        places.releaseFirst()
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(model.phase == .searching)
        places.releaseFirst()
        #expect(await AsyncTestSupport.eventually { Self.names(model.phase) != nil })
        #expect(Self.names(model.phase) == ["鴨川シーワールド", "江の島", "由比ヶ浜海水浴場"])
    }

    /// 見つからなければ「見つかりませんでした」の状態
    @Test
    func noResults() async {
        let model = Self.makeModel()
        model.searchNow("存在しない場所")
        #expect(await AsyncTestSupport.eventually { model.phase == .noResults })
    }

    /// 通信できなければトースト「通信できませんでした」を出し、結果は出さない。cancel ではトーストを出さない
    @Test
    func failureShowsToastButCancellationDoesNot() async {
        let places = RecordingPlaceSearch()
        places.error = AppError(.network)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(places: places, toasts: toasts)

        model.searchNow("水族館")
        #expect(await AsyncTestSupport.eventually { model.phase == .failed })
        #expect(toasts.current?.text == "通信できませんでした")

        toasts.dismiss()
        places.error = AppError(.cancelled, code: .cancelled)
        model.searchNow("海")
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(toasts.current == nil)
        #expect(places.queries == ["水族館", "海"])
    }

    /// 画面が消えたら（`cancel()`）、待っている検索をしない
    @Test
    func cancelStopsPendingSearch() async {
        let places = RecordingPlaceSearch()
        let sleeper = ManualSleeper()
        let model = Self.makeModel(places: places, sleeper: sleeper)

        model.updateQuery("水族館")
        #expect(await AsyncTestSupport.eventually { sleeper.waitingCount == 1 })
        model.cancel()
        sleeper.releaseAll()
        for _ in 0..<100 {
            await Task.yield()
        }
        #expect(places.queries.isEmpty)
        #expect(model.phase == .idle)
    }
}
