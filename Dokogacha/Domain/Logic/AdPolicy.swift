//
//  AdPolicy.swift
//  Dokogacha
//

import Foundation

/// 広告の判定で区別する画面（02 の F-50）。
///
/// バナーを出してよいのはホーム・ルーム・候補を追加の 3 つだけ。ほかの画面は、出さないことをはっきりさせるために並べる
nonisolated enum AdScreen: CaseIterable, Sendable {
    /// S-01 オンボーディング
    case onboarding
    /// S-02 ホーム
    case home
    /// S-03 ルーム作成
    case createRoom
    /// S-04 招待
    case invite
    /// S-07 ルーム
    case room
    /// S-08 候補を追加
    case addCandidate
    /// S-13 ガチャ
    case gacha
    /// S-14 結果
    case result
    /// S-15 設定
    case settings

    /// この画面にバナーを出してよいか（05 の §8 の `allowsAds`。ホーム・ルーム・候補を追加だけ）
    var allowsAds: Bool {
        switch self {
        case .home, .room, .addCandidate:
            true
        case .onboarding, .createRoom, .invite, .gacha, .result, .settings:
            false
        }
    }
}

/// バナー広告を出すかの判定（05 の §8 の `shouldShowAds`。02 の F-50・F-51）。
nonisolated enum AdDisplayPolicy {
    /// その画面にバナーを出すか。
    ///
    /// 1. 出してよい画面でなければ出さない（F-50）
    /// 2. 自分が広告非表示を買っていれば出さない（`users.adFree`。F-51「購入者本人は全画面で広告が消える」）
    /// 3. 開いているルームに購入者がいれば出さない（`rooms.adFreeSponsor`。F-51「そのルームの全メンバーの広告が消える」）。
    ///    ホームはルームを渡さないので、自分が買ったかだけで決まる（F-51「ホーム画面の広告は自分が購入者かだけで決める」）
    ///
    /// - Parameters:
    ///   - screen: 出そうとしている画面
    ///   - isAdFree: 自分が広告非表示を買ったか（いまは `users.adFree`。端末での購入の確認はタスク 37 で足す）
    ///   - room: 開いているルーム（ルーム・候補を追加のとき。ホームでは nil）
    static func shouldShowAds(screen: AdScreen, isAdFree: Bool, room: Room?) -> Bool {
        guard screen.allowsAds else {
            return false
        }
        if isAdFree {
            return false
        }
        if let room, room.adFreeSponsor != nil {
            return false
        }
        return true
    }
}

/// 起動のしかたごとの広告の扱い。
///
/// Unit テストのホストと `-uiTesting` では、SDK を初期化せず広告を読み込まない・ATT を尋ねない（ダイアログが画面を塞ぐ・ネットワークで揺らぐ）。
/// 撮影モードでは本物の広告を写さないよう、読み込まずに固定の見た目の枠（`DGAdPlaceholder`）を出す
nonisolated enum AdMode: Equatable, Sendable {
    /// 本物の広告を読み込む（`adUnitID` の広告ユニット）
    case live(adUnitID: String)
    /// 読み込まずに、バナーの場所に固定の見た目の枠を出す（撮影モード）
    case placeholder
    /// 何も出さない・読み込まない・ATT を尋ねない（テスト・広告ユニット ID の設定漏れ）
    case disabled

    /// 起動のしかたと Info.plist の広告ユニット ID から決める
    /// - Parameters:
    ///   - launch: 起動のしかた
    ///   - adUnitID: Info.plist の `DGBannerAdUnitID`（xcconfig の `DG_BANNER_AD_UNIT_ID`）。無い・空なら読み込まない
    static func make(launch: LaunchContext, adUnitID: String?) -> Self {
        if launch.isUnitTestHost || launch.isUITesting {
            return .disabled
        }
        if launch.isScreenshotDemo {
            return .placeholder
        }
        guard let adUnitID, !adUnitID.isEmpty else {
            return .disabled
        }
        return .live(adUnitID: adUnitID)
    }

    /// SDK を初期化して広告を読み込むか
    var loadsAds: Bool {
        if case .live = self {
            return true
        }
        return false
    }
}

/// ATT（App Tracking Transparency）の許可の状態（`ATTrackingManager.AuthorizationStatus` を写した値）
nonisolated enum AdTrackingStatus: Equatable, Sendable {
    /// まだ尋ねていない
    case notDetermined
    /// 端末の制限で許可できない（ペアレンタルコントロールなど）
    case restricted
    /// 拒否された
    case denied
    /// 許可された
    case authorized
}

/// ATT を尋ねる時機と、広告のリクエストの決め方（02 の F-50「初回にルームに入ったあと」「拒否された場合は非パーソナライズ広告」）。
nonisolated enum AdTrackingPolicy {
    /// 非パーソナライズ広告を求めるときに、リクエストの追加のパラメータ（`Extras.additionalParameters`）に入れる鍵と値
    static let nonPersonalizedParameters = ["npa": "1"]

    /// ルームに入ったときに ATT を尋ねるか。
    ///
    /// 広告を読み込むときだけ・まだ尋ねていないときだけ（初めてルームに入ったときに当たる）。広告非表示を買った人には広告を出さないので尋ねない
    /// - Parameters:
    ///   - mode: 起動のしかたごとの広告の扱い
    ///   - status: いまの ATT の状態
    ///   - isAdFree: 自分が広告非表示を買ったか
    static func shouldRequestAuthorization(mode: AdMode, status: AdTrackingStatus, isAdFree: Bool) -> Bool {
        mode.loadsAds && status == .notDetermined && !isAdFree
    }

    /// 広告のリクエストに足すパラメータ。許可された人だけパーソナライズし、それ以外（未回答・制限・拒否）は非パーソナライズにする
    /// - Parameter status: いまの ATT の状態
    static func requestParameters(status: AdTrackingStatus) -> [String: String] {
        status == .authorized ? [:] : nonPersonalizedParameters
    }
}
