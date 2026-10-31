//
//  AppRoute.swift
//  Dokogacha
//

import Foundation

/// ホーム・ルームから開く画面の行き先（03 の §2 の画面遷移）。
///
/// `NavigationStack` の行き先（`navigationDestination(for:)`）と、シート（`sheet(item:)`）・フルスクリーンカバー
/// （`fullScreenCover(item:)`）の行き先を 1 つの enum にまとめ、
/// どちらで出すかは `presentation` で決める（03 の §1 の「表示形式」）。
nonisolated enum AppRoute: Hashable, Identifiable, Sendable {
    /// S-03 ルーム作成（プッシュ）
    case createRoom
    /// S-04 招待（プッシュ。作成したルームの上に積み、戻るとルーム。03 の §1）
    case invite(InviteDestination)
    /// S-05 招待コードで参加（シート。タスク 15）
    case joinByCode
    /// 招待リンクで開いた S-05・S-06（シート。タスク 34）。S-05 にコードを入れた状態で始め、すぐに確かめて S-06 を積む。
    /// `via` はコードが届いた道（招待リンク・前回のメンバーへの招待の通知。`room_join` の `via`）
    case joinByInviteLink(InviteCode, via: RoomJoinVia = .link)
    /// S-07 ルーム（プッシュ。タスク 19）
    case room(id: String)
    /// S-15 設定（プッシュ。タスク 16）
    case settings
    /// S-08 候補を追加（ルームから。プッシュ。タスク 20）
    case addCandidate(roomID: String)
    /// S-10 候補の詳細（ルームの候補から。シート。タスク 21）
    case candidateDetail(roomID: String, candidateID: String)
    /// S-11 メンバー一覧（ルームのアバターから。シート。タスク 25）
    case members(roomID: String)
    /// S-04 招待（ルームのアバターの並びの招待の「＋」から。シート。Issue #157）
    case inviteMembers(InviteDestination)
    /// S-12 ルーム設定（ルームのヘッダーの設定から。作成者だけ。シート。タスク 25）
    case roomSettings(roomID: String)
    /// S-13 ガチャ（ルームの「ガチャを回す」から。フルスクリーンカバー。タスク 27）。カプセルを開け終えたら同じカバーの中で S-14 に替わる
    case gacha(roomID: String)
    /// S-14 結果（`drawn`・`closed` のルームを開いたとき・ルームの「行き先きっぷを見る」から。フルスクリーンカバー。タスク 28）
    case result(roomID: String, drawID: String)

    /// 出し方
    enum Presentation: Equatable, Sendable {
        /// `NavigationStack` に積む
        case push
        /// シートで出す
        case sheet
        /// フルスクリーンカバーで出す
        case fullScreenCover
    }

    /// 出し方（03 の §1 の表のとおり）
    var presentation: Presentation {
        switch self {
        case .createRoom, .invite, .room, .settings, .addCandidate:
            .push
        case .joinByCode, .joinByInviteLink, .candidateDetail, .members, .inviteMembers, .roomSettings:
            .sheet
        case .gacha, .result:
            .fullScreenCover
        }
    }

    var id: Self {
        self
    }

    /// S-13・S-14 のカバー（`gacha`・`result`）のルームの ID（ほかの行き先では nil）。
    ///
    /// 同じルームの S-13・S-14 は 1 つのカバー（`GachaFlowView`）の中で行き来するので、
    /// カバーを出している間に同じルームの `gacha`・`result` を開き直さないかを決めるのに使う（`AppPresentation.open`）
    var gachaRoomID: String? {
        switch self {
        case let .gacha(roomID), let .result(roomID, _):
            roomID
        default:
            nil
        }
    }

    /// 招待リンクで開いた S-05・S-06 の招待コード（ほかの行き先では nil）
    var inviteLinkCode: InviteCode? {
        if case let .joinByInviteLink(code, _) = self {
            return code
        }
        return nil
    }

    /// S-05・S-06 を開いた道（`room_join` の `via`。参加の行き先でなければ nil）
    var joinVia: RoomJoinVia? {
        switch self {
        case .joinByCode:
            .code
        case let .joinByInviteLink(_, via):
            via
        default:
            nil
        }
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

/// S-04 招待の行き先（作成したルーム・招待の「＋」を押したルーム）。
///
/// ルーム名は作成に送った名前（前後の空白を取り除いたもの）か、「＋」を押したときのルーム名。S-04 はルームを購読せず、この値だけで表示する
nonisolated struct InviteDestination: Hashable, Sendable {
    /// ルームの ID
    let roomID: String
    /// ルーム名
    let roomName: String
    /// 招待コード
    let inviteCode: InviteCode
}
