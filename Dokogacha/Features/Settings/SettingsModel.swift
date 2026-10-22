//
//  SettingsModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-15 設定の状態と操作。表示名の変更・広告非表示の購入と復元・Sign in with Apple の連携を持つ。
///
/// 規約・プライバシーポリシー・通知設定（OS の設定を開く）・ライセンス・バージョンは、画面（`SettingsView`）だけで行う。
///
/// - 今の表示名は、自分のプロフィール（`users/{uid}`）を `AuthService.profile` で購読して出す。画面（`SettingsView`）は
///   `.task` で `observe()` を呼び、画面が消えると cancel して購読を止める。購読が失敗したらトースト（続けて失敗しても 1 回だけ）を出し、
///   出していた名前のまま、少し待って購読し直す
/// - 変更は編集のシート（`isEditingName`）で入力し、`NameInputCheck`（S-01 と同じ規則）が通って今の名前と違うときだけ保存できる。
///   保存は `AuthService.saveDisplayName`（Callable の `saveProfile`）。参加中のルームのメンバーの表示名は、
///   サーバーのトリガー（`onUserProfileUpdate`）が書き換える
/// - 送っている途中は、もう一度押しても送らない。失敗したらトーストを出し、シートと入力をそのままにする
///
/// 広告非表示の購入と復元（02 の §7.2 F-51）は `PurchaseCoordinator` の `purchase`・`restore` を呼ぶ。購入済みかは、
/// 購読しているプロフィールの `users.adFree` と端末の購入のどちらか（`AdFreeStatus`）。結果はトースト（`PurchaseFeedback`）で知らせる。
///
/// Sign in with Apple の連携（02 の §1 F-01）は、nonce を作って Apple の認証の画面を出し（`AppleAuthorizing`）、受け取った ID トークンで
/// 今の匿名のアカウントに連携する（`AuthService.linkWithApple`）。その Apple ID が既に別のアカウントに連携されていたら、
/// そのアカウントでサインインし直すかを尋ね（`isConfirmingAccountSwitch`）、選ばれたらサインインし直す（参加ルームが戻る。F-01 の AC）。
/// サインインし直す前に、今の匿名のアカウントを削除する（`AuthService.deleteAccount`）。サインインし直すと今のアカウントには戻れないので、
/// 残すと、参加中のルームのメンバーに残り続けて「全員OK」のルームが解禁できなくなり、使われないプロフィールがサーバーに残るため。
///
/// アカウントの削除（02 の §2.6 F-06）は、確認（`isConfirmingDeletion`）で「削除する」が選ばれたら、Sign in with Apple に連携済みなら
/// Apple の認証をもう一度行ってトークンを取り消し（`AuthService.revokeAppleToken`）、サーバーで削除し
/// （`AuthService.deleteAccount`）、この端末に残す値を消して（`AccountDeviceData`）、サインアウトする（`AuthService.signOut`）。
/// サインアウトすると起動の流れが匿名でサインインし直し、S-01 オンボーディングを出す。失敗したらトーストを出し、何も消さない（もう一度押せる）。
///
/// 購入・復元・連携・削除は 1 つずつ行い（`activeAction`）、行っている途中はほかの行も押せない。
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

    /// 行っている途中の操作（購入・復元・連携。無ければ nil）
    private(set) var activeAction: Action?
    /// 広告非表示のアイテムの価格の表示（StoreKit から読めたら入る。読めなければ仮決めの ¥480 を出す）
    private(set) var displayPrice: String?
    /// サインインしているアカウントが Sign in with Apple に連携済みか
    private(set) var isLinkedWithApple: Bool
    /// 「この Apple ID は別のアカウントで使われています」の確認を出しているか
    var isConfirmingAccountSwitch = false
    /// 「アカウントを削除しますか？」の確認を出しているか
    var isConfirmingDeletion = false

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let purchases: PurchaseCoordinator
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let deviceData: AccountDeviceData
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// Apple の認証の窓口を差し替えるとき（擬似のサーバー・テスト）。nil なら画面の環境の `authorizationController` を使う
    @ObservationIgnored let appleAuthorizer: (any AppleAuthorizing)?
    /// nonce を作る（テストでは決まった値を返すものを渡す）
    @ObservationIgnored private let makeNonce: () -> String
    /// ボタンから始めた保存。シートが消えたら止める
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// ボタンから始めた購入・復元・連携。画面が無くなったら止める
    @ObservationIgnored private var actionTask: Task<Void, Never>?

    /// 購入・復元・連携・削除のどれを行っているか
    enum Action: Equatable {
        /// 広告非表示の購入
        case purchase
        /// 購入の復元
        case restore
        /// Sign in with Apple の連携（別のアカウントでのサインインし直しを含む）
        case linkApple
        /// アカウントの削除
        case deleteAccount
    }

    /// - Parameters:
    ///   - userID: 自分の uid
    ///   - auth: プロフィールの購読・表示名の保存・Apple の連携の窓口（Firebase か擬似のサーバー）
    ///   - purchases: 広告非表示の買い切りのまとめ役
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - deviceData: アカウントを削除した後に、この端末に残す値を消す窓口
    ///   - appleAuthorizer: Apple の認証の窓口（nil なら画面の環境のものを使う）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    ///   - makeNonce: Sign in with Apple の nonce を作る
    init(
        userID: String,
        auth: any AuthService,
        purchases: PurchaseCoordinator,
        toasts: DGToastCenter,
        deviceData: AccountDeviceData = .none,
        appleAuthorizer: (any AppleAuthorizing)? = nil,
        resubscribeDelay: ResubscribeDelay = .standard,
        makeNonce: @escaping () -> String = { AppleSignInNonce.make() }
    ) {
        self.userID = userID
        self.auth = auth
        self.purchases = purchases
        self.toasts = toasts
        self.deviceData = deviceData
        self.appleAuthorizer = appleAuthorizer
        self.resubscribeDelay = resubscribeDelay
        self.makeNonce = makeNonce
        isLinkedWithApple = auth.isLinkedWithApple
    }

    deinit {
        saveTask?.cancel()
        actionTask?.cancel()
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
            toasts.showFailure(error)
        }
    }
}

