//
//  TrackingAuthorizationPrompt.swift
//  Dokogacha
//

import SwiftUI

/// ルームの画面（S-07）が出たら、まだ尋ねていなければ ATT の許可を尋ねる（02 の F-50「初回にルームに入ったあと（オンボーディング中ではない）」）。
///
/// - 尋ねるかは `AdCoordinator`（`AdTrackingPolicy`）が決める。テスト・撮影モード・広告非表示を買った人には尋ねない
/// - 初めてルームを作成・参加したときは通知の許可も尋ねる（02 の §8）ので、通知のダイアログの答えが出るのを待ってから尋ねる
/// - OS はアプリが前面（`active`）にいないとダイアログを出さない（通知のダイアログを出している間は `inactive`）。
///   前面に戻るたびに動かし直すので、出せなかったときは次に前面に戻ったときに尋ねる
struct TrackingAuthorizationPrompt: ViewModifier {
    /// プッシュ通知のまとめ役（プレビューでは無い）
    let push: PushNotificationCoordinator?

    /// 広告のまとめ役（`DokoGachaApp` が渡す。プレビューでは無い）
    @Environment(AdCoordinator.self) private var ads: AdCoordinator?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase == .active) {
                guard scenePhase == .active, let ads else {
                    return
                }
                await push?.waitForAuthorizationRequest()
                guard !Task.isCancelled else {
                    return
                }
                await ads.requestTrackingAuthorizationIfNeeded()
            }
    }
}
