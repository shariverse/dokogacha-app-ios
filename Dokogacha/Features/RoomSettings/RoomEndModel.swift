//
//  RoomEndModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-12 ルーム設定の「ルームを終了する」（03 の S-12・Discussion #155）の状態と操作。`RoomSettingsModel.ending` として持つ。
///
/// 作成者が押すと確認のダイアログを出し、「終了する」で Callable の `closeRoom` を意図 `endEarly` で呼ぶ
/// （S-14 の「この行き先で決定」（`ResultCloseModel`）と同じ作り）。
/// 送っている途中は二重に送らない（ボタンを押せなくし、シートを閉じさせない）。成功したら `onEnded` を呼び、画面がシートを閉じてホームに戻る。
/// 失敗したら `AppError` の文言のトーストを出し、画面はそのまま（もう一度押せる）。確認の間にほかの人がガチャを回して `drawn` になっていたら、
/// サーバーは `room-already-decided`（「このルームはもう行き先が決まっています」）で断るので、そのトーストを出す（ルームは終了しない）。
/// もう終了していたとき（二度押し）はサーバーが成功を返すので、そのままホームに戻る。
/// 画面が消えても送ったものは止めない（作成者が決めたので送り切る。「この行き先で決定」と同じ）。
@Observable
final class RoomEndModel {
    /// ルームの ID
    let roomID: String
    /// 確認のダイアログを出しているか
    var isConfirming = false
    /// `closeRoom` を送っている途中か（二重に送らない・ボタンを押せなくする）
    private(set) var isEnding = false

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// 終了できたら `room_close`（`early` が true）を送る窓口
    @ObservationIgnored private let analytics: any AnalyticsService
    /// 確認のダイアログから始めた終了（二重に始めないために持つ）
    @ObservationIgnored private var endTask: Task<Void, Never>?

    /// 送っている途中か、送り始める Task が残っているか（シートを閉じさせない）
    var isBusy: Bool {
        isEnding || endTask != nil
    }

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - functions: `closeRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 失敗を出すトーストの窓口（シートの中に重ねるもの）
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

    /// 「ルームを終了する」が押された。確認のダイアログを出す（送っている途中なら出さない）
    func endTapped() {
        guard !isBusy else {
            return
        }
        isConfirming = true
    }

    /// 確認のダイアログで「終了する」が押された。終了を始める（始めた Task が残っている間は受け付けない）
    /// - Parameter onEnded: 終了できたときの処理（シートを閉じてホームに戻る）
    func confirmTapped(onEnded: @escaping () -> Void) {
        guard endTask == nil else {
            return
        }
        endTask = Task { [weak self] in
            let ended = await self?.end() ?? false
            self?.endTask = nil
            if ended {
                onEnded()
            }
        }
    }

    /// ルームを途中で終了する（`closeRoom` の `endEarly`）。送っている途中なら何もしない。
    /// - Returns: 終了できたか（失敗したら `AppError` の文言のトーストを出して false。cancel ならトーストを出さない）
    func end() async -> Bool {
        guard !isEnding else {
            return false
        }
        isEnding = true
        defer { isEnding = false }
        do {
            try await functions.closeRoom(CloseRoomRequest(roomId: roomID, reason: .endEarly))
            analytics.log(.roomClose(auto: false, early: true))
            return true
        } catch {
            toasts.showFailure(error)
            return false
        }
    }
}
