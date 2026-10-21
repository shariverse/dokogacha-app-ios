//
//  DomainConstants.swift
//  Dokogacha
//
//  02 の上限と、06 の §4 の仮決めの値を 1 か所にまとめた定数。
//  TypeScript 側は `backend/functions/src/domain/constants.ts` に同じ値を持つ。値を変えるときは両方を変える。
//

import Foundation

/// ドメインの定数。
///
/// 06 の §4 は「値は定数や Remote Config にまとめる」とあるが、Remote Config の SDK は導入していないので
/// （pbxproj を変えないため）、Swift と TypeScript の定数それぞれ 1 か所にまとめる。
nonisolated enum DomainConstants {
    /// 1 日の秒数
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    // MARK: 上限・入力の範囲（02）

    /// 人数・文字数・件数の上限と入力の範囲（02 の §1・§2・§3・§9）。
    nonisolated enum Limits {
        /// 1 ルームのメンバーの最大数（02 の §0・§2.4・§9）
        static let maxMembers = 20
        /// 表示名の文字数（02 の §1「1〜10文字、必須」）
        static let displayNameLength = 1...10
        /// ルーム名の文字数（02 の §2.2「1〜20文字。必須」）
        static let roomNameLength = 1...20
        /// 1 人あたりの投稿数の範囲（02 の §2.2「1〜10件」）
        static let postLimitRange = 1...10
        /// 1 人あたりの投稿数の初期値（02 の §2.2）
        static let defaultPostLimit = 3
        /// 1 ルームの候補の最大数（02 の §9「最大200件（20人×10件）」）
        static let maxCandidates = maxMembers * postLimitRange.upperBound
        /// ひとことの最大文字数（02 の §3.1「最大40文字」）
        static let noteMaxLength = 40
        /// 同じ場所とみなす距離（02 の §3.1「場所名が同じで座標が100m以内」。メートル）
        static let duplicateDistanceMeters: Double = 100
        /// 場所名の文字数（02 に無い。MapKit の検索結果の名前が収まる長さとして決めた。backend の `PLACE_NAME_LENGTH`）
        static let placeNameLength = 1...100
        /// エリアの表示の文字数（02 に無い。「東京・豊島区」の形。MapKit から取れないときは空。backend の `PLACE_AREA_LENGTH`）
        static let placeAreaLength = 0...50
        /// ひとことの文字数（02 の §3.1「最大40文字」。任意なので 0 文字も可。backend の `NOTE_LENGTH`）
        static let noteLength = 0...noteMaxLength
        /// 参考 URL の最大の長さ（UTF-16 のコード単位。02 に無い。backend の `CANDIDATE_URL_MAX_LENGTH`）
        static let candidateURLMaxLength = 2_048
        /// MapKit の識別子（`MKMapItem.identifier`）の最大の長さ（UTF-16 のコード単位。backend の `MAP_ITEM_ID_MAX_LENGTH`）
        static let mapItemIDMaxLength = 256
        /// 締切日時に選べる最も早い時刻の、今からの秒数（02 の §2.2「現在から1時間後」）
        static let deadlineEarliestFromNow: TimeInterval = 60 * 60
        /// 締切日時に選べる最も遅い時刻の、今からの秒数（02 の §2.2「30日後」）
        static let deadlineLatestFromNow: TimeInterval = 30 * secondsPerDay
        /// 締切日時の初期値の日数（02 の §2.2「3日後の21:00」の 3 日）
        static let defaultDeadlineDaysLater = 3
        /// 締切日時の初期値の時（02 の §2.2「3日後の21:00」の 21 時）
        static let defaultDeadlineHour = 21
        /// 1 ルームで引き直せる回数（02 の §6.4「ルームにつき1回まで」）
        static let rerollsPerRoom = 1
    }

    // MARK: 出やすさ（02 の §4.3）

    /// 出やすさのレベル（F-22）の境目。
    ///
    /// 02 の §4.3 は「比 = 表示% ÷ 平均%」を 1.2・0.85 と比べる。比を浮動小数点で作ると、`100 / 候補数` の割り算の誤差で
    /// 「1.2 ちょうど」が下に落ちうるので、比を百分率の整数（比 × 100 = 表示% × 候補数）で持って整数どうしで比べる。
    nonisolated enum Odds {
        /// 「出やすい」になる比の下限（百分率。比 ≥ 1.2）
        static let highRatioPercent = 120
        /// 「ふつう」になる比の下限（百分率。0.85 ≤ 比。これより下は「レア」）
        static let midRatioPercent = 85
    }

    // MARK: 仮決め（06 の §4）

    /// 広告非表示の買い切り（F-51）。
    nonisolated enum RemoveAds {
        /// StoreKit 2 の非消耗型アイテムの ID（02 の §7.2・05 の §1）
        static let productID = "remove_ads"
        /// 価格（円。06 の §4 の仮決め ¥480）。画面の表示は StoreKit の `displayPrice` を優先し、取れないときだけ使う
        static let priceYen = 480
    }

    /// Web（Hosting）と招待リンク（05 の §7）。
    nonisolated enum Web {
        /// Web のドメイン（06 の §4 の仮決め `dokogacha.app`）
        static let domain = "dokogacha.app"
        /// 招待リンクのパスの前置き（`https://dokogacha.app/r/{招待コード}`。02 の §2.4）
        static let inviteLinkPathPrefix = "/r/"
        /// 招待リンクの OGP のタイトル（06 の §4 の仮決め「固定画像・固定タイトル」。05 の §7。アプリの画面には出さない）
        static let ogpTitle = "ドコガチャに招待されました"
    }

    /// サーバーの時間の決まり（Functions のスケジュール・期限）。
    nonisolated enum Schedule {
        /// 引き直しの投票の期限（06 の §4 の仮決め 24 時間。秒）
        static let rerollVotingDuration: TimeInterval = secondsPerDay
        /// 抽選から自動で終了するまで（06 の §4 の仮決め 7 日。秒）
        static let autoCloseAfterDraw: TimeInterval = 7 * secondsPerDay
        /// 締切日時の解禁を判定する間隔（06 の §4 の仮決め 5 分。秒）
        static let deadlineCheckInterval: TimeInterval = 5 * 60
        /// 新しい候補のまとめ通知の時刻の時（06 の §4 の仮決め「1日1回 20:00 JST」）
        static let newCandidatesDigestHour = 20
        /// 新しい候補のまとめ通知の時刻の分
        static let newCandidatesDigestMinute = 0
        /// 新しい候補のまとめ通知を同じルームに送る 1 日あたりの最大回数
        static let newCandidatesDigestPerDay = 1
        /// スケジュールの時刻のタイムゾーン（JST）
        static let timeZoneIdentifier = "Asia/Tokyo"
    }

    /// 人気・過去のアイデアの基準（F-13・F-23）。
    nonisolated enum Popularity {
        /// 「前回惜しかった」バッジを付ける前回のいいね数の下限（06 の §4 の仮決め「前回のいいね3以上」）
        static let closeCallMinLikes = 3
        /// 「みんな推し」の割合（06 の §4 の仮決め「投稿者以外の6割以上」。いいね数 ≥ ceil(n' × 0.6)）
        static let popularRatio = 0.6
        /// 「みんな推し」に要るいいね数の下限（02 の §4.4「かついいね数 ≥ 2」）
        static let popularMinLikes = 2
        /// 「全員いいね」に要る、投稿者以外のメンバー数 n' の下限（02 の §4.4「かつ n' ≥ 2」）
        static let allLikedMinOtherMembers = 2
    }

    /// 場所検索の範囲（06 の §4 の仮決め「日本全国。`MKLocalSearch` の `region` は日本全体」）。
    ///
    /// 沖縄から北海道まで（北緯 24〜45.6 度・東経 123〜146 度）が入る矩形。位置情報は使わない。
    nonisolated enum SearchRegion {
        /// 中心の緯度
        static let centerLatitude = 34.8
        /// 中心の経度
        static let centerLongitude = 134.5
        /// 緯度の幅（度）
        static let latitudeDelta = 22.0
        /// 経度の幅（度）
        static let longitudeDelta = 24.0
    }

    // アバターの色（06 の §4 の仮決め「ユーザー作成時にランダム。ルーム内の重複は許容」）は、
    // 候補の一覧と選び方を `AvatarPalette`（`Domain/Models/AvatarPalette.swift`）に置く。
}
