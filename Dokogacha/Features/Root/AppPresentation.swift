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

    /// 行き先を開く（`AppRoute.presentation` に合わせて積む・シート・フルスクリーンカバーで出す）
    mutating func open(_ route: AppRoute) {
        switch route.presentation {
        case .push:
            path.append(route)
        case .sheet:
            sheet = route
        case .fullScreenCover:
            if sheet == nil {
                fullScreen = route
            } else {
                pendingFullScreen = route
                sheet = nil
            }
        }
    }

    /// シートが閉じ終えた（`sheet(item:onDismiss:)` の `onDismiss`）。待たせていたカバーがあれば出す
    mutating func sheetDismissed() {
        guard let pending = pendingFullScreen else {
            return
        }
        pendingFullScreen = nil
        fullScreen = pending
    }
}
