//
//  PushDestination.swift
//  Dokogacha
//
//  プッシュ通知（02 の §8 F-60）のペイロードから、開く画面と前面での出し方を決める純粋な関数。
//  ペイロードの形は backend の `functions/src/notifications/logic.ts`（`pushData`）が決める。片方を変えたら両方を変える。
//

import Foundation

/// 通知を開いたときの行き先（05 の §7「通知のペイロードに roomId と遷移先（room / result）を入れる」）。
///
/// ペイロード（FCM の `data`。APNs の `userInfo` の最上位に入る）の `roomId`・`target`・`type`・`drawId` から作る。
/// `roomId` が無い・ドキュメントの ID として正しくない通知は開かない（`init` が nil）
nonisolated struct PushDestination: Equatable, Sendable {
    /// 通知の種類（ペイロードの `type`）。知らない値は nil（開き方は `target` だけで決める）
    enum Kind: String, Sendable {
        /// ガチャが解禁された
        case unlocked
        /// 行き先が決まった
        case drawn
        /// 引き直しが提案された
        case rerollProposed
        /// 前回のメンバーとして招待された（`inviteLastMembers`）
        case invited
        /// その日に候補が増えた（まとめ通知 `notifyNewCandidates`）
        case newCandidates
    }

    /// 開く画面（ペイロードの `target`）
    enum Target: String, Sendable {
        /// S-07 ルーム
        case room
        /// S-14 結果（ルームが `drawn`・`closed` なら S-07 を開くと自動で出る）
        case result
        /// S-06 参加確認（前回のメンバーへの招待。`inviteCode` で招待リンクと同じ道で開く。招待された人はまだメンバーでなく、ルームを読めない）
        case join
    }

    /// 通知の種類
    let kind: Kind?
    /// ルームの ID
    let roomID: String
    /// 開く画面。知らない値・無いときはルーム
    let target: Target
    /// 結果を開くときの抽選の ID（無ければ nil）
    let drawID: String?
    /// 参加確認を開くときの招待コード（`target` が `join` のときだけ。ほかは nil）
    let inviteCode: InviteCode?

    /// 値を指定して作る（テスト・UI テストの起動引数）
    init(kind: Kind?, roomID: String, target: Target, drawID: String? = nil, inviteCode: InviteCode? = nil) {
        self.kind = kind
        self.roomID = roomID
        self.target = target
        self.drawID = drawID
        self.inviteCode = inviteCode
    }

    /// 通知のペイロードから作る。`roomId` が無い・正しくない、参加確認を開くのに招待コードが無い・正しくなければ nil
    /// - Parameter userInfo: 通知の `userInfo`（FCM の `data` の値は文字列）
    init?(userInfo: [AnyHashable: Any]) {
        guard let roomID = userInfo["roomId"] as? String, FirestorePath.isValidDocumentID(roomID) else {
            return nil
        }
        let target = (userInfo["target"] as? String).flatMap(Target.init(rawValue:)) ?? .room
        let inviteCode = (userInfo["inviteCode"] as? String).flatMap { InviteCode($0) }
        // 招待された人はメンバーでないので、コードが読めなければルームも開けない（開かない）
        if target == .join, inviteCode == nil {
            return nil
        }
        self.roomID = roomID
        self.target = target
        self.inviteCode = target == .join ? inviteCode : nil
        kind = (userInfo["type"] as? String).flatMap(Kind.init(rawValue:))
        drawID = (userInfo["drawId"] as? String).flatMap { FirestorePath.isValidDocumentID($0) ? $0 : nil }
    }
}

/// いま前面に出しているルームの画面（前面で通知が届いたときに、出すかを決めるのに使う）
nonisolated struct VisibleRoomScreen: Equatable, Sendable {
    /// ルームの ID
    let roomID: String
    /// S-13・S-14 のカバーを出しているか（false なら S-07 を出している）
    let isGachaCover: Bool
}

/// アプリが前面にいるときに届いた通知を、バナーで出すか。
///
/// 通知の中身がもう画面に出ているときは出さない（そのルームの画面は購読で変わる）:
/// - そのルームの S-13・S-14 を出している → 出さない（抽選の演出の上にバナーを重ねない。引き直しの投票も S-14 で見える）
/// - そのルームの S-07 を出している → 解禁・抽選結果は出さない（S-07 が解禁の表示に替わる・ガチャの演出を自動で再生する F-41）。
///   引き直しの提案は S-07 に出ないので出す
/// - ほかの画面・ほかのルーム → 出す（バナー・通知センター・音）
nonisolated enum PushForegroundPolicy {
    /// バナーで出すか
    /// - Parameters:
    ///   - destination: 届いた通知の行き先（読めない通知は nil。出す）
    ///   - visible: いま出しているルームの画面（ルームの画面でなければ nil）
    static func showsBanner(for destination: PushDestination?, visible: VisibleRoomScreen?) -> Bool {
        guard let destination, let visible, visible.roomID == destination.roomID else {
            return true
        }
        if visible.isGachaCover {
            return false
        }
        return destination.kind == .rerollProposed
    }
}