// MARK: - 広告非表示の購入と復元

extension SettingsModel {
    /// 「広告を非表示にする（¥480）」の行の状態
    var removeAdsRow: RemoveAdsRowState {
        RemoveAdsRowState.make(isAdFree: purchases.isAdFree(serverAdFree: profile?.adFree ?? false), displayPrice: displayPrice)
    }

    /// 購入・復元・連携・削除の行を押せるか（どれかを行っている途中は押せない）
    var canStartAction: Bool {
        activeAction == nil
    }

    /// 広告非表示のアイテムの価格を読み込む（読めなければ仮決めの価格のまま。トーストは出さない）
    func loadProduct() async {
        guard displayPrice == nil, let product = try? await purchases.product() else {
            return
        }
        displayPrice = product.displayPrice
    }

    /// 「広告を非表示にする（¥480）」が押された
    func purchaseTapped() {
        start { model in await model.purchase() }
    }

    /// 「購入を復元」が押された
    func restoreTapped() {
        start { model in await model.restore() }
    }

    /// 広告非表示のアイテムを買う。結果をトーストで知らせる（購入の確認でやめたときは出さない）
    func purchase() async {
        guard case .available = removeAdsRow else {
            return
        }
        await perform(.purchase) {
            let outcome = try await purchases.purchase()
            if let message = PurchaseFeedback.message(for: outcome) {
                toasts.show(text: message)
            }
        }
    }

    /// 購入を復元する。結果をトーストで知らせる
    func restore() async {
        await perform(.restore) {
            let restored = try await purchases.restore()
            toasts.show(text: PurchaseFeedback.restoreMessage(restored: restored))
        }
    }
}

// MARK: - Sign in with Apple の連携

extension SettingsModel {
    /// 「Apple でサインインを連携」が押された
    /// - Parameter authorizer: Apple の認証の窓口（画面の環境のもの。`appleAuthorizer` があればそちらを使う）
    func linkAppleTapped(using authorizer: any AppleAuthorizing) {
        let authorizer = appleAuthorizer ?? authorizer
        start { model in await model.linkApple(using: authorizer) }
    }

    /// 確認で「サインインし直す」が押された
    func switchAccountConfirmed() {
        start { model in await model.switchToLinkedAppleAccount() }
    }

    /// Apple の認証の画面を出し、今のアカウントに連携する。
    ///
    /// 既に別のアカウントに連携された Apple ID なら、そのアカウントでサインインし直すかを尋ねる。ユーザーがやめたら何もしない
    func linkApple(using authorizer: any AppleAuthorizing) async {
        guard !isLinkedWithApple else {
            return
        }
        await perform(.linkApple) {
            let nonce = makeNonce()
            guard let idToken = try await authorizer.authorize(nonceHash: AppleSignInNonce.sha256(nonce)) else {
                return
            }
            switch try await auth.linkWithApple(AppleIDCredential(idToken: idToken, rawNonce: nonce)) {
            case .linked:
                isLinkedWithApple = true
                toasts.show(text: String(localized: "Apple でサインインを連携しました"))
            case .alreadyInUse:
                isConfirmingAccountSwitch = true
            }
        }
    }

