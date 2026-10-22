//
//  AppError.swift
//  Dokogacha
//

import Foundation

/// サーバー（Callable Functions・Firestore）が返すエラーの分類（gRPC の標準のコード）。
///
/// 値は gRPC の番号と同じにしてある。Firebase の `FunctionsErrorCode`・`FirestoreErrorCode` も同じ番号なので、
/// SDK のエラーの `code` からそのまま作れる（`init(grpcCode:)`）。SDK の型をデータ層の外に出さないために持つ。
nonisolated enum ServerErrorCode: Int, CaseIterable, Equatable, Sendable {
    case ok = 0
    case cancelled = 1
    case unknown = 2
    case invalidArgument = 3
    case deadlineExceeded = 4
    case notFound = 5
    case alreadyExists = 6
    case permissionDenied = 7
    case resourceExhausted = 8
    case failedPrecondition = 9
    case aborted = 10
    case outOfRange = 11
    case unimplemented = 12
    case `internal` = 13
    case unavailable = 14
    case dataLoss = 15
    case unauthenticated = 16

    /// SDK のエラーの番号から作る。知らない番号は `unknown`
    init(grpcCode: Int) {
        self = Self(rawValue: grpcCode) ?? .unknown
    }
}

/// サーバーから返ったエラーの中身（SDK のエラーから取り出したもの）。
///
/// Firebase の実装（`FirebaseCallableTransport`・`FirebaseFirestoreGateway`）が SDK のエラーをこの形にし、
/// `AppError.server(_:)` がアプリの文言に対応付ける。
nonisolated struct ServerFailure: Error, Equatable, Sendable {
    /// gRPC の分類
    var code: ServerErrorCode
    /// Callable の `HttpsError` の `details.reason`（backend の `errors.ts` の `AppErrorReason`）。無ければ nil
    var reason: String?
}

/// データ層の操作が失敗したときのエラー。画面は `message` をトーストなどにそのまま出す。
///
/// **`isCancellation` のときはトーストを出さない。** 画面を閉じた・操作をやめたので `Task` を cancel した結果で、
/// 通信の失敗ではない（`CancellationError`・SDK の cancel（gRPC の `cancelled`・`NSURLErrorCancelled`）がここに入る）。
///
/// Callable Functions の `HttpsError`（`code` と `details.reason`）・Firestore の購読と書き込みの失敗・
/// サーバーに接続できない状態を、**ここ 1 か所で**アプリの文言（03 の表記。無いものはこのファイルで決める）に対応付ける。
/// 文言は `reason` で引く。同じ `code` に別の理由が複数ある（例: `failed-precondition` に「作成者は退出できません」と
/// 「このルームはもう行き先が決まっています」）ため、`code` だけでは決められない。
nonisolated struct AppError: Error, Equatable, Sendable {
    /// エラーの理由
    let reason: Reason
    /// サーバーが返した gRPC の分類（サーバーから返ったものでなければ nil）。再試行してよいかの判断に使う
    let code: ServerErrorCode?

    /// 理由と分類から作る
    init(_ reason: Reason, code: ServerErrorCode? = nil) {
        self.reason = reason
        self.code = code
    }

    /// 画面に出す文言
    var message: String {
        reason.message
    }

    /// cancel した結果か（画面を閉じた・操作をやめた）。true なら画面はトーストを出さずに捨てる
    var isCancellation: Bool {
        reason == .cancelled
    }

    /// セキュリティルールで拒まれたか（permission-denied）。
    ///
    /// 購読がこれで終わったら、ルールの `isMember` で読めなくなった（ルームが削除された・メンバーから外れた・無いルームを開いた）ことを表し、
    /// 購読し直しても読めない（`RoomModel` は「ルームが見つかりません」にする）
    var isPermissionDenied: Bool {
        code == .permissionDenied || reason == .permissionDenied
    }

    /// 通信の問題で、同じ操作をもう一度すれば通るかもしれないか（cancel は含めない）
    var isRetryable: Bool {
        switch code {
        case .unavailable, .deadlineExceeded, .aborted:
            true
        default:
            reason == .network
        }
    }

    /// サーバーのエラーをアプリのエラーにする。
    ///
    /// 1. `reason`（backend の `errors.ts` の理由）を知っていれば、その文言にする
    /// 2. 知らない理由（backend に新しく足した理由を、古いアプリが受け取ったとき）・理由が無いときは、`code` で大まかに決める。
    ///    どれにも当たらなければ「通信できませんでした」にする（内部の情報を画面に出さない）
    static func server(_ failure: ServerFailure) -> Self {
        if let reasonText = failure.reason, let reason = Reason(serverReason: reasonText) {
            return Self(reason, code: failure.code)
        }
        return Self(fallbackReason(for: failure.code), code: failure.code)
    }

    /// どんなエラーでもアプリのエラーにする（`AppError`・`ServerFailure` 以外は「通信できませんでした」）
    static func wrapping(_ error: any Error) -> Self {
        switch error {
        case let appError as Self:
            appError
        case let failure as ServerFailure:
            server(failure)
        case is CancellationError:
            Self(.cancelled, code: .cancelled)
        default:
            Self(.internal)
        }
    }

    /// 理由が分からないときの、`code` からの対応
    private static func fallbackReason(for code: ServerErrorCode) -> Reason {
        switch code {
        case .invalidArgument, .outOfRange:
            .invalidArgument
        case .unauthenticated:
            .unauthenticated
        case .permissionDenied:
            .permissionDenied
        case .cancelled:
            .cancelled
        case .unavailable, .deadlineExceeded, .aborted:
            .network
        case .ok, .unknown, .notFound, .alreadyExists, .resourceExhausted, .failedPrecondition,
             .unimplemented, .internal, .dataLoss:
            .internal
        }
    }
}

