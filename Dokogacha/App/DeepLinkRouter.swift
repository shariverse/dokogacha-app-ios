//
//  DeepLinkRouter.swift
//  Dokogacha
//

import Foundation
import Observation

/// Universal Links（招待リンク `https://dokogacha.app/r/{招待コード}`）で開かれたときの行き先を覚えておく窓口（02 の §2.4・05 の §7）。
///
/// アプリの根元（`DokoGachaApp` の `onOpenURL`・`onContinueUserActivity`）が `handle` に URL を渡し、
/// 招待リンクなら招待コードを `pendingInviteCode` に入れる。表示名を登録した後の画面（`MainNavigationView`）が
/// それを見て `takePendingInviteCode()` で受け取り、S-06 参加確認をそのコードで開く。
/// 表示名を登録する前（S-01）に届いたときは、ホームが出るまで覚えておき、登録した後に開く。
///
/// URL からコードを取り出す判定は `InviteLink.inviteCode(from:)`（純粋な関数）に任せ、ここは覚えておくことだけをする。
/// `AppDelegate` が 1 つ持つ（後のタスクで、通知を開いたときの行き先もここに足す）。
@Observable
final class DeepLinkRouter {
    /// まだ開いていない招待コード（招待リンクで開かれ、S-06 をまだ出していないもの）
    private(set) var pendingInviteCode: InviteCode?

    /// 開かれた URL を受け取る。招待リンクなら招待コードを覚える（前に覚えていたコードは新しいもので置き換える）。
    ///
    /// 招待リンクでない URL（ホスト・パスが違う・コードが正しくない）は無視し、覚えていたコードも消さない
    /// - Parameter url: 開かれた URL
    /// - Returns: 招待リンクとして受け取ったら true
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let code = InviteLink.inviteCode(from: url) else {
            return false
        }
        pendingInviteCode = code
        return true
    }

    /// Universal Links の `NSUserActivity` を受け取る（`NSUserActivityTypeBrowsingWeb` の `webpageURL`）。ほかの種類は無視する
    /// - Parameter activity: 続きから開く操作
    /// - Returns: 招待リンクとして受け取ったら true
    @discardableResult
    func handle(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL else {
            return false
        }
        return handle(url)
    }

    /// 覚えている招待コードを受け取って消す（同じコードで S-06 を 2 回開かないように）
    /// - Returns: 覚えていた招待コード。無ければ nil
    func takePendingInviteCode() -> InviteCode? {
        defer { pendingInviteCode = nil }
        return pendingInviteCode
    }
}
