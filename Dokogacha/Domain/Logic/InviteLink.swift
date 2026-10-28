//
//  InviteLink.swift
//  Dokogacha
//
//  招待リンク（02 の §2.4「`https://dokogacha.app/r/{招待コード}`（ドメインは仮決め）」）。
//

import Foundation

/// 招待リンクの組み立てと読み取り。
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

    /// Universal Links で開かれた URL から招待コードを取り出す（`DeepLinkRouter` が使う。05 の §7）。
    ///
    /// 招待リンク（`https://dokogacha.app/r/{招待コード}`）の形でなければ nil を返し、アプリは何もしない。
    /// - スキームは `https` だけ（Universal Links は https でしか届かない）。ホストは大文字・小文字を区別せず `DomainConstants.Web.domain` と比べる。
    ///   ユーザー名・パスワード・ポートが付いたものは受けない
    /// - パスは `/r/` で始まり、その後ろが 1 つの区切りだけ（末尾のスラッシュは 1 つまで許す）。`/R/` は受けない
    ///   （AASA の `components` は大文字・小文字を区別するので、アプリに届くのは `/r/` だけ）
    /// - コードの正規化と検証は `InviteCode` に任せる（小文字・ハイフン付きでも受け、`0 O 1 I` を含む・6 文字でないものは nil）
    /// - クエリとフラグメントは見ない（共有先のアプリが付ける計測用のパラメータで読めなくならないように）
    /// - Parameter url: 開かれた URL
    /// - Returns: 招待コード。招待リンクでなければ nil
    static func inviteCode(from url: URL) -> InviteCode? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == DomainConstants.Web.scheme,
              components.host?.lowercased() == DomainConstants.Web.domain,
              components.user == nil, components.password == nil, components.port == nil else {
            return nil
        }
        // `path` はパーセントエンコードを戻した形（`%2D` などで書かれたハイフンも、ほかの文字と同じに扱う）
        let path = components.path
        guard path.hasPrefix(DomainConstants.Web.inviteLinkPathPrefix) else {
            return nil
        }
        var rest = path.dropFirst(DomainConstants.Web.inviteLinkPathPrefix.count)
        if rest.hasSuffix("/") {
            rest = rest.dropLast()
        }
        guard !rest.isEmpty, !rest.contains("/") else {
            return nil
        }
        return InviteCode(String(rest))
    }
}
