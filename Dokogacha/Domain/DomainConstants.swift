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
        /// レア当選（F-42）の比の上限（02 の §6.3「当選確率 < 平均確率 × 0.85」の 0.85。これより下ならレア当選）
        static let rareWinRatio = 0.85
        /// レア当選の比を境目と比べるときの許容誤差（重み ÷ 合計 × 候補数の割り算の誤差で、0.85 ちょうどがレア当選に落ちないようにする）
        static let rareWinTolerance = 1e-9
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
        /// 招待リンクのスキーム（Universal Links は https だけ）
        static let scheme = "https"
        /// Web のドメイン（06 の §4 の仮決め `dokogacha.app`）
        static let domain = "dokogacha.app"
        /// 招待リンクのパスの前置き（`https://dokogacha.app/r/{招待コード}`。02 の §2.4）
        static let inviteLinkPathPrefix = "/r/"
        /// 招待リンクの OGP のタイトル（06 の §4 の仮決め「固定画像・固定タイトル」。05 の §7。アプリの画面には出さない）
        static let ogpTitle = "ドコガチャに招待されました"
        /// App Store のアプリのページ（02 の §6.3「App Store のURL（仮）」。行き先きっぷの共有画像に入れる。
        /// アプリの ID は App Store Connect でアプリを登録するまで決まらないので仮の値。登録したら差し替える）。
        /// 招待リンクのランディングページ（`backend/hosting/public/assets/landing.js` の `APP_STORE_URL`）も同じ値にする
        static let appStoreURL = "https://apps.apple.com/jp/app/id0000000000"
        /// 利用規約のページ（`backend/hosting/public/terms.html`。`firebase.json` の `cleanUrls` で拡張子なしの URL で開く）。
        /// 設定画面（S-15）の「利用規約」から開く
        static let termsURL = "\(scheme)://\(domain)/terms"
        /// プライバシーポリシーのページ（`backend/hosting/public/privacy.html`。`termsURL` と同じく拡張子なし）。
        /// 設定画面（S-15）の「プライバシーポリシー」から開く
        static let privacyPolicyURL = "\(scheme)://\(domain)/privacy"
        /// サポートのページ（`backend/hosting/public/support.html`。`termsURL` と同じく拡張子なし）。
        /// App Store の「サポート URL」（`AppStore/metadata/shared.json` の `supportUrl`）に同じ値を入れる。アプリの画面からは開かない
        static let supportURL = "\(scheme)://\(domain)/support"
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

    /// 場所検索の範囲（06 の §4 の仮決め「全国か地方を選ぶ。初めは全国」。Issue #131）。
    ///
    /// エリア（`SearchArea`）ごとの、`MKLocalSearch` の `region` にする矩形。位置情報は使わない。
    /// - 全国: 沖縄から北海道まで（北緯 23.8〜45.8 度・東経 122.5〜146.5 度）。矩形なので、日本の外（韓国・中国・台湾の一部と周りの海）も含む。
    ///   範囲の外の結果は出さないが、この矩形の中の日本の外の場所は結果に出うる（国で絞る API は無い。実機での確かめは #59）
    /// - 地方: 地方の都道府県の本土と主な島を囲む。矩形なので隣の地方の一部も入る（結果は都道府県で取り除く。`SearchArea.keeps`）。
    ///   矩形の外の離島（伊豆諸島・小笠原諸島・奄美群島など）は「全国」で探す
    nonisolated enum SearchRegion {
        /// 初めて S-08 を開いたときのエリア（選んだ後は端末に覚えたエリア。`SearchAreaStore`）
        static let initialArea = SearchArea.nationwide
        /// 全国
        static let nationwide = SearchBounds(minLatitude: 23.8, maxLatitude: 45.8, minLongitude: 122.5, maxLongitude: 146.5)
        /// 北海道（松前・奥尻島から宗谷岬・納沙布岬まで）
        static let hokkaido = SearchBounds(minLatitude: 41.3, maxLatitude: 45.6, minLongitude: 139.3, maxLongitude: 145.9)
        /// 東北（福島県の南端から大間崎まで、飛島から魹ヶ崎まで）
        static let tohoku = SearchBounds(minLatitude: 36.7, maxLatitude: 41.6, minLongitude: 139.1, maxLongitude: 142.1)
        /// 関東（房総半島の南端から栃木県の北端まで、群馬県の西端から犬吠埼まで）
        static let kanto = SearchBounds(minLatitude: 34.8, maxLatitude: 37.2, minLongitude: 138.4, maxLongitude: 140.9)
        /// 中部（渥美半島から新潟県の北端まで、敦賀から新潟市・熱海まで）。東西を県の端まで広げると、東京・埼玉・群馬と京都・大阪が入り、
        /// 結果がそちらで埋まる（「グルメ」で中部の県が 25 件中 4 件だった）ので狭めた。新潟県の北東の端（村上など）は「全国」で探す
        static let chubu = SearchBounds(minLatitude: 34.5, maxLatitude: 38.6, minLongitude: 136.0, maxLongitude: 139.2)
        /// 関西（潮岬から丹後半島まで、兵庫県の西端から志摩半島まで）
        static let kansai = SearchBounds(minLatitude: 33.4, maxLatitude: 35.8, minLongitude: 134.2, maxLongitude: 136.9)
        /// 中国・四国（足摺岬から隠岐まで、下関から蒲生田岬まで）
        static let chugokuShikoku = SearchBounds(minLatitude: 32.7, maxLatitude: 36.4, minLongitude: 130.8, maxLongitude: 134.9)
        /// 九州（屋久島から対馬まで、五島列島から大分県の東端まで）
        static let kyushu = SearchBounds(minLatitude: 29.9, maxLatitude: 34.8, minLongitude: 128.5, maxLongitude: 132.1)
        /// 沖縄（波照間島から伊平屋島まで、与那国島から大東諸島まで）
        static let okinawa = SearchBounds(minLatitude: 24.0, maxLatitude: 27.1, minLongitude: 122.9, maxLongitude: 131.4)
    }

    // アバターの色（06 の §4 の仮決め「ユーザー作成時にランダム。ルーム内の重複は許容」）は、
    // 候補の一覧と選び方を `AvatarPalette`（`Domain/Models/AvatarPalette.swift`）に置く。
}
