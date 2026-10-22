//
//  InviteModel.swift
//  Dokogacha
//

import Foundation
import Observation
import UIKit

/// S-04 招待（作成したルームの招待コードと招待リンク）の表示の値と操作。
///
/// 招待コードは `ABC-123` の形で出し、招待リンク（`InviteLink`）と 03 の S-04 の文面を共有シート（`ShareLink`）に渡す。
/// コードの長押しでコピーし、トーストで知らせる。クリップボードへの書き込みは注入する（テストで差し替える）。
@Observable
final class InviteModel {
    /// クリップボードに文字列を書く処理
    typealias Copy = (String) -> Void

    /// 作成したルーム
    let destination: InviteDestination

    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let copy: Copy

    /// - Parameters:
    ///   - destination: 作成したルーム
    ///   - toasts: コピーしたことを知らせるトーストの窓口
    ///   - copy: クリップボードに書く処理（既定は `UIPasteboard.general`）
    init(destination: InviteDestination, toasts: DGToastCenter, copy: @escaping Copy = { UIPasteboard.general.string = $0 }) {
        self.destination = destination
        self.toasts = toasts
        self.copy = copy
    }

    /// ルーム名
    var roomName: String {
        destination.roomName
    }

    /// 招待コードの表示の形（`DK7-29Q`）
    var codeText: String {
        destination.inviteCode.displayText
    }

    /// 招待リンク（`https://dokogacha.app/r/DK729Q`）
    var inviteURL: URL {
        InviteLink.url(for: destination.inviteCode)
    }

    /// 共有シートで送る文面（03 の S-04 の 3。1 行目が誘いの文、2 行目が招待リンク）。
    ///
    /// リンクを文面の中に入れて 1 つの文字列で渡す（URL と文面を分けて渡すと、共有先のアプリによっては文面が落ちるため）
    var shareMessage: String {
        Self.shareMessage(roomName: roomName, inviteCode: destination.inviteCode)
    }

    /// 共有シートで送る文面（S-04 と、S-11 の「招待する」で同じものを使う。03 の S-11「S-04 と同じ共有」）
    /// - Parameters:
    ///   - roomName: ルーム名
    ///   - inviteCode: 招待コード
    static func shareMessage(roomName: String, inviteCode: InviteCode) -> String {
        let invitation = String(localized: "「\(roomName)」で行き先ガチャやろう！行きたい場所を投稿してね")
        return invitation + "\n" + InviteLink.url(for: inviteCode).absoluteString
    }

    /// 1 ルームに参加できる人数（「最大20人まで参加できます」）
    var maxMembers: Int {
        DomainConstants.Limits.maxMembers
    }

    /// 招待コードをコピーする（03 の S-04「コード部分を長押しでコピー」）。
    ///
    /// 表示と同じハイフン付きの形で書く（S-05 の入力はハイフンを無視するので、そのまま貼り付けられる）
    func copyCode() {
        copy(codeText)
        toasts.show("招待コードをコピーしました")
    }
}
