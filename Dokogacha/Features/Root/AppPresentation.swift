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
/// ほかのルームのカバーを出している間に開こうとしたカバー（通知で積み直したカバーの下の S-07 が S-14 を開くなど）も替えずに待たせ、
/// カバーを閉じ終えてから出す（替えると、出しているカバーの演出が止まる。PR #80 の持ち越し）。
/// コードからシートを閉じたとき（`closeSheet()`）は、閉じ終える（`sheetDismissed()`）までカバーを出さずに待たせる
/// （閉じている途中のシートの上にはカバーを出せず、`fullScreen` だけが残って出ないため。PR #72 の持ち越し）。
/// 招待リンクのシート（S-05・S-06）は、招待コードを使い切って開いているので、カバーや通知のために閉じたら、カバーを閉じた後に出し直す。
/// ほかのシート（S-10〜S-12）を出している間に届いた招待リンクも、出しているシートを替えずに、閉じ終えてから出す
/// （編集の途中の S-11・S-12 を消さないため。PR #70 の持ち越し）。
/// 画面の状態を値の型にして、開く順を Unit テストで確かめる。
nonisolated struct AppPresentation: Equatable, Sendable {
    /// 積んでいる行き先
    var path: [AppRoute] = []
    /// シートで出している行き先
    var sheet: AppRoute?
    /// フルスクリーンカバーで出している行き先
    var fullScreen: AppRoute?
    /// シート・フルスクリーンカバーを閉じ終えたら出すフルスクリーンカバー
    private(set) var pendingFullScreen: AppRoute?
    /// シート・フルスクリーンカバーを閉じ終えたら出すシート
    private(set) var pendingSheet: AppRoute?
    /// コードから閉じたシートが、まだ閉じ終えていないか（`closeSheet()` から `sheetDismissed()` まで）
    private(set) var isClosingSheet = false
    /// シートが画面に出たか（`sheetAppeared()` から `sheetDismissed()` まで）。
    /// 出る前に閉じたシートは `onDismiss` が呼ばれないので、閉じ終えるのを待たない
    private(set) var isSheetOnScreen = false

    /// 行き先を開く（`AppRoute.presentation` に合わせて積む・シート・フルスクリーンカバーで出す）
    mutating func open(_ route: AppRoute) {
        switch route.presentation {
        case .push:
            path.append(route)
        case .sheet:
            openSheet(route)
        case .fullScreenCover:
            openCover(route)
        }
    }

    /// シートを開く
    private mutating func openSheet(_ route: AppRoute) {
        if fullScreen != nil || pendingFullScreen != nil {
            // カバーを出している（シートを閉じてカバーを出す途中を含む）。カバーは閉じず、閉じ終えてから出す
            pendingSheet = route
        } else if route.inviteLinkCode != nil, let current = sheet, current != route {
            // ほかのシートを出している間の招待リンク。出しているシートは替えず、閉じ終えてから出す
            pendingSheet = route
        } else if isClosingSheet {
            // コードから閉じたシートが閉じ終える前。閉じ終えてから出す
            pendingSheet = route
        } else {
            sheet = route
        }
    }

    /// フルスクリーンカバーを開く
    private mutating func openCover(_ route: AppRoute) {
        if let roomID = route.gachaRoomID, isCoveringGacha(roomID: roomID) {
            // 同じルームの S-13・S-14 のカバーを出している（出す待ちを含む）。カバーの中で行き来するので替えない
            return
        }
        if fullScreen != nil {
            // ほかのルームのカバーを出している。替えずに、閉じ終えてから出す
            pendingFullScreen = route
        } else if sheet != nil || isClosingSheet {
            // シートを閉じ終えてから出す。招待リンクのシートは、カバーを閉じた後に出し直す
            pendingFullScreen = route
            if let current = sheet, current.inviteLinkCode != nil {
                pendingSheet = current
            }
            closeSheet()
        } else {
            fullScreen = route
            pendingFullScreen = nil
        }
    }

    /// コードからシートを閉じる（参加した・退出した・保存したなど）。閉じ終えるまで、カバーを出さずに待たせる
    mutating func closeSheet() {
        guard sheet != nil else {
            return
        }
        sheet = nil
        if isSheetOnScreen {
            isClosingSheet = true
        } else {
            // まだ画面に出ていない（`onDismiss` が呼ばれない）。待たせていたものをすぐに出す
            showPending()
        }
    }

    /// シートの中身が画面に出た（シートの中身の `onAppear`）
    mutating func sheetAppeared() {
        isSheetOnScreen = true
    }

    /// そのルームの S-13・S-14 のカバーを出しているか（シートを閉じてから出す待ちを含む）
    /// - Parameter roomID: ルームの ID
    private func isCoveringGacha(roomID: String) -> Bool {
        fullScreen?.gachaRoomID == roomID || pendingFullScreen?.gachaRoomID == roomID
    }

    /// シートが閉じ終えた（`sheet(item:onDismiss:)` の `onDismiss`）。待たせていたカバー、無ければシートを出す
    mutating func sheetDismissed() {
        isClosingSheet = false
        isSheetOnScreen = false
        showPending()
    }

    /// フルスクリーンカバーが閉じ終えた（`fullScreenCover(item:onDismiss:)` の `onDismiss`）。待たせていたカバー、無ければシートを出す
    mutating func fullScreenDismissed() {
        showPending()
    }

    /// 待たせていたものを出す（カバーが先。シートはカバーを閉じた後に出す）
    private mutating func showPending() {
        guard sheet == nil, fullScreen == nil else {
            return
        }
        if let pending = pendingFullScreen {
            pendingFullScreen = nil
            fullScreen = pending
        } else if let pending = pendingSheet {
            pendingSheet = nil
            sheet = pending
        }
    }
}
