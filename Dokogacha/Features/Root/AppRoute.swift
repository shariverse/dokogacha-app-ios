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
    /// S-03 ルーム作成（プッシュ）
    case createRoom
    /// S-04 招待（プッシュ。作成したルームの上に積み、戻るとルーム。03 の §1）
    case invite(InviteDestination)
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
        case .createRoom, .invite, .room, .settings:
            .push
        case .joinByCode:
            .sheet
        }
    }

    var id: Self {
        self
    }
}

extension AppRoute {
    /// ルームを作った後の積み方（03 の §1「S-04 招待：プッシュ（戻るとルーム）」）。
    ///
    /// S-03（とその上）を外し、作ったルームと、その上に S-04 を積む（ホーム → S-07 → S-04）。
    /// S-03 に戻らないのは、作り終えたフォームに戻ると同じルームをもう一度作れてしまうため
    /// - Parameters:
    ///   - created: 作ったルーム
    ///   - path: いまの積み方
    static func pathAfterCreating(_ created: InviteDestination, from path: [Self]) -> [Self] {
        let base = path.lastIndex(of: .createRoom).map { Array(path[..<$0]) } ?? path
        return base + [.room(id: created.roomID), .invite(created)]
    }

    /// 「ルームへ進む」の後の積み方。いちばん上の S-04 を外して、下にあるルームを出す（上が S-04 でなければ変えない）
    /// - Parameter path: いまの積み方
    static func pathOpeningRoom(from path: [Self]) -> [Self] {
        guard case .invite = path.last else {
            return path
        }
        return Array(path.dropLast())
    }
}

/// S-04 招待の行き先（作成したルーム）。
///
/// ルーム名は作成に送った名前（前後の空白を取り除いたもの）。S-04 はルームを購読せず、この値だけで表示する
nonisolated struct InviteDestination: Hashable, Sendable {
    /// ルームの ID
    let roomID: String
    /// ルーム名
    let roomName: String
    /// 招待コード
    let inviteCode: InviteCode
}
