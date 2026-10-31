//
//  Prefecture.swift
//  Dokogacha
//

import Foundation

/// 都道府県（S-08 の検索のエリアで、地方の次に選ぶ。03 の S-08 の 6・Issue #160）。
///
/// 検索の範囲（`bounds`）は都道府県を囲む矩形で、矩形に入る隣の都道府県の結果は `MKPlacemark.administrativeArea` で取り除く
/// （`SearchScope.keeps`）。英語の端末では MapKit が「Tokyo」の形で返すので、ローマ字の名前でも当てる（`named(_:)`）
nonisolated struct Prefecture: Hashable, Identifiable, Sendable {
    /// 都道府県コード（JIS X 0401。北海道 1〜沖縄 47。市区町村の団体コードの上 2 桁）
    let code: Int
    /// 名前（`MKPlacemark.administrativeArea` の「東京都」の形）
    let name: String
    /// ローマ字の名前（英語の端末で `MKPlacemark.administrativeArea` が返す「Tokyo」の形）
    let romanizedName: String
    /// 地方
    let area: SearchArea
    /// 検索の範囲（06 の §4 の仮決め。`all` の説明）
    let bounds: SearchBounds

    var id: Int {
        code
    }

    /// 「都」「府」「県」を外した名前（チップに出す。「北海道」はそのまま）
    var shortName: String {
        guard let last = name.last, "都府県".contains(last) else {
            return name
        }
        return String(name.dropLast())
    }

    /// - Parameters:
    ///   - code: 都道府県コード
    ///   - name: 名前（「東京都」）
    ///   - romanizedName: ローマ字の名前（「Tokyo」）
    ///   - area: 地方
    ///   - latitude: 検索の範囲の南北の緯度
    ///   - longitude: 検索の範囲の西東の経度
    init(
        _ code: Int,
        _ name: String,
        _ romanizedName: String,
        _ area: SearchArea,
        latitude: ClosedRange<Double>,
        longitude: ClosedRange<Double>
    ) {
        self.init(code, name, romanizedName, area, bounds: SearchBounds(latitude: latitude, longitude: longitude))
    }

    /// - Parameters:
    ///   - code: 都道府県コード
    ///   - name: 名前（「東京都」）
    ///   - romanizedName: ローマ字の名前（「Tokyo」）
    ///   - area: 地方
    ///   - bounds: 検索の範囲
    init(_ code: Int, _ name: String, _ romanizedName: String, _ area: SearchArea, bounds: SearchBounds) {
        self.code = code
        self.name = name
        self.romanizedName = romanizedName
        self.area = area
        self.bounds = bounds
    }
}

