//
//  AnalyticsService.swift
//  Dokogacha
//

import Foundation

/// Analytics にイベント（05 の §9）を送る窓口。
///
/// 画面の Model は、操作が成功したところでこれに `AnalyticsEvent` を渡す（Firebase の SDK を知らない）。
/// Firebase に繋いだときは `FirebaseAnalyticsService`、擬似のサーバー・接続できないとき・プレビューでは `DisabledAnalyticsService`。
/// テストでは送ったイベントを覚えるものに差し替えて、名前とパラメータを確かめる。
/// 送るかどうか（Debug・テスト・撮影モードでは送らない）は SDK の収集の設定で決める（`FirebaseCollectionPolicy`）
protocol AnalyticsService: AnyObject {
    /// イベントを送る
    func log(_ event: AnalyticsEvent)
}

/// 何も送らない `AnalyticsService`（擬似のサーバー・接続できないとき・プレビュー・画面の Model の既定）
final class DisabledAnalyticsService: AnalyticsService {
    func log(_ event: AnalyticsEvent) {}
}
