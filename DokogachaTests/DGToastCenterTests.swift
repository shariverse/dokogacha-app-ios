//
//  DGToastCenterTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// トーストの窓口（`DGToastCenter`）が、出しておく時間が過ぎると消えることを確かめる。
///
/// 実際の時間は待たない。待ちの処理を `FakeSleeper` に差し替え、待ちが始まったことを `await` で受け、待ちをテストから終わらせる。
struct DGToastCenterTests {
    /// 呼ばれた待ちを記録し、テストから 1 件ずつ終わらせられる待ちの処理。
    @MainActor
    final class FakeSleeper {
        /// 呼ばれた待ちの時間（呼ばれた順）
        private(set) var durations: [Duration] = []
        /// 終わらせるのを待っている待ち（呼ばれた順。終わらせたものは `nil`）
        private var waiters: [CheckedContinuation<Void, Never>?] = []
        /// 待ちが始まるたびに、その時間を流す
        let started: AsyncStream<Duration>
        /// `started` に流す口
        private let startedContinuation: AsyncStream<Duration>.Continuation

        init() {
            (started, startedContinuation) = AsyncStream.makeStream()
        }

        /// `DGToastCenter` に渡す待ちの処理
        var sleep: DGToastCenter.Sleep {
            { [self] duration in await self.wait(for: duration) }
        }

        /// 待ちを記録し、`finish(_:)` で終わらせるまで止まる
        private func wait(for duration: Duration) async {
            await withCheckedContinuation { continuation in
                durations.append(duration)
                waiters.append(continuation)
                startedContinuation.yield(duration)
            }
        }

        /// `index` 番目（0 始まり）に始まった待ちを終わらせる
        func finish(_ index: Int) {
            waiters[index]?.resume()
            waiters[index] = nil
        }
    }

    /// 待ちには、トークンの表示時間（2.2 秒）を使う
    @Test
    func visibleDurationUsesMotionToken() async throws {
        let sleeper = FakeSleeper()
        let center = DGToastCenter(sleep: sleeper.sleep)
        var started = sleeper.started.makeAsyncIterator()

        center.show(text: "候補に追加しました")
        let duration = try #require(await started.next())
        #expect(duration == .seconds(DGMotion.toastVisibleFor))
        #expect(DGMotion.toastVisibleFor == 2.2)

        let task = center.dismissTask
        sleeper.finish(0)
        await task?.value
        #expect(center.current == nil)
    }

    /// 待ちが終わると今のトーストが消え、次のトーストを出して次の待ちが始まる
    @Test
    func finishingWaitAdvancesToNext() async throws {
        let sleeper = FakeSleeper()
        let center = DGToastCenter(sleep: sleeper.sleep)
        var started = sleeper.started.makeAsyncIterator()

        center.show(text: "候補に追加しました")
        center.show(text: "通信できませんでした")
        _ = try #require(await started.next())
        #expect(center.current?.text == "候補に追加しました")

        sleeper.finish(0)
        _ = try #require(await started.next())
        #expect(center.current?.text == "通信できませんでした")
        #expect(sleeper.durations.count == 2)

        let lastTask = center.dismissTask
        sleeper.finish(1)
        await lastTask?.value
        #expect(center.current == nil)
        #expect(sleeper.durations.count == 2)
    }

    /// `dismiss()` してから次を出したとき、前の待ちが後から終わっても次のトーストを消さない
    @Test
    func cancelledWaitDoesNotDismissNextToast() async throws {
        let sleeper = FakeSleeper()
        let center = DGToastCenter(sleep: sleeper.sleep)
        var started = sleeper.started.makeAsyncIterator()

        center.show(text: "候補に追加しました")
        _ = try #require(await started.next())
        let firstTask = center.dismissTask
        center.dismiss()
        #expect(center.current == nil)
        #expect(firstTask?.isCancelled == true)

        center.show(text: "通信できませんでした")
        _ = try #require(await started.next())
        #expect(center.current?.text == "通信できませんでした")

        sleeper.finish(0)
        await firstTask?.value
        #expect(center.current?.text == "通信できませんでした")

        let secondTask = center.dismissTask
        sleeper.finish(1)
        await secondTask?.value
        #expect(center.current == nil)
    }

    /// 窓口が解放されると、消すまでの待ちを止める
    @Test
    func releasingCenterCancelsWait() async throws {
        let sleeper = FakeSleeper()
        var center: DGToastCenter? = DGToastCenter(sleep: sleeper.sleep)
        weak let released = center
        var started = sleeper.started.makeAsyncIterator()

        center?.show(text: "候補に追加しました")
        _ = try #require(await started.next())
        let task = try #require(center?.dismissTask)
        #expect(!task.isCancelled)

        center = nil
        #expect(released == nil)
        #expect(task.isCancelled)

        sleeper.finish(0)
        await task.value
    }
}
