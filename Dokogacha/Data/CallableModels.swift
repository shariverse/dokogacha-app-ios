//
//  CallableModels.swift
//  Dokogacha
//
//  Callable Functions（05 の §5）の入力と出力の型。
//  プロパティの名前は Callable の `request.data` と戻り値の JSON の鍵（backend の `*/input.ts`・`*/service.ts`）と同じにする。
//  Callable の入力は JSON なので、日時は UNIX 時刻のミリ秒（整数）で送る（`CallableTime`）。
//

import Foundation

/// Callable Functions の名前（backend の `index.ts` で export する名前）
nonisolated enum CallableName: String, CaseIterable, Sendable {
    case saveProfile
    case createRoom
    case joinRoom
    case previewRoom
    case leaveRoom
    case removeMember
    case updateRoomSettings
    case addCandidate
    case deleteCandidate
    case forceUnlock
    case drawGacha
    case proposeReroll
    case voteReroll
    case closeRoom
    case inviteLastMembers
    case reportCandidate
    case verifyPurchase
    case deleteAccount
}

/// Callable に送る日時の形（UNIX 時刻のミリ秒）。`Timestamp` は JSON で送れないため
nonisolated enum CallableTime {
    /// 日時をミリ秒にする（小数は切り捨て）
    static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    /// ミリ秒を日時にする
    static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}

/// 入力・戻り値の無い Callable の `{}`（`deleteAccount` の入力、`leaveRoom` などの戻り値）
nonisolated struct EmptyCallablePayload: Codable, Equatable, Sendable {}

/// ルームを 1 つ指す入力（`leaveRoom`・`forceUnlock`・`drawGacha`・`proposeReroll`・`closeRoom`・`inviteLastMembers`）
nonisolated struct RoomRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
}

// MARK: - ユーザー

/// `saveProfile` の入力（表示名の登録・変更。F-01）
nonisolated struct SaveProfileRequest: Codable, Equatable, Sendable {
    /// 表示名（1〜10 文字。前後の空白はサーバーが取り除く）
    var displayName: String
}

/// `saveProfile` の結果
nonisolated struct SaveProfileResponse: Codable, Equatable, Sendable {
    /// 保存した表示名（前後の空白を取り除いたもの）
    var displayName: String
    /// アバターの色（ユーザーを作ったときにサーバーが決めた色）
    var avatarColor: String
    /// 今回ユーザーを作ったか（初回の表示名の登録）
    var created: Bool
}

/// `verifyPurchase` の入力（F-51）
nonisolated struct VerifyPurchaseRequest: Codable, Equatable, Sendable {
    /// StoreKit 2 の署名付きトランザクション（`Transaction` の `jwsRepresentation`）
    var signedTransaction: String
}

/// `verifyPurchase` の結果
nonisolated struct VerifyPurchaseResponse: Codable, Equatable, Sendable {
    /// 広告非表示になったか（`users.adFree`）
    var adFree: Bool
}

// MARK: - ルーム

/// `createRoom` の入力（F-02）
nonisolated struct CreateRoomRequest: Codable, Equatable, Sendable {
    /// ルーム名（1〜20 文字）
    var name: String
    /// 1 人あたりの投稿数（1〜10）
    var postLimit: Int
    /// 解禁の条件
    var unlockRule: UnlockRule
    /// 締切日時（UNIX 時刻のミリ秒）。`unlockRule` が `deadline` のときだけ送る
    var deadlineAt: Int64?
    /// いいねの効き方
    var likeMode: LikeMode

    /// 画面の入力から作る。締切日時は `unlockRule` が `deadline` のときだけ送る
    init(name: String, postLimit: Int, unlockRule: UnlockRule, deadline: Date?, likeMode: LikeMode) {
        self.name = name
        self.postLimit = postLimit
        self.unlockRule = unlockRule
        deadlineAt = unlockRule == .deadline ? deadline.map(CallableTime.milliseconds(from:)) : nil
        self.likeMode = likeMode
    }
}

/// `createRoom` の結果
nonisolated struct CreateRoomResponse: Codable, Equatable, Sendable {
    /// 作ったルームの ID
    var roomId: String
    /// 招待コード（ハイフンなしの 6 文字。表示は `InviteCode.formatted(_:)`）
    var inviteCode: String
}

/// `joinRoom` の入力（F-04）
nonisolated struct JoinRoomRequest: Codable, Equatable, Sendable {
    /// 招待コード（小文字・ハイフン・全角もサーバーが正規化する）
    var inviteCode: String
}

/// `joinRoom` の結果
nonisolated struct JoinRoomResponse: Codable, Equatable, Sendable {
    /// 参加したルームの ID
    var roomId: String
    /// もとからメンバーだったか（S-06「すでにメンバーなら確認を出さずにルーム画面へ」）
    var alreadyMember: Bool
}

