//
//  AppRoute.swift
//  Dokogacha
//

import Foundation

/// ホームから開く画面の行き先（03 の §2 の画面遷移）。
///
/// `NavigationStack` の行き先（`navigationDestination(for:)`）と、シートの行き先（`sheet(item:)`）を 1 つの enum にまとめ、
/// どちらで出すかは `presentation` で決める（03 の §1 の「表示形式」）。
/// まだ作っていない画面は仮の画面（`PendingScreenView`）を出し、後のタスクで `MainNavigationView` の行き先を差し替える。
nonisolated enum AppRoute: Hashable, Identifiable, Sendable {
    /// S-03 ルーム作成（プッシュ。タスク 14）
    case createRoom
    /// S-05 招待コードで参加（シート。タスク 15）
    case joinByCode
    /// S-07 ルーム（プッシュ。タスク 19）
    case room(id: String)
    /// S-15 設定（プッシュ。タスク 16）
    case settings

    /// 出し方
    enum Presentation: Equatable, Sendable {
        /// `NavigationStack` に積む
        case push
        /// シートで出す
        case sheet
    }

    /// 出し方（03 の §1 の表のとおり）
    var presentation: Presentation {
        switch self {
        case .createRoom, .room, .settings:
            .push
        case .joinByCode:
            .sheet
        }
    }

    var id: Self {
        self
    }
}
