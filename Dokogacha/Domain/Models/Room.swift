//
//  Room.swift
//  Dokogacha
//

import Foundation

/// ルーム（`rooms/{roomId}`。05 の §3）。
///
/// 書き込みは Callable Functions だけが行う（05 の §4）。アプリは購読して表示に使う。
/// プロパティ名は Firestore のフィールド名と同じ。日時は `Date` で、`Timestamp` との変換はデータ層で行う。
nonisolated struct Room: Codable, Sendable, Equatable {
    /// ルーム名（1〜20 文字）
    var name: String
    /// 作成者の uid
    var ownerId: String
    /// 招待コード（6 文字。ハイフンなしで保存する。表示は `InviteCode.displayText`）
    var inviteCode: String
    /// 状態
    var status: RoomStatus
    /// 作成時に決めた設定（F-02・F-03）
    var settings: RoomSettings
    /// 作成者が強制解禁したか（F-32）
    var forcedUnlock: Bool
    /// メンバーの uid（クエリ用。最大 20）
    var memberIds: [String]
    /// メンバー数（Functions が更新）
    var memberCount: Int
    /// 準備OKの人数（Functions が更新）
    var readyCount: Int
    /// 候補の数（Functions が更新）
    var candidateCount: Int
    /// 広告非表示の購入者（メンバーにいれば最初に参加した人。いなければ nil）
    var adFreeSponsor: AdFreeSponsor?
    /// 最新の抽選の ID（`draws/{drawId}`）
    var currentDrawId: String?
    /// 当選した候補の ID
    var winnerCandidateId: String?
    /// 引き直しで外れた候補の ID
    var excludedCandidateIds: [String]
    /// 引き直し（F-43）の状態
    var reroll: RerollState
    /// 作成日時
    var createdAt: Date
    /// 抽選の日時（抽選前は nil）
    var drawnAt: Date?
    /// 終了の日時（終了前は nil）
    var closedAt: Date?
}

/// ルームの状態（02 の §2.1）。`rawValue` は Firestore の `status` の値。
nonisolated enum RoomStatus: String, CaseIterable, Codable, Sendable {
    /// 候補募集中
    case open
    /// ガチャ解禁！
    case unlocked
    /// 行き先決定
    case drawn
    /// 終了
    case closed
}

/// ルームの設定（`rooms.settings`。F-02・F-03）。
nonisolated struct RoomSettings: Codable, Sendable, Equatable {
    /// 1 人あたりの投稿数（1〜10）
    var postLimit: Int
    /// 解禁の条件
    var unlockRule: UnlockRule
    /// 締切日時（`unlockRule` が `deadline` のときだけ。それ以外は nil）
    var deadlineAt: Date?
    /// いいねの効き方
    var likeMode: LikeMode
}

/// 解禁の条件（F-31）。`rawValue` は Firestore の `settings.unlockRule` の値。
nonisolated enum UnlockRule: String, CaseIterable, Codable, Sendable {
    /// 全員OK
    case all
    /// 過半数OK
    case majority
    /// 締切日時
    case deadline
}

/// いいねの効き方（F-21）。`rawValue` は Firestore の `settings.likeMode` の値。
nonisolated enum LikeMode: String, CaseIterable, Codable, Sendable {
    /// 共感ブースト（いいねが多いほど出やすい）
    case boost
    /// みんな平等（どの候補も同じ確率）
    case equal
}

/// ルームの広告をなくしている購入者（`rooms.adFreeSponsor`。F-51）。
nonisolated struct AdFreeSponsor: Codable, Sendable, Equatable {
    /// 購入者の uid
    var uid: String
    /// 購入者の表示名（「◯◯さんのおかげで、このルームは広告なし」に出す）
    var displayName: String
}

/// 引き直し（F-43）の状態（`rooms.reroll`）。
///
/// 05 の §3 では引き直しを別のコレクションにせず、ルームの中の map に持つ（ルームにつき 1 回までのため）。
nonisolated struct RerollState: Codable, Sendable, Equatable {
    /// 引き直しの権利を使ったか（提案した時点で使ったことになる）
    var used: Bool
    /// 提案した人の uid（提案前は nil）
    var proposedBy: String?
    /// 提案した日時（提案前は nil）
    var proposedAt: Date?
    /// 賛成した人の uid
    var votesFor: [String]
    /// 反対した人の uid
    var votesAgainst: [String]
    /// 投票の状態
    var status: RerollStatus

    /// まだ誰も提案していない状態（ルームの作成時の値）
    static let initial = Self(
        used: false, proposedBy: nil, proposedAt: nil, votesFor: [], votesAgainst: [], status: .notProposed
    )
}

/// 引き直しの投票の状態。`rawValue` は Firestore の `reroll.status` の値。
nonisolated enum RerollStatus: String, CaseIterable, Codable, Sendable {
    /// 提案されていない（保存する値は 05 の §3 の `none`。Swift の名前を `none` にすると
    /// `Optional` の `.none` と紛れるので変える）
    case notProposed = "none"
    /// 投票中
    case voting
    /// 可決（過半数が賛成）
    case passed
    /// 否決（期限までに過半数に届かなかった）
    case rejected
}