nonisolated extension Prefecture {
    /// 47 の都道府県（都道府県コードの順）。
    ///
    /// 検索の範囲は、都道府県の本土と近くの島を囲む矩形（06 の §4 の仮決め。北緯・東経の度。端の町が端に掛からないよう少し広げてある）。
    /// 遠くの離島（東京の伊豆諸島・小笠原諸島、鹿児島のトカラ列島・奄美群島など）は入れない。入れると矩形の中心が海の上に寄り、
    /// 本土の結果が減るため。離島の場所は、その市区町村を選ぶ（市区町村の範囲は MapKit で引く）か「全国」で探す。
    /// 北海道・沖縄は地方と同じ矩形（`DomainConstants.SearchRegion`）
    static let all: [Self] = [
        Self(1, "北海道", "Hokkaido", .hokkaido, bounds: DomainConstants.SearchRegion.hokkaido),
        Self(2, "青森県", "Aomori", .tohoku, latitude: 40.2...41.6, longitude: 139.8...141.7),
        Self(3, "岩手県", "Iwate", .tohoku, latitude: 38.7...40.5, longitude: 140.6...142.1),
        Self(4, "宮城県", "Miyagi", .tohoku, latitude: 37.7...39.05, longitude: 140.2...141.7),
        Self(5, "秋田県", "Akita", .tohoku, latitude: 38.8...40.6, longitude: 139.6...141.05),
        // 飛島を含む
        Self(6, "山形県", "Yamagata", .tohoku, latitude: 37.7...39.25, longitude: 139.5...140.7),
        Self(7, "福島県", "Fukushima", .tohoku, latitude: 36.7...38.05, longitude: 139.1...141.1),
        Self(8, "茨城県", "Ibaraki", .kanto, latitude: 35.7...37.0, longitude: 139.6...140.9),
        Self(9, "栃木県", "Tochigi", .kanto, latitude: 36.15...37.2, longitude: 139.3...140.35),
        Self(10, "群馬県", "Gunma", .kanto, latitude: 35.9...37.1, longitude: 138.35...139.7),
        Self(11, "埼玉県", "Saitama", .kanto, latitude: 35.7...36.35, longitude: 138.65...139.95),
        Self(12, "千葉県", "Chiba", .kanto, latitude: 34.8...36.2, longitude: 139.7...140.9),
        // 伊豆諸島・小笠原諸島は入れない（島の町村を選べば探せる）
        Self(13, "東京都", "Tokyo", .kanto, latitude: 35.5...35.9, longitude: 138.9...140.0),
        Self(14, "神奈川県", "Kanagawa", .kanto, latitude: 35.1...35.7, longitude: 138.9...139.85),
        // 佐渡を含む
        Self(15, "新潟県", "Niigata", .chubu, latitude: 36.7...38.6, longitude: 137.5...139.95),
        Self(16, "富山県", "Toyama", .chubu, latitude: 36.2...37.0, longitude: 136.7...137.8),
        Self(17, "石川県", "Ishikawa", .chubu, latitude: 36.0...37.6, longitude: 136.2...137.4),
        Self(18, "福井県", "Fukui", .chubu, latitude: 35.3...36.35, longitude: 135.4...136.9),
        Self(19, "山梨県", "Yamanashi", .chubu, latitude: 35.1...36.0, longitude: 138.1...139.2),
        Self(20, "長野県", "Nagano", .chubu, latitude: 35.15...37.1, longitude: 137.3...138.8),
        Self(21, "岐阜県", "Gifu", .chubu, latitude: 35.1...36.5, longitude: 136.2...137.7),
        Self(22, "静岡県", "Shizuoka", .chubu, latitude: 34.5...35.7, longitude: 137.4...139.2),
        Self(23, "愛知県", "Aichi", .chubu, latitude: 34.5...35.5, longitude: 136.6...137.9),
        Self(24, "三重県", "Mie", .kansai, latitude: 33.7...35.3, longitude: 135.8...137.05),
        Self(25, "滋賀県", "Shiga", .kansai, latitude: 34.7...35.8, longitude: 135.7...136.5),
        Self(26, "京都府", "Kyoto", .kansai, latitude: 34.65...35.8, longitude: 134.8...136.1),
        Self(27, "大阪府", "Osaka", .kansai, latitude: 34.2...35.1, longitude: 135.0...135.8),
        // 淡路島を含む
        Self(28, "兵庫県", "Hyogo", .kansai, latitude: 34.1...35.7, longitude: 134.2...135.5),
        Self(29, "奈良県", "Nara", .kansai, latitude: 33.8...34.8, longitude: 135.5...136.3),
        Self(30, "和歌山県", "Wakayama", .kansai, latitude: 33.4...34.4, longitude: 134.95...136.1),
        Self(31, "鳥取県", "Tottori", .chugokuShikoku, latitude: 35.0...35.7, longitude: 133.1...134.6),
        // 隠岐を含む
        Self(32, "島根県", "Shimane", .chugokuShikoku, latitude: 34.25...36.4, longitude: 131.6...133.4),
        Self(33, "岡山県", "Okayama", .chugokuShikoku, latitude: 34.25...35.4, longitude: 133.2...134.5),
        Self(34, "広島県", "Hiroshima", .chugokuShikoku, latitude: 34.0...35.2, longitude: 132.0...133.5),
        Self(35, "山口県", "Yamaguchi", .chugokuShikoku, latitude: 33.7...34.8, longitude: 130.7...132.5),
        Self(36, "徳島県", "Tokushima", .chugokuShikoku, latitude: 33.5...34.3, longitude: 133.6...134.9),
        // 小豆島を含む
        Self(37, "香川県", "Kagawa", .chugokuShikoku, latitude: 33.95...34.65, longitude: 133.4...134.5),
        Self(38, "愛媛県", "Ehime", .chugokuShikoku, latitude: 32.85...34.35, longitude: 131.9...133.7),
        Self(39, "高知県", "Kochi", .chugokuShikoku, latitude: 32.7...33.9, longitude: 132.4...134.4),
        Self(40, "福岡県", "Fukuoka", .kyushu, latitude: 32.95...34.05, longitude: 129.9...131.25),
        Self(41, "佐賀県", "Saga", .kyushu, latitude: 32.9...33.7, longitude: 129.7...130.6),
        // 対馬・壱岐・五島列島を含む
        Self(42, "長崎県", "Nagasaki", .kyushu, latitude: 32.5...34.75, longitude: 128.5...130.4),
        // 天草を含む
        Self(43, "熊本県", "Kumamoto", .kyushu, latitude: 32.0...33.2, longitude: 129.9...131.35),
        Self(44, "大分県", "Oita", .kyushu, latitude: 32.7...33.8, longitude: 130.8...132.1),
        Self(45, "宮崎県", "Miyazaki", .kyushu, latitude: 31.3...32.9, longitude: 130.7...131.9),
        // 甑島・種子島・屋久島を含み、トカラ列島・奄美群島は入れない（島の町村を選べば探せる）
        Self(46, "鹿児島県", "Kagoshima", .kyushu, latitude: 30.2...32.35, longitude: 129.6...131.2),
        Self(47, "沖縄県", "Okinawa", .okinawa, bounds: DomainConstants.SearchRegion.okinawa)
    ]

    /// 都道府県コードの都道府県。知らないコードなら nil
    static func code(_ code: Int) -> Self? {
        all.first { $0.code == code }
    }

    /// `MKPlacemark.administrativeArea` の値の都道府県。
    ///
    /// 「東京都」「東京」（「都」「府」「県」が無い）と、英語の端末の「Tokyo」「Tokyo-to」（ローマ字。大文字・長音記号を問わない）を当てる。
    /// 都道府県でない・無いときは nil
    /// - Parameter name: `MKPlacemark.administrativeArea` の値
    static func named(_ name: String?) -> Self? {
        guard let name = name.map(NameValidation.trimWhitespace), !name.isEmpty else {
            return nil
        }
        if let prefecture = all.first(where: { $0.name == name || $0.shortName == name }) {
            return prefecture
        }
        let key = romanizedKey(name)
        guard !key.isEmpty else {
            return nil
        }
        return all.first { romanizedKey($0.romanizedName) == key }
    }

    /// ローマ字の名前を比べる形（小文字にし、長音記号・「-ken」「Prefecture」などの後ろの語・記号を外す）
    private static func romanizedKey(_ name: String) -> String {
        var key = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        for suffix in [" prefecture", "-ken", "-fu", "-to", " ken", " fu", " to"] where key.hasSuffix(suffix) {
            key.removeLast(suffix.count)
            break
        }
        return String(key.filter { $0.isASCII && $0.isLetter })
    }
}
