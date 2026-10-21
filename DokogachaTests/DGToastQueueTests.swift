//
//  DGToastQueueTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// トーストの表示の順番（`DGToastQueue`）と、窓口（`DGToastCenter`）の出し入れを確かめる。
///
/// 時間で消える動きは `DGToastCenterTests` で、待ちを差し替えて確かめる。
struct DGToastQueueTests {
    /// テスト用のトースト（ID を固定して、同じ文言でも区別できるようにする）
    static func message(_ text: String, id: Int) -> DGToastMessage {
        DGToastMessage(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id)) ?? UUID(), text: text)
    }

    /// 何も出ていなければ、足したものをすぐに出す
    @Test
    func firstMessageIsShownImmediately() {
        var queue = DGToastQueue()
        let added = Self.message("候補に追加しました", id: 1)
        let shown = queue.enqueue(added)
        #expect(shown)
        #expect(queue.current == added)
        #expect(queue.pending.isEmpty)
    }

    /// 出している間に来たものは後ろに並び、消すと順に出る
    @Test
    func messagesAreShownInOrder() {
        var queue = DGToastQueue()
        let first = Self.message("候補に追加しました", id: 1)
        let second = Self.message("通信できませんでした", id: 2)
        let third = Self.message("ガチャを強制解禁しました", id: 3)
        queue.enqueue(first)
        let secondShown = queue.enqueue(second)
        let thirdShown = queue.enqueue(third)
        #expect(!secondShown)
        #expect(!thirdShown)
        #expect(queue.current == first)
        #expect(queue.pending == [second, third])

        let next = queue.advance()
        #expect(next == second)
        let last = queue.advance()
        #expect(last == third)
        let end = queue.advance()
        #expect(end == nil)
        #expect(queue.current == nil)
    }

    /// 出しているものと同じ文言は足さない
    @Test
    func duplicateOfCurrentIsIgnored() {
        var queue = DGToastQueue()
        queue.enqueue(Self.message("通信できませんでした", id: 1))
        let shown = queue.enqueue(Self.message("通信できませんでした", id: 2))
        #expect(!shown)
        #expect(queue.pending.isEmpty)
    }

    /// 最後に待っているものと同じ文言は足さないが、間に別の文言があれば足す
    @Test
    func duplicateOfLastPendingIsIgnored() {
        var queue = DGToastQueue()
        queue.enqueue(Self.message("候補に追加しました", id: 1))
        queue.enqueue(Self.message("通信できませんでした", id: 2))
        queue.enqueue(Self.message("通信できませんでした", id: 3))
        #expect(queue.pending.map(\.text) == ["通信できませんでした"])

        queue.enqueue(Self.message("候補に追加しました", id: 4))
        #expect(queue.pending.map(\.text) == ["通信できませんでした", "候補に追加しました"])
    }

    /// 消えた後なら、同じ文言をもう一度出せる
    @Test
    func sameTextCanBeShownAgainAfterDismissal() {
        var queue = DGToastQueue()
        queue.enqueue(Self.message("通信できませんでした", id: 1))
        queue.advance()
        let shown = queue.enqueue(Self.message("通信できませんでした", id: 2))
        #expect(shown)
    }

    /// 窓口は 1 件ずつ出し、`dismiss()` で次に進む
    @Test
    func centerShowsOneAtATime() {
        let center = DGToastCenter(visibleFor: .seconds(3600))
        #expect(center.current == nil)
        center.show(text: "候補に追加しました")
        center.show(text: "通信できませんでした")
        #expect(center.current?.text == "候補に追加しました")

        center.dismiss()
        #expect(center.current?.text == "通信できませんでした")
        center.dismiss()
        #expect(center.current == nil)
    }
}
