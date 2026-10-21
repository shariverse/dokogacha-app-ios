//
//  InviteLink.swift
//  Dokogacha
//
//  招待リンク（02 の §2.4「`https://dokogacha.app/r/{招待コード}`（ドメインは仮決め）」）。
//

import Foundation

/// 招待リンクの組み立て。
///
/// ドメインとパスは `DomainConstants.Web`（TypeScript 側の `WEB_DOMAIN`・`INVITE_LINK_PATH_PREFIX`）の値を使う。
/// コードはハイフンなしの保存する形で入れる（Universal Links とランディングページ（タスク 34）が `/r/{code}` で受ける形）。
nonisolated enum InviteLink {
    /// 招待リンクの URL
    /// - Parameter code: 招待コード
    static func url(for code: InviteCode) -> URL {
        var components = URLComponents()
        components.scheme = DomainConstants.Web.scheme
        components.host = DomainConstants.Web.domain
        components.path = DomainConstants.Web.inviteLinkPathPrefix + code.value
        // スキーム・ホスト・英数字だけのパスなので、組み立てに失敗することはない
        guard let url = components.url else {
            preconditionFailure("招待リンクを組み立てられません: \(code.value)")
        }
        return url
    }
}
