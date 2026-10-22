//
//  SettingsDisplay.swift
//  Dokogacha
//
//  S-15 設定の行の表示と、操作の結果に出すトーストの文言の判定。StoreKit・Bundle から切り出した値だけで決める純粋な関数。
//

import Foundation

/// 「広告を非表示にする（¥480）」の行の状態（03 の S-15「購入済みなら『広告非表示：購入済み』」）。
nonisolated enum RemoveAdsRowState: Equatable, Sendable {
    /// まだ買っていない（押すと購入。値は価格の表示）
    case available(price: String)
    /// 購入済み（押せない）
    case purchased

    /// 行の状態を決める。
    ///
    /// 購入済みかは、サーバーの記録（`users.adFree`）か端末の購入のどちらか（`AdFreeStatus`。広告を出すかと同じ）。
    /// 価格は App Store の表示（地域の通貨）を使い、読み込めないとき（オフライン・App Store にまだ無い）は仮決めの ¥480 にする
    /// - Parameters:
    ///   - isAdFree: 自分を広告非表示として扱うか
    ///   - displayPrice: StoreKit の `Product.displayPrice`（読み込めていなければ nil）
    static func make(isAdFree: Bool, displayPrice: String?) -> Self {
        if isAdFree {
            return .purchased
        }
        if let displayPrice, !displayPrice.trimmingCharacters(in: .whitespaces).isEmpty {
            return .available(price: displayPrice)
        }
        return .available(price: fallbackPrice)
    }

    /// 価格を読み込めないときの表示（06 の §4 の仮決め ¥480）
    static var fallbackPrice: String {
        "¥\(DomainConstants.RemoveAds.priceYen)"
    }
}

/// 購入と復元の結果に出すトーストの文言（03 に無いので、ここで決める）。
nonisolated enum PurchaseFeedback {
    /// 購入の結果の文言。購入の確認でやめたときは出さない（nil）
    static func message(for outcome: PurchaseOutcome) -> String? {
        switch outcome {
        case .purchased:
            String(localized: "広告を非表示にしました")
        case .pending:
            String(localized: "購入の承認待ちです。承認されると広告が消えます")
        case .cancelled:
            nil
        }
    }

    /// 復元の結果の文言
    /// - Parameter restored: 復元できる購入があったか
    static func restoreMessage(restored: Bool) -> String {
        restored ? String(localized: "購入を復元しました") : String(localized: "復元できる購入がありません")
    }
}

/// バージョンの行の表示（`CFBundleShortVersionString`（`CFBundleVersion`））。
nonisolated enum AppVersionText {
    /// 「1.0.0（1）」の形にする。ビルド番号が無ければバージョンだけ、バージョンが無ければ空
    /// - Parameters:
    ///   - shortVersion: `CFBundleShortVersionString`
    ///   - build: `CFBundleVersion`
    static func make(shortVersion: String?, build: String?) -> String {
        guard let shortVersion, !shortVersion.isEmpty else {
            return ""
        }
        guard let build, !build.isEmpty else {
            return shortVersion
        }
        return "\(shortVersion)（\(build)）"
    }

    /// アプリの Info.plist から作る
    static func make(bundle: Bundle) -> String {
        make(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
