//
//  RootView.swift
//  Dokogacha
//

import SwiftUI

/// アプリの根元の画面。起動の流れ（`RootModel`）の判定に合わせて、起動中・失敗・S-01・ホームを切り替える。
///
/// トーストの窓口（`DGToastCenter`）をここで 1 つ持ち、画面の根元に重ねる（どの画面のトーストも同じ位置に出す）。
/// 後の画面は `@Environment(DGToastCenter.self)` で受け取れる。
struct RootView: View {
    @State private var model: RootModel
    @State private var toasts: DGToastCenter
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter session: サーバーへの接続とサインインの状態（`AppDelegate` で `start` 済みのもの）
    init(session: ServerSession) {
        let toasts = DGToastCenter()
        _toasts = State(initialValue: toasts)
        _model = State(initialValue: RootModel(session: session, toasts: toasts))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dgBgBase.ignoresSafeArea())
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
        case .onboarding:
            OnboardingView(model: OnboardingModel(auth: model.auth, toasts: toasts))
        case let .home(profile):
            // S-02 ホームはタスク 13 で作る。それまでは仮の画面
            HomePlaceholderView(profile: profile)
        }
    }
}
