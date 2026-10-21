//
//  OnboardingModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-01 オンボーディング（表示名の入力。F-01）の状態と操作。
///
/// 入力の検証は `NameValidation`（backend の `saveProfile` と同じ規則）で行い、通るときだけ「はじめる」を押せる。
/// 登録は `AuthService.saveDisplayName`（Callable の `saveProfile`）を通す。登録が済むと `users/{uid}` ができ、
/// 起動の流れ（`RootModel`）が購読しているプロフィールに届いてホームへ進む（この Model は画面を切り替えない）。
@Observable
final class OnboardingModel {
    /// 入力が正しくない理由（空のときは理由を出さず、ボタンを無効にするだけ）
    typealias InputIssue = NameInputCheck.Issue

    /// 表示名の文字数の範囲（02 の §1「1〜10文字、必須」）
    static let lengthRange = DomainConstants.Limits.displayNameLength

    /// 入力中の表示名
    var displayName = ""
    /// 登録を送っている途中か（二重に送らないため、ボタンと入力欄を止める）
    private(set) var isSubmitting = false
    /// 登録が済んだか（ホームに切り替わるまでの間に、もう一度押せないようにする）
    private(set) var didRegister = false

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let toasts: DGToastCenter
    /// ボタンから始めた登録。画面（Model）が無くなったら止める
    @ObservationIgnored private var submitTask: Task<Void, Never>?

    /// - Parameters:
    ///   - auth: 表示名を登録する窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    init(auth: any AuthService, toasts: DGToastCenter) {
        self.auth = auth
        self.toasts = toasts
    }

    deinit {
        submitTask?.cancel()
    }

    /// 入力の検証の結果（`NameValidation` の規則。文字数の表示とエラーの文言にも使う）
    var check: NameInputCheck {
        NameInputCheck(displayName, length: Self.lengthRange)
    }

    /// 送る表示名（前後の空白を取り除いたもの）。受け付けない入力なら nil
    var validatedName: String? {
        check.validatedName
    }

    /// 文字数（検証と同じ数え方。前後の空白を除き、見えない文字だけなら 0）
    var characterCount: Int {
        check.characterCount
    }

    /// 文字数の上限
    var characterLimit: Int {
        check.limit
    }

    /// 入力が正しくない理由。正しいとき・空のときは nil
    var inputIssue: InputIssue? {
        check.issue
    }

    /// 「はじめる」を押せるか（入力が空・正しくないとき、送っている途中・登録済みのときは押せない）
    var canSubmit: Bool {
        validatedName != nil && !isSubmitting && !didRegister
    }

    /// 「はじめる」が押された・キーボードの完了が押された。登録を始める（送っている途中なら何もしない）。
    ///
    /// `isSubmitting` は Task が動き出してから立つので、Task が始まる前に続けて押されたときのために、
    /// 始めた Task が残っている間も押せないことにする（2 つ目の Task を作って 1 つ目を cancel できなくしない）
    func submitTapped() {
        guard canSubmit, submitTask == nil else {
            return
        }
        submitTask = Task { [weak self] in
            await self?.submit()
            // cancel された Task は `cancelSubmit` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                self?.submitTask = nil
            }
        }
    }

    /// 画面が消えたとき、送っている途中の登録を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）
    func cancelSubmit() {
        submitTask?.cancel()
        submitTask = nil
    }

    /// 表示名を登録する。押せない状態なら何もしない。
    ///
    /// 失敗したらトースト（文言は `AppError`）を出して、入力をそのままにもう一度押せるようにする。
    /// cancel（画面を閉じた）のときはトーストを出さない
    func submit() async {
        guard canSubmit, let name = validatedName else {
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await auth.saveDisplayName(name)
            didRegister = true
        } catch {
            let appError = AppError.wrapping(error)
            if !appError.isCancellation {
                toasts.show(text: appError.message)
            }
        }
    }
}
