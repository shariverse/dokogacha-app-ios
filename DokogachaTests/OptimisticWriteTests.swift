//
//  OptimisticWriteTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 楽観的更新の確定の決まり（`OptimisticWrite`）。届いた値の自分の分が一致したときだけ確定し、古い値・関係の無い値では確定しないこと
struct OptimisticWriteTests {
    /// 送り終えた後は、一致しない値（古い値）が何度届いても確定せず、一致した値が届いたときに確定する
    @Test
    func confirmsOnlyWhenMatchingValueArrivesAfterSending() {
        var write = OptimisticWrite(true)
        let result1 = write.sent(current: false)
        #expect(!result1)
        #expect(write.isSent)
        let result2 = write.received(false)
        #expect(!result2)
        let result3 = write.received(false)
        #expect(!result3)
        let result4 = write.received(true)
        #expect(result4)
    }

    /// 送り終えた時点で今の値がもう一致していれば、その場で確定する
    @Test
    func confirmsAtSendingWhenCurrentValueAlreadyMatches() {
        var write = OptimisticWrite(false)
        let result5 = write.sent(current: false)
        #expect(result5)
    }

    /// 送っている途中に一致した値が届いたら、送り終えた時点で確定する（その後に拒まれて値が戻っても、戻った値を映せる）
    @Test
    func confirmsAtSendingWhenMatchingValueArrivedWhileSending() {
        var write = OptimisticWrite(true)
        let result6 = write.received(true)
        #expect(!result6)
        #expect(write.wasReflected)
        // 拒まれて元の値に戻ったものが届いても、送っている途中は確定しない
        let result7 = write.received(false)
        #expect(!result7)
        let result8 = write.sent(current: false)
        #expect(result8)
    }

    /// 送っている途中は、一致した値が届いても確定しない（送り終えるまで楽観的な値を持つ）
    @Test
    func doesNotConfirmWhileSending() {
        var write = OptimisticWrite(true)
        let result9 = write.received(true)
        #expect(!result9)
        #expect(!write.isSent)
    }

    /// まだ購読の値が無いとき（nil）は、送り終えても確定しない
    @Test
    func doesNotConfirmWithoutCurrentValue() {
        var write = OptimisticWrite(true)
        let result10 = write.sent(current: nil)
        #expect(!result10)
        let result11 = write.received(true)
        #expect(result11)
    }
}
