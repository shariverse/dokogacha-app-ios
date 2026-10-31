//
//  ResultCloseModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-14 結果の「この行き先で決定」（02 の §6.3・§6.5 F-44）の状態と操作。`ResultModel.closing` として持つ。
///
/// 作成者が押すと確認のダイアログを出し、「決定する」で Callable の `closeRoom` を呼ぶ。
/// 送っている途中は二重に送らない（ボタンを押せなくする）。成功したら `onClosed` を呼び、画面がカバーを閉じてホームに戻る。
/// 失敗したら `AppError` の文言のトーストを出し、画面はそのまま（もう一度押せる）。
/// もう終了していたとき（自動の終了と重なった・二度押し）はサーバーが成功を返すので、そのままホームに戻る。
/// 画面が消えても送ったものは止めない（作成者が決めたので送り切る。強制解禁と同じ）。
@Observable
final class ResultCloseModel {
    /// ルームの ID
    let roomID: String
    /// 確認のダイアログを出しているか
    var isConfirming = false
    /// `closeRoom` を送っている途中か（二重に送らない・ボタンを押せなくする）
    private(set) var isClosing = false

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// 終了できたら `room_close` を送る窓口
    @ObservationIgnored private let analytics: any AnalyticsService
    /// 確認のダイアログから始めた終了（二重に始めないために持つ）
    @ObservationIgnored private var closeTask: Task<Void, Never>?

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - functions: `closeRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 失敗を出すトーストの窓口（フルスクリーンカバーの中に重ねるもの）
    ///   - analytics: Analytics のイベント（05 の §9）を送る窓口
    init(
        roomID: String,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        analytics: any AnalyticsService = DisabledAnalyticsService()
    ) {
        self.roomID = roomID
        self.functions = functions
        self.toasts = toasts
        self.analytics = analytics
    }

    /// 「この行き先で決定」が押された。確認のダイアログを出す（送っている途中なら出さない）
    func decideTapped() {
        guard !isClosing else {
            return
        }
        isConfirming = true
    }

    /// 確認のダイアログで「決定する」が押された。終了を始める（始めた Task が残っている間は受け付けない）
    /// - Parameter onClosed: 終了できたときの処理（カバーを閉じてホームに戻る）
    func confirmTapped(onClosed: @escaping () -> Void) {
        guard closeTask == nil else {
            return
        }
        closeTask = Task { [weak self] in
            let closed = await self?.close() ?? false
            self?.closeTask = nil
            if closed {
                onClosed()
            }
        }
    }

    /// ルームを終了する（`closeRoom`）。送っている途中なら何もしない。
    /// - Returns: 終了できたか（失敗したら `AppError` の文言のトーストを出して false。cancel ならトーストを出さない）
    func close() async -> Bool {
        guard !isClosing else {
            return false
        }
        isClosing = true
        defer { isClosing = false }
        do {
            try await functions.closeRoom(CloseRoomRequest(roomId: roomID, reason: .decide))
            // 自動の終了（抽選の 7 日後）は Functions が行い、アプリからは分からないので、ここで送るのは作成者が決めたときだけ
            analytics.log(.roomClose(auto: false, early: false))
            return true
        } catch {
            toasts.showFailure(error)
            return false
        }
    }
}
