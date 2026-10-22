//
//  AppPresentation.swift
//  Dokogacha
//

import Foundation

/// `MainNavigationView` が出している行き先（積み・シート・フルスクリーンカバー）と、その開き方の決まり。
///
/// シート（S-09〜S-12）を出したままフルスクリーンカバー（S-13・S-14）を出そうとすると、根元からはシートの上にカバーを重ねられず、
/// カバーが出ないまま捨てられる（ほかの人が回したときの自動再生が消える。PR #67 の持ち越し）。
/// そのため、シートが出ているときは先にシートを閉じ、閉じ終えた（`sheetDismissed()`）ところでカバーを出す。
/// 逆に、カバーを出している間（S-13 の演出中を含む）にシートを開こうとしたとき（招待リンクが届いたときなど）は、カバーを閉じずに待たせ、
/// ユーザーがカバーを閉じ終えた（`fullScreenDismissed()`）ところでシートを出す。S-13 は演出中に閉じられない取り決めで、
/// 閉じると本人が結果を見ないまま演出が止まり、見た印（`markSeen`）も付かないため。
/// 同じルームの S-13・S-14 のカバーを出している（出す待ちを含む）間は、同じルームの `gacha`・`result` を開いても値を替えない。
/// カバーの中の S-13 で回す・ほかの人が回すと、カバーの下の S-07 が S-13 を開こうとするが、値が替わると SwiftUI がカバーを閉じて出し直し、
/// 回している途中の演出が止まって新しい S-13 が同じ抽選をもう一度再生するため（新しい抽選はカバーの中の `GachaFlowView` が見せる）。
/// 画面の状態を値の型にして、開く順を Unit テストで確かめる。
nonisolated struct AppPresentation: Equatable, Sendable {
    /// 積んでいる行き先
    var path: [AppRoute] = []
    /// シートで出している行き先
    var sheet: AppRoute?
    /// フルスクリーンカバーで出している行き先
    var fullScreen: AppRoute?
    /// シートを閉じ終えたら出すフルスクリーンカバー
    private(set) var pendingFullScreen: AppRoute?
    /// フルスクリーンカバーを閉じ終えたら出すシート
    private(set) var pendingSheet: AppRoute?

    /// 行き先を開く（`AppRoute.presentation` に合わせて積む・シート・フルスクリーンカバーで出す）
    mutating func open(_ route: AppRoute) {
        switch route.presentation {
        case .push:
            path.append(route)
        case .sheet:
            if fullScreen == nil, pendingFullScreen == nil {
                sheet = route
            } else {
                // カバーを出している（シートを閉じてカバーを出す途中を含む）。カバーは閉じず、閉じ終えてから出す
                pendingSheet = route
            }
        case .fullScreenCover:
            if let roomID = route.gachaRoomID, isCoveringGacha(roomID: roomID) {
                // 同じルームの S-13・S-14 のカバーを出している（出す待ちを含む）。カバーの中で行き来するので替えない
                return
            }
            if sheet == nil {
                fullScreen = route
            } else {
                pendingFullScreen = route
                sheet = nil
            }
        }
    }

    /// そのルームの S-13・S-14 のカバーを出しているか（シートを閉じてから出す待ちを含む）
    /// - Parameter roomID: ルームの ID
    private func isCoveringGacha(roomID: String) -> Bool {
        fullScreen?.gachaRoomID == roomID || pendingFullScreen?.gachaRoomID == roomID
    }

    /// シートが閉じ終えた（`sheet(item:onDismiss:)` の `onDismiss`）。待たせていたカバーがあれば出す
    mutating func sheetDismissed() {
        guard let pending = pendingFullScreen else {
            return
        }
        pendingFullScreen = nil
        fullScreen = pending
    }

    /// フルスクリーンカバーが閉じ終えた（`fullScreenCover(item:onDismiss:)` の `onDismiss`）。待たせていたシートがあれば出す
    mutating func fullScreenDismissed() {
        guard let pending = pendingSheet else {
            return
        }
        pendingSheet = nil
        sheet = pending
    }
}
