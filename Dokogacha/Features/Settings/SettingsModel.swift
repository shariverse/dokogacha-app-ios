//
//  SettingsModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-15 設定の状態と操作。いまは表示名の変更（02 の F-01「表示名は設定画面から変更できる」）だけを持つ。
///
/// - 今の表示名は、自分のプロフィール（`users/{uid}`）を `AuthService.profile` で購読して出す。画面（`SettingsView`）は
///   `.task` で `observe()` を呼び、画面が消えると cancel して購読を止める。購読が失敗したらトースト（続けて失敗しても 1 回だけ）を出し、
///   出していた名前のまま、少し待って購読し直す
/// - 変更は編集のシート（`isEditingName`）で入力し、`NameInputCheck`（S-01 と同じ規則）が通って今の名前と違うときだけ保存できる。
///   保存は `AuthService.saveDisplayName`（Callable の `saveProfile`）。参加中のルームのメンバーの表示名は、
///   サーバーのトリガー（`onUserProfileUpdate`）が書き換える
/// - 送っている途中は、もう一度押しても送らない。失敗したらトーストを出し、シートと入力をそのままにする
///
/// 残りの項目（広告非表示の購入と復元・Apple の連携・通知設定・規約・ライセンス・アカウント削除）はタスク 38・39 で足す。
@Observable
final class SettingsModel {
    /// 表示名の文字数の範囲（02 の §1「1〜10文字、必須」）
    static let lengthRange = DomainConstants.Limits.displayNameLength

    /// 自分の uid
    let userID: String
    /// 購読で届いた自分のプロフィール（まだ届いていない・無いときは nil）
    private(set) var profile: UserProfile?
    /// 最初のプロフィールが届いたか（届くまでは表示名の行を読み込み中の形で出す）
    private(set) var hasLoadedProfile = false

    /// 表示名の編集のシートを出しているか
    var isEditingName = false
    /// 編集中の表示名
    var draftName = ""
    /// 保存を送っている途中か（二重に送らないため、ボタンと入力欄を止める）
    private(set) var isSaving = false

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// ボタンから始めた保存。シートが消えたら止める
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// - Parameters:
    ///   - userID: 自分の uid
    ///   - auth: プロフィールの購読と表示名の保存の窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        userID: String,
        auth: any AuthService,
        toasts: DGToastCenter,
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        self.userID = userID
        self.auth = auth
        self.toasts = toasts
        self.resubscribeDelay = resubscribeDelay
    }

    deinit {
        saveTask?.cancel()
    }

    /// 今の表示名（まだ届いていなければ nil）
    var displayName: String? {
        profile?.displayName
    }

    /// 編集中の表示名の検証の結果
    var draftCheck: NameInputCheck {
        NameInputCheck(draftName, length: Self.lengthRange)
    }

    /// 表示名の行を押せるか（今の名前が届くまでは押せない）
    var canEditName: Bool {
        profile != nil
    }

    /// 「保存」を押せるか（入力が正しく今の名前と違い、送っている途中でないとき）
    var canSave: Bool {
        guard let name = draftCheck.validatedName else {
            return false
        }
        return name != displayName && !isSaving
    }

    // MARK: プロフィールの購読

    /// 自分のプロフィールを購読し、呼んだ `Task` が cancel されるまで続ける
    func observe() async {
        var didShowFailure = false
        while !Task.isCancelled {
            for await update in auth.profile(userID: userID) {
                switch update {
                case let .value(value):
                    profile = value
                    hasLoadedProfile = true
                    didShowFailure = false
                case let .failure(error):
                    guard !error.isCancellation, !didShowFailure else {
                        continue
                    }
                    toasts.show(text: error.message)
                    didShowFailure = true
                }
            }
            guard await resubscribeDelay.wait() else {
                break
            }
        }
    }

    // MARK: 表示名の変更

    /// 表示名の行が押された。今の名前を入れた編集のシートを出す
    func beginEditingName() {
        guard let displayName else {
            return
        }
        draftName = displayName
        isEditingName = true
    }

    /// 「保存」が押された・キーボードの完了が押された。保存を始める（送っている途中なら何もしない）。
    ///
    /// `isSaving` は Task が動き出してから立つので、Task が始まる前に続けて押されたときのために、
    /// 始めた Task が残っている間も押せないことにする
    func saveTapped() {
        guard canSave, saveTask == nil else {
            return
        }
        saveTask = Task { [weak self] in
            await self?.save()
            // cancel された Task は `cancelSave` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                self?.saveTask = nil
            }
        }
    }

    /// 編集のシートが消えたとき、送っている途中の保存を止める（cancel ではトーストを出さない）
    func cancelSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    /// 表示名を保存する。押せない状態なら何もしない。
    ///
    /// 保存できたらシートを閉じる（行の名前は購読しているプロフィールに届いて変わる）。
    /// 失敗したらトースト（文言は `AppError`）を出して、シートと入力をそのままにもう一度押せるようにする
    func save() async {
        guard canSave, let name = draftCheck.validatedName else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await auth.saveDisplayName(name)
            guard !Task.isCancelled else {
                return
            }
            // 購読に届くのを待たずに、行の名前を保存した名前にする（届いたら同じ値で上書きされる）
            profile?.displayName = response.displayName
            isEditingName = false
        } catch {
            let appError = AppError.wrapping(error)
            if !appError.isCancellation {
                toasts.show(text: appError.message)
            }
        }
    }
}
