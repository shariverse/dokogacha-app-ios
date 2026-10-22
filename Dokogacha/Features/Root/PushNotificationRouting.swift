//
//  PushNotificationRouting.swift
//  Dokogacha
//

import SwiftUI

/// `MainNavigationView` に、プッシュ通知（02 の §8）の端末側の処理をつなぐ。
///
/// - ホームが出たら（表示名を登録済み）、その人のトークンを `users/{uid}.fcmTokens` に書く（`PushNotificationCoordinator.activate`）
/// - 通知が開かれたら（この画面が出る前に開かれたものも、出たときに）、そのルームを開く（`AppPresentation.openNotification`）
/// - いま出しているルームの画面を `PushNotificationCoordinator` に知らせる（前面で届いた通知を出すかを決める）
struct PushNotificationRouting: ViewModifier {
    /// 出している行き先
    @Binding var presentation: AppPresentation
    /// 自分の uid
    let userID: String
    /// 通知を開いたときの行き先
    let deepLinks: DeepLinkRouter
    /// 通知のまとめ役（プレビューなどで無いときは nil）
    let push: PushNotificationCoordinator?

    func body(content: Content) -> some View {
        content
            .task(id: userID) {
                await push?.activate(userID: userID)
            }
            .onChange(of: deepLinks.pendingNotification, initial: true) {
                if let destination = deepLinks.takePendingNotification() {
                    presentation.openNotification(destination)
                }
            }
            .onChange(of: presentation.visibleRoomScreen, initial: true) { _, screen in
                push?.visibleRoomScreen = screen
            }
    }
}
