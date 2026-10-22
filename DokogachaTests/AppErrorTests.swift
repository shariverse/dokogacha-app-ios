//
//  AppErrorTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// サーバーのエラー（`HttpsError` の `code` と `details.reason`）から、アプリの文言への対応を確かめる
struct AppErrorTests {
    /// backend の `backend/functions/src/errors.ts` の `APP_ERRORS` の鍵と文言（変えたら両方を変える）
    nonisolated static let backendReasons: [(reason: String, message: String)] = [
        ("unauthenticated", "通信できませんでした"),
        ("invalid-argument", "入力内容を確認してください"),
        ("profile-required", "表示名を登録してください"),
        ("invite-code-not-found", "招待コードが見つかりません"),
        ("room-full", "このルームは満員です（最大20人）"),
        ("room-already-decided", "このルームはもう行き先が決まっています"),
        ("room-not-found", "ルームが見つかりません"),
        ("not-room-member", "このルームのメンバーではありません"),
        ("not-room-owner", "作成者だけが操作できます"),
        ("owner-cannot-leave", "作成者はルームから退出できません"),
        ("cannot-remove-owner", "作成者は削除できません"),
        ("member-not-found", "このメンバーはもうルームにいません"),
        ("post-limit-reached", "投稿できる数の上限に達しています"),
        ("room-candidates-full", "このルームの候補は上限に達しています（最大200件）"),
        ("candidate-not-found", "候補が見つかりません"),
        ("not-candidate-owner", "投稿した人と作成者だけが削除できます"),
        ("room-closed", "このルームは終了しています"),
        ("post-limit-decrease", "投稿数は今より少なくできません"),
        ("unlock-rule-locked", "解禁の条件は候補募集中のときだけ変更できます"),
        ("like-mode-locked", "行き先が決まった後は、いいねの効き方を変更できません"),
        ("room-not-unlocked", "まだガチャは解禁されていません"),
        ("no-candidates", "候補がありません"),
        ("candidate-drawn", "ガチャで当選した候補は削除できません"),
        ("room-not-drawn", "まだ行き先が決まっていません"),
        ("reroll-used", "引き直しは使用済みです"),
        ("reroll-not-voting", "引き直しの投票は終わっています"),
        ("cannot-report-own-candidate", "自分の投稿は報告できません"),
        ("invite-code-unavailable", "通信できませんでした"),
        ("internal", "通信できませんでした")
    ]

    @Test(arguments: backendReasons)
    func mapsBackendReasonToMessage(reason: String, message: String) {
        let error = AppError.server(ServerFailure(code: .failedPrecondition, reason: reason))
        #expect(error.reason.rawValue == reason)
        #expect(error.message == message)
    }

    /// アプリが知っているサーバーの理由が、backend の一覧と過不足なく一致する
    @Test
    func serverReasonsMatchBackend() {
        let appReasons = Set(AppError.Reason.serverReasons.map(\.rawValue))
        #expect(appReasons == Set(Self.backendReasons.map(\.reason)))
    }

    /// F-04 の AC の 3 つの文言
    @Test
    func joinErrorsUseRequirementWording() {
        #expect(AppError(.inviteCodeNotFound).message == "招待コードが見つかりません")
        #expect(AppError(.roomFull).message == "このルームは満員です（最大20人）")
        #expect(AppError(.roomAlreadyDecided).message == "このルームはもう行き先が決まっています")
    }

    /// 知らない理由（新しい backend と古いアプリ）・理由が無いときは、gRPC の分類で大まかに決める
    @Test(arguments: [
        (ServerErrorCode.invalidArgument, AppError.Reason.invalidArgument),
        (.unauthenticated, .unauthenticated),
        (.permissionDenied, .permissionDenied),
        (.unavailable, .network),
        (.deadlineExceeded, .network),
        (.failedPrecondition, .internal),
        (.notFound, .internal),
        (.internal, .internal)
    ])
    func fallsBackToCodeForUnknownReason(code: ServerErrorCode, expected: AppError.Reason) {
        #expect(AppError.server(ServerFailure(code: code, reason: "added-in-a-later-version")).reason == expected)
        #expect(AppError.server(ServerFailure(code: code, reason: nil)).reason == expected)
    }

    /// アプリだけの理由は、サーバーから送られても受け付けない
    @Test
    func doesNotAcceptAppOnlyReasonFromServer() {
        #expect(AppError.Reason(serverReason: "app/network") == nil)
        #expect(AppError.server(ServerFailure(code: .internal, reason: "app/not-implemented")).reason == .internal)
    }

    @Test
    func retryableOnlyForTransientFailures() {
        #expect(AppError.server(ServerFailure(code: .unavailable, reason: "invite-code-unavailable")).isRetryable)
        #expect(AppError(.network).isRetryable)
        #expect(!AppError.server(ServerFailure(code: .resourceExhausted, reason: "room-full")).isRetryable)
    }

    /// cancel は通信の失敗と見分ける（画面はトーストを出さない）。再試行の対象にもしない
    @Test
    func cancellationIsDistinguishedFromNetworkFailure() {
        let wrapped = AppError.wrapping(CancellationError())
        #expect(wrapped.isCancellation)
        #expect(wrapped.reason == .cancelled)
        #expect(!wrapped.isRetryable)
        #expect(AppError.server(ServerFailure(code: .cancelled)).isCancellation)
        // サーバーから `app/cancelled` を送られても受け付けない
        #expect(AppError.Reason(serverReason: "app/cancelled") == nil)
        #expect(!AppError(.network).isCancellation)
        #expect(!AppError.server(ServerFailure(code: .unavailable)).isCancellation)
    }

    @Test
    func wrapsAnyError() {
        struct Other: Error {}
        #expect(AppError.wrapping(Other()).message == "通信できませんでした")
        #expect(AppError.wrapping(AppError(.roomFull)) == AppError(.roomFull))
        #expect(AppError.wrapping(ServerFailure(code: .notFound, reason: "room-not-found")).reason == .roomNotFound)
        #expect(ServerErrorCode(grpcCode: 99) == .unknown)
    }
}