    /// 既に Apple ID に連携されたアカウントでサインインし直す（サインインし直すと、起動の流れがそのユーザーのホームを開き直す）。
    ///
    /// 先に今の匿名のアカウントをサーバーで削除する（参加中のルームから退出し、作成したルームは終了する。確認の文言で伝える）。
    /// 今のアカウントは Apple に連携していない（連携しようとした Apple ID は別のアカウントのもの）ので、Apple のトークンは取り消さない。
    /// 削除に失敗したらサインインし直さない（今のアカウントのまま、もう一度押せる）。
    /// 削除の後にサインインし直せなかったら、消えたアカウントのまま残らないようサインアウトする（匿名でサインインし直して S-01 に戻る）
    func switchToLinkedAppleAccount() async {
        await perform(.linkApple) {
            try await deleteCurrentAccountOnServer()
            do {
                _ = try await auth.signInWithLinkedAppleAccount()
            } catch {
                auth.signOut()
                throw error
            }
        }
    }
}

// MARK: - アカウントの削除

extension SettingsModel {
    /// 「アカウントを削除」が押された。確認を出す（ほかの操作を行っている途中は出さない）
    func deleteAccountTapped() {
        guard canStartAction else {
            return
        }
        isConfirmingDeletion = true
    }

    /// 確認で「削除する」が押された
    /// - Parameter authorizer: Apple の認証の窓口（画面の環境のもの。`appleAuthorizer` があればそちらを使う）
    func deletionConfirmed(using authorizer: any AppleAuthorizing) {
        let authorizer = appleAuthorizer ?? authorizer
        start { model in await model.deleteAccount(using: authorizer) }
    }

    /// アカウントを削除する（02 の F-06）。サーバーで削除できたら、この端末に残す値を消してサインアウトする（S-01 に戻る）。
    ///
    /// Sign in with Apple に連携済みなら、先に Apple の認証をもう一度行って authorization code を受け取り、トークンを取り消す
    /// （Apple の「Offering account deletion in your app」・審査ガイドライン 5.1.1(v)。サーバーで消すと Auth のユーザーが無くなって取り消せない）。
    /// Apple の画面でやめたら削除しない（トーストも出さない）。取り消せなかったら削除せずにトーストを出す
    /// （Apple に連携が残ったままアカウントだけ消えるのを避ける。もう一度押せる）。
    ///
    /// 削除に失敗したらトーストを出し、端末の値もサインインもそのまま（もう一度押せる。サーバーの削除は続きから終わる）
    func deleteAccount(using authorizer: any AppleAuthorizing) async {
        await perform(.deleteAccount) {
            if auth.isLinkedWithApple {
                guard let code = try await authorizer.authorizationCode() else {
                    return
                }
                try await auth.revokeAppleToken(authorizationCode: code)
            }
            try await deleteCurrentAccountOnServer()
            deviceData.clear()
            auth.signOut()
        }
    }

    /// 今のアカウントをサーバーで削除する。
    ///
    /// 失敗しても、Auth のユーザーが消えていれば（応答が届かなかった・消し終えた後に失敗した）、削除できたことにする。
    /// サーバーは `users/{uid}` を先に消すので、失敗として消えた uid のまま残すと、プロフィールが無いので S-01 に替わり、
    /// 表示名を登録すると `users/{uid}` を作り直してしまうため
    private func deleteCurrentAccountOnServer() async throws {
        do {
            try await auth.deleteAccount()
        } catch {
            guard await auth.isCurrentAccountDeleted() else {
                throw error
            }
        }
    }
}

// MARK: - 操作の共通

extension SettingsModel {
    /// ボタンから操作を始める（ほかの操作を行っている途中・始めた Task が残っている間は始めない）
    private func start(_ operation: @escaping (SettingsModel) async -> Void) {
        guard canStartAction, actionTask == nil else {
            return
        }
        actionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await operation(self)
            actionTask = nil
        }
    }

    /// 操作を行う。行っている間は `activeAction` を立て、失敗したらトースト（cancel では出さない）を出す
    private func perform(_ action: Action, _ operation: () async throws -> Void) async {
        guard activeAction == nil else {
            return
        }
        activeAction = action
        defer { activeAction = nil }
        do {
            try await operation()
        } catch {
            toasts.showFailure(error)
        }
    }
}
