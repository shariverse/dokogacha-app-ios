//
//  DGToastCenter+Failure.swift
//  Dokogacha
//

import Foundation

extension DGToastCenter {
    /// 操作の失敗を、`AppError` の文言のトーストで知らせる（どの画面もこれで出し、出し方をそろえる）。
    ///
    /// - cancel（`AppError.isCancellation`）と、呼んだ `Task` が cancel 済みのとき（画面を閉じた・操作をやめた）は出さない。
    ///   通信の失敗ではないため
    /// - 同じ文言が続けて並ばないのは `DGToastQueue` が受け持つ（いいねを続けて失敗しても 1 回）
    /// - Parameters:
    ///   - error: 失敗（どんなエラーでもよい。`AppError.wrapping` で文言にする）
    ///   - message: 文言を画面に合わせて替えるとき（既定は `AppError.message`）
    /// - Returns: トーストを出したか
    @discardableResult
    func showFailure(_ error: any Error, message: (AppError) -> String = \.message) -> Bool {
        let appError = AppError.wrapping(error)
        guard !appError.isCancellation, !Task.isCancelled else {
            return false
        }
        show(text: message(appError))
        return true
    }
}
