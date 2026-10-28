//
//  AccountDeviceData.swift
//  Dokogacha
//

import Foundation

/// この端末に残している、サインインしているアカウントに結び付く値を消す窓口（02 の F-06 のアカウントの削除の後に呼ぶ）。
///
/// 消すもの: 演出を見終えた抽選（`SeenDrawStore`）・報告した候補（`ReportedCandidateStore`）・通知のトークンを書いた先の記録
/// （`PushNotificationCoordinator`）・購入を送ったユーザーの記録（`PurchaseCoordinator`）。
/// 画面の Model（`SettingsModel`）はこの窓口だけを受け取り、何を消すかは画面を組み立てる側（`MainNavigationView`）が決める
struct AccountDeviceData {
    /// 消す処理
    let clear: () -> Void

    /// 何も消さない窓口（プレビュー・撮影モード・テスト）
    static let none = Self {}

    /// データ層の窓口と、通知・購入のまとめ役から作る
    /// - Parameters:
    ///   - services: データ層の窓口（見た抽選・報告した候補）
    ///   - push: 通知のまとめ役（無ければ何もしない）
    ///   - purchases: 購入のまとめ役（無ければ何もしない）
    static func make(services: DataServices, push: PushNotificationCoordinator?, purchases: PurchaseCoordinator?) -> Self {
        let seenDraws = services.seenDraws
        let reportedCandidates = services.reportedCandidates
        return Self {
            seenDraws.removeAll()
            reportedCandidates.removeAll()
            push?.forgetAccount()
            purchases?.forgetAccount()
        }
    }
}
