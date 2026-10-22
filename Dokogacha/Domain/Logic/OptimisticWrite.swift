//
//  OptimisticWrite.swift
//  Dokogacha
//
//  直接の書き込み（いいね F-20・自分の準備OK F-30）の楽観的更新で、送っている途中の値をいつ捨てるか（確定するか）の決まり。
//

import Foundation

/// 送っている途中の直接の書き込み 1 つ分（楽観的に表示している値と、確定までの進み具合）。
///
/// 直接の書き込みは送った時点で返り、サーバーの値は購読で後から届く（`RoomRepository`）。購読の値は書き込みの前の古い値のことも、
/// ほかの人の変化（別の候補へのいいね・ほかのメンバーの準備OK）だけを含むこともあるので、
/// **届いた値の「自分の分」が楽観的な値と一致したときだけ確定する**（次に届いた値で無条件に確定すると、古い値で一瞬戻ってちらつく）。
///
/// - 送り終える前に一致した値が届いたら、書き込みはもう反映されている（Firestore はキャッシュに書いた時点で流す）ので、
///   送り終えた時点で確定する。その後にサーバーに拒まれて値が戻っても、確定した後なので購読の値（戻った値）をそのまま映す
/// - 送り終えた後は、一致した値が届いた時点で確定する
/// - 一致する値が届かないまま拒まれる場合（ルームが `drawn`・`closed` になった・候補が消えた・メンバーでなくなった）は、
///   どれも購読で分かる変化なので、持ち主（`RoomModel`）がその時点で捨てる
nonisolated struct OptimisticWrite<Value: Equatable & Sendable>: Equatable, Sendable {
    /// 楽観的に表示している値（送った値）
    let value: Value
    /// 送り終えたか
    private(set) var isSent = false
    /// 送っている途中に、購読で一致した値が届いたか
    private(set) var wasReflected = false

    /// - Parameter value: 楽観的に表示する値（送る値）
    init(_ value: Value) {
        self.value = value
    }

    /// 購読で「自分の分」の値が届いた。確定したら true（持ち主は捨てて、購読の値を映す）
    /// - Parameter current: 届いた値の自分の分（候補に自分のいいねがあるか・自分の準備OK）
    mutating func received(_ current: Value) -> Bool {
        guard current == value else {
            return false
        }
        if isSent {
            return true
        }
        wasReflected = true
        return false
    }

    /// 送り終えた。確定したら true（送っている途中に一致した値が届いていた・今の購読の値がもう一致している）
    /// - Parameter current: 今の購読の値の自分の分（まだ届いていなければ nil）
    mutating func sent(current: Value?) -> Bool {
        if wasReflected || current == value {
            return true
        }
        isSent = true
        return false
    }
}