/// `previewRoom` の入力（参加前の確認。S-06）
nonisolated struct PreviewRoomRequest: Codable, Equatable, Sendable {
    /// 招待コード（`joinRoom` と同じく、小文字・ハイフン・全角もサーバーが正規化する）
    var inviteCode: String
}

/// `previewRoom` の結果（S-06 参加確認に出す値。backend の `rooms/logic.ts` の `RoomPreview`）。
///
/// メンバー以外はルームを読めない（セキュリティルール）ので、参加の前に見せる値はこの Callable で受け取る。
/// まだメンバーでなく参加できないルーム（満員・決定後）は、`joinRoom` と同じ理由のエラーになり、この値は返らない
nonisolated struct RoomPreview: Codable, Hashable, Sendable {
    /// ルームの ID
    var roomId: String
    /// ルーム名
    var name: String
    /// 作成者の表示名（作成者のメンバーのドキュメントが無いときは nil）
    var ownerName: String?
    /// メンバー数
    var memberCount: Int
    /// 候補数
    var candidateCount: Int
    /// 状態（S-06 の状態チップ）
    var status: RoomStatus
    /// もとからメンバーか（S-06「すでにメンバーなら確認を出さずにルーム画面へ」）
    var alreadyMember: Bool
}

/// `removeMember` の入力（F-05）
nonisolated struct RemoveMemberRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
    /// 削除するメンバーの uid
    var memberId: String
}

/// `updateRoomSettings` の入力（F-03）。変える項目だけ値を入れる
nonisolated struct UpdateRoomSettingsRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
    /// ルーム名
    var name: String?
    /// 1 人あたりの投稿数（引き上げのみ）
    var postLimit: Int?
    /// 解禁の条件（`open` のときのみ）
    var unlockRule: UnlockRule?
    /// 締切日時（UNIX 時刻のミリ秒）
    var deadlineAt: Int64?
    /// いいねの効き方（`open`・`unlocked` のときのみ）
    var likeMode: LikeMode?
}

/// `inviteLastMembers` の結果（S-04 のトースト「前回のメンバーN人に招待を送りました」）
nonisolated struct InviteLastMembersResponse: Codable, Equatable, Sendable {
    /// 招待を送った人数
    var invitedCount: Int
}

// MARK: - 候補

/// `addCandidate` の入力（F-10・F-13）
nonisolated struct AddCandidateRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
    /// 場所
    var place: Place
    /// カテゴリ
    var category: PlaceCategory
    /// ひとこと（0〜40 文字）
    var note: String
    /// 参考 URL
    var url: String?
    /// 過去のアイデアから持ち込むときの元
    var fromPastIdeaId: String?
}

/// `addCandidate` の戻り値の JSON（追加したら `candidateId`、重複なら `duplicateOf`。05 の §5）
nonisolated struct AddCandidateResponse: Codable, Equatable, Sendable {
    /// 追加した候補の ID
    var candidateId: String?
    /// 重複した既存の候補の ID
    var duplicateOf: String?
}

/// `addCandidate` の結果
nonisolated enum AddCandidateResult: Equatable, Sendable {
    /// 追加した（値は候補の ID）
    case added(candidateID: String)
    /// 同じ場所がすでにあった（F-10「すでに候補にあります。いいねしますか？」。値は既存の候補の ID）
    case duplicate(of: String)
}

/// 候補を 1 つ指す入力（`deleteCandidate`）
nonisolated struct CandidateRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
    /// 候補の ID
    var candidateId: String
}

/// `reportCandidate` の入力（F-14）
nonisolated struct ReportCandidateRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
    /// 候補の ID
    var candidateId: String
    /// 理由
    var reason: ReportReason
}

// MARK: - ガチャ

/// `drawGacha` の結果（F-40。backend の `draw/logic.ts` の `DrawGachaResult` と同じ形）
nonisolated struct DrawGachaResponse: Codable, Equatable, Sendable {
    /// 抽選の ID（`draws/{drawId}`。先に誰かが回していれば、その抽選の ID）
    var drawId: String
    /// 当選した候補の ID（回した人の画面が、購読を待たずにカプセルと結果を出せるように返る）
    var candidateId: String
    /// 先に誰かが回していたか（true なら今回は抽選していない。02 の §6.1「2人目には既存の結果を返す」）
    var alreadyDrawn: Bool
}

/// `voteReroll` の入力（F-43）
nonisolated struct VoteRerollRequest: Codable, Equatable, Sendable {
    /// ルームの ID
    var roomId: String
    /// 賛成なら true、反対なら false
    var approve: Bool
}
