//
//  AppPresentation+Notification.swift
//  Dokogacha
//

import Foundation

extension AppPresentation {
    /// 通知を開いたときに、そのルームの画面を出す（02 の §8「通知をタップすると該当ルーム（結果があれば結果画面）を開く」）。
    ///
    /// - そのルームの S-07 を出していなければ、ホームの上にそのルームだけを積み直す（`[.room]`）。
    ///   ルームが `drawn`・`closed` なら、S-07 が開いたときに S-14 を自動で出す（`DrawReplay.resultDrawID`。いまの抽選で出す）
    /// - もうそのルームの S-07 を出していて、結果を開く通知なら、S-14 を開く（S-07 の自動の表示は開いたときだけなので）
    /// - シートは閉じる。S-13・S-14 のカバーは閉じない（S-13 は演出中に閉じられない取り決め。`AppPresentation` の説明）。
    ///   ほかのルームのカバーを出していたら、カバーの下で積み直すので、カバーを閉じるとそのルームが出る
    /// - Parameter destination: 通知の行き先
    mutating func openNotification(_ destination: PushDestination) {
        let room = AppRoute.room(id: destination.roomID)
        let isShowingRoom = path.last == room
        if !isShowingRoom {
            path = [room]
        }
        if destination.target == .result, isShowingRoom, let drawID = destination.drawID {
            // シートが出ていれば、シートを閉じてからカバーを出す。同じルームのカバーを出していれば替えない（`open`）
            open(.result(roomID: destination.roomID, drawID: drawID))
        } else if fullScreen == nil, pendingFullScreen == nil {
            sheet = nil
        }
    }

    /// いま前面に出しているルームの画面（前面で届いた通知を出すかを決める。`PushForegroundPolicy`）。
    ///
    /// S-13・S-14 のカバーを出していればそのルーム、シートを出していなければ積みのいちばん上の S-07。それ以外は nil
    var visibleRoomScreen: VisibleRoomScreen? {
        if let roomID = fullScreen?.gachaRoomID {
            return VisibleRoomScreen(roomID: roomID, isGachaCover: true)
        }
        guard sheet == nil, case let .room(roomID) = path.last else {
            return nil
        }
        return VisibleRoomScreen(roomID: roomID, isGachaCover: false)
    }
}