extension AppError {
    /// エラーの理由。
    ///
    /// 前半は backend の `backend/functions/src/errors.ts` の `APP_ERRORS` の鍵と同じ値（`rawValue`）で、
    /// `HttpsError` の `details.reason` から作る。後半はアプリだけの理由で、`rawValue` に `app/` を付けて
    /// サーバーの理由と取り違えないようにする。
    nonisolated enum Reason: String, CaseIterable, Equatable, Sendable {
        // MARK: サーバーの理由（errors.ts と同じ）

        /// サインインしていない
        case unauthenticated
        /// 入力の形が正しくない
        case invalidArgument = "invalid-argument"
        /// 表示名を登録する前に、ルームを作成・参加しようとした
        case profileRequired = "profile-required"
        /// 招待コードが存在しない・形が正しくない（F-04 の AC）
        case inviteCodeNotFound = "invite-code-not-found"
        /// メンバーが上限に達している（F-04 の AC）
        case roomFull = "room-full"
        /// ルームが `drawn`・`closed` で参加できない（F-04 の AC）。候補の追加・削除・強制解禁を `drawn`・`closed` でしたときも
        case roomAlreadyDecided = "room-already-decided"
        /// ルームが存在しない
        case roomNotFound = "room-not-found"
        /// ルームのメンバーではない
        case notRoomMember = "not-room-member"
        /// 作成者だけができる操作を、作成者以外がした
        case notRoomOwner = "not-room-owner"
        /// 作成者は退出できない（F-05）
        case ownerCannotLeave = "owner-cannot-leave"
        /// 作成者は削除できない
        case cannotRemoveOwner = "cannot-remove-owner"
        /// 削除しようとした人が、もうメンバーにいない
        case memberNotFound = "member-not-found"
        /// 自分の投稿数がルームの上限に達している（F-10）
        case postLimitReached = "post-limit-reached"
        /// ルームの候補が上限（200 件）に達している
        case roomCandidatesFull = "room-candidates-full"
        /// 候補が存在しない（ほかの人がすでに削除した）
        case candidateNotFound = "candidate-not-found"
        /// 投稿した人と作成者以外が候補を削除しようとした（F-11）
        case notCandidateOwner = "not-candidate-owner"
        /// ルームが `closed` で設定を変えられない（F-03）
        case roomClosed = "room-closed"
        /// 投稿数を今より少なくしようとした（F-03「引き上げのみ可」）
        case postLimitDecrease = "post-limit-decrease"
        /// `open` 以外で解禁の条件を変えようとした（F-03）
        case unlockRuleLocked = "unlock-rule-locked"
        /// `drawn`・`closed` でいいねの効き方を変えようとした（F-03）
        case likeModeLocked = "like-mode-locked"
        /// ルームが解禁されていない（F-40。`unlocked` でも、数え直した準備OKで条件を満たさないとき）
        case roomNotUnlocked = "room-not-unlocked"
        /// 抽選の対象の候補が無い（F-40「候補がありません」）
        case noCandidates = "no-candidates"
        /// ガチャで当選した候補（今の当選・引き直しで除外した前の当選）を削除しようとした
        case candidateDrawn = "candidate-drawn"
        /// 行き先が決まる前（`open`・`unlocked`）に、引き直しを提案した（F-43）か「この行き先で決定」をした（F-44）
        case roomNotDrawn = "room-not-drawn"
        /// 引き直しの権利を使った後に、もう一度提案した（F-43 の AC「引き直しは2回目を提案できない」）
        case rerollUsed = "reroll-used"
        /// 投票中でない引き直しに投票した（可決・否決の後など）
        case rerollNotVoting = "reroll-not-voting"
        /// 招待コードを決められなかった（もう一度で通る見込みが高い）
        case inviteCodeUnavailable = "invite-code-unavailable"
        /// 想定していないエラー
        case `internal`

        // MARK: アプリだけの理由

        /// セキュリティルールで拒まれた（直接の書き込み・購読。理由が付かない）
        case permissionDenied = "app/permission-denied"
        /// 通信できない（オフライン・タイムアウト・サーバーが一時的に使えない）
        case network = "app/network"
        /// Firebase を初期化できず、サーバーに接続できない（plist が無い Stg など）
        case serverUnavailable = "app/server-unavailable"
        /// サーバーのドキュメントを読めなかった（知らない状態の値など）
        case unreadableData = "app/unreadable-data"
        /// 擬似のサーバーにまだ無い操作（後続のタスクで足す）
        case notImplemented = "app/not-implemented"
        /// cancel した（`Task` の cancel・SDK の cancel）。通信の失敗ではないので、画面はトーストを出さない（`isCancellation`）
        case cancelled = "app/cancelled"

        /// サーバーの理由（`app/` で始まらないもの）
        static let serverReasons: [Self] = allCases.filter { !$0.rawValue.hasPrefix("app/") }

        /// サーバーの `details.reason` から作る。アプリだけの理由・知らない理由は nil
        init?(serverReason: String) {
            guard let reason = Self(rawValue: serverReason), Self.serverReasons.contains(reason) else {
                return nil
            }
            self = reason
        }

        /// 画面に出す文言（03 にあればその表記。backend の `errors.ts` の `message` と同じ）
        var message: String {
            switch self {
            case .invalidArgument:
                String(localized: "入力内容を確認してください")
            case .profileRequired:
                String(localized: "表示名を登録してください")
            case .inviteCodeNotFound:
                String(localized: "招待コードが見つかりません")
            case .roomFull:
                String(localized: "このルームは満員です（最大\(DomainConstants.Limits.maxMembers)人）")
            case .roomAlreadyDecided:
                String(localized: "このルームはもう行き先が決まっています")
            case .roomNotFound:
                String(localized: "ルームが見つかりません")
            case .notRoomMember:
                String(localized: "このルームのメンバーではありません")
            case .notRoomOwner:
                String(localized: "作成者だけが操作できます")
            case .ownerCannotLeave:
                String(localized: "作成者はルームから退出できません")
            case .cannotRemoveOwner:
                String(localized: "作成者は削除できません")
            case .memberNotFound:
                String(localized: "このメンバーはもうルームにいません")
            case .postLimitReached:
                String(localized: "投稿できる数の上限に達しています")
            case .roomCandidatesFull:
                String(localized: "このルームの候補は上限に達しています（最大\(DomainConstants.Limits.maxCandidates)件）")
            case .candidateNotFound:
                String(localized: "候補が見つかりません")
            case .notCandidateOwner:
                String(localized: "投稿した人と作成者だけが削除できます")
            case .roomClosed:
                String(localized: "このルームは終了しています")
            case .postLimitDecrease:
                String(localized: "投稿数は今より少なくできません")
            case .unlockRuleLocked:
                String(localized: "解禁の条件は候補募集中のときだけ変更できます")
            case .likeModeLocked:
                String(localized: "行き先が決まった後は、いいねの効き方を変更できません")
            case .roomNotUnlocked:
                String(localized: "まだガチャは解禁されていません")
            case .noCandidates:
                String(localized: "候補がありません")
            case .candidateDrawn:
                String(localized: "ガチャで当選した候補は削除できません")
            case .roomNotDrawn:
                String(localized: "まだ行き先が決まっていません")
            case .rerollUsed:
                String(localized: "引き直しは使用済みです")
            case .rerollNotVoting:
                String(localized: "引き直しの投票は終わっています")
            case .permissionDenied:
                String(localized: "この操作はできません")
            case .unauthenticated, .inviteCodeUnavailable, .internal, .network, .serverUnavailable,
                 .unreadableData, .notImplemented, .cancelled:
                String(localized: "通信できませんでした")
            }
        }
    }
}
