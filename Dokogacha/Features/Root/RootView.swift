//
//  RootView.swift
//  Dokogacha
//

import SwiftUI

/// アプリの根元の画面。起動の流れ（`RootModel`）の判定に合わせて、起動中・失敗・S-01・ホーム（`MainNavigationView`）を切り替える。
///
/// トーストの窓口（`DGToastCenter`）をここで 1 つ持ち、画面の根元に重ねる（どの画面のトーストも同じ位置に出す）。
/// 後の画面は `@Environment(DGToastCenter.self)` で受け取れる。
/// オフラインの間は、画面の上端に「オフラインです」のバナーを出し（02 の §9）、回線が戻ったら失敗した起動の流れをやり直す。
struct RootView: View {
    @State private var model: RootModel
    @State private var toasts: DGToastCenter
    @Environment(\.scenePhase) private var scenePhase
    /// 広告のまとめ役（`DokoGachaApp` が渡す。プレビューでは無い）
    @Environment(AdCoordinator.self) private var ads: AdCoordinator?
    /// 広告非表示の買い切りのまとめ役（`DokoGachaApp` が渡す。プレビューでは無い）
    @Environment(PurchaseCoordinator.self) private var purchases: PurchaseCoordinator?
    /// 招待リンクで開かれたときの行き先（表示名を登録するまでは覚えておくだけで、ホームが出たら S-06 を開く）
    private let deepLinks: DeepLinkRouter
    /// 端末の回線の状態（`AppDelegate` が持つもの。プレビューでは無い）
    private let network: NetworkStatus?

    /// - Parameters:
    ///   - session: サーバーへの接続とサインインの状態（`AppDelegate` で `start` 済みのもの）
    ///   - deepLinks: 招待リンクで開かれたときの行き先
    ///   - network: 端末の回線の状態
    init(session: ServerSession, deepLinks: DeepLinkRouter, network: NetworkStatus? = nil) {
        self.deepLinks = deepLinks
        self.network = network
        let toasts = DGToastCenter()
        _toasts = State(initialValue: toasts)
        _model = State(initialValue: RootModel(session: session, toasts: toasts, network: network))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dgBgBase.ignoresSafeArea())
            // 起動のオフラインの画面は、それ自体が「オフラインです」と出すので、バナーを重ねない
            .offlineBanner(isAllowed: model.route.showsOfflineBanner)
            .dgToast(toasts)
            .environment(toasts)
            // サインインの状態が変わるたびに、サインインし直すか、そのユーザーのプロフィールを購読し直す
            .task(id: model.taskKey) {
                await model.follow()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.retryIfFailed()
                }
            }
            // 回線が戻ったら、オフラインで失敗したサインイン・プロフィールの読み込みをやり直す（PR #17・#40 の持ち越し）
            .onChange(of: network?.reachability) { _, reachability in
                if reachability == .online {
                    model.retryIfFailed()
                    // 通信の失敗で送れなかった広告非表示の購入も送り直す（PR #97 の持ち越し）
                    purchases?.retryVerificationIfNeeded()
                }
            }
            // 広告を出すかの判定に、自分が広告非表示を買ったか（`users.adFree` か端末の購入）を渡す（05 の §8）
            .onChange(of: isAdFree, initial: true) { _, isAdFree in
                ads?.isAdFree = isAdFree
            }
            // 端末の購入をサーバーにまだ記録していなければ送る（05 の §8 の `verifyPurchase`）
            .onChange(of: purchaseSyncKey, initial: true) { _, key in
                purchases?.connect(functions: model.session.services.functions, userID: key.userID, serverAdFree: key.serverAdFree)
            }
    }

    /// 端末の購入をサーバーに送るかを決め直す鍵（サインインしているユーザーと、その `users.adFree`）
    private struct PurchaseSyncKey: Equatable {
        let userID: String?
        let serverAdFree: Bool?
    }

    /// 自分のプロフィールの `users.adFree`（プロフィールが読めるまでは nil）
    private var serverAdFree: Bool? {
        if case let .home(profile) = model.route {
            return profile.adFree
        }
        return nil
    }

    /// 端末の購入をサーバーに送るかを決め直す鍵
    private var purchaseSyncKey: PurchaseSyncKey {
        PurchaseSyncKey(userID: model.signedInUserID, serverAdFree: serverAdFree)
    }

    /// 自分が広告非表示を買ったか（サーバーの記録か端末の購入。プロフィールが読めるまでは端末の購入だけ）
    private var isAdFree: Bool {
        AdFreeStatus.isAdFree(serverAdFree: serverAdFree ?? false, hasEntitlement: purchases?.entitlement != nil)
    }

    @ViewBuilder private var content: some View {
        switch model.route {
        case .loading:
            LaunchStatusView(status: .loading)
        case .serverUnavailable:
            LaunchStatusView(status: .serverUnavailable)
        case let .failed(error):
            LaunchStatusView(status: .failed(message: error.message)) {
                model.retry()
            }
        case .offline:
            LaunchStatusView(status: .offline)
        case .onboarding:
            OnboardingView(model: OnboardingModel(auth: model.auth, toasts: toasts))
        case .home:
            if let userID = model.signedInUserID {
                MainNavigationView(userID: userID, services: model.session.services, toasts: toasts, deepLinks: deepLinks)
                    // ユーザーが替わったら、ホームの購読と積んだ画面を作り直す
                    .id(userID)
            }
        }
    }
}
