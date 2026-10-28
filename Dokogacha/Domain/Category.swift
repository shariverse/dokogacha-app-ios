//
//  Category.swift
//  Dokogacha
//
//  候補の場所のカテゴリ（02 の §3.1「カテゴリの対応表」）と、MapKit のカテゴリからの対応。
//

import MapKit

/// 候補の場所のカテゴリ（9 種）。
///
/// `rawValue` は Firestore の `candidates.category`・`pastIdeas.category` に保存する値で、
/// `docs/spec/design/tokens.json` の `color.category` の鍵と同じ（`DesignTokensTests` で突き合わせる）。
/// TypeScript 側の `backend/functions/src/domain/category.ts` も同じ値を持つ。
///
/// 表示名・色・アイコンは見た目のトークンなので、正本は `DesignSystem` の `DGCategoryStyle` に置き、
/// ここでは持たない（`DGCategoryStyle.of(_:)` で引く）。
///
/// 型の名前を `Category` にしないのは、Objective-C のランタイムの `Category`（`objc_category` のポインタ）と
/// テストのファイルなどで名前がぶつかるため。
nonisolated enum PlaceCategory: String, CaseIterable, Codable, Sendable {
    /// 水族館
    case aquarium
    /// 自然
    case nature
    /// アート・美術館
    case art
    /// グルメ
    case food
    /// アクティビティ
    case activity
    /// テーマパーク
    case park
    /// 街歩き（対応するものが無いときの既定）
    case town
    /// 寺社（MapKit に該当するカテゴリが無いので、場所名から判定する）
    case shrine
    /// 海
    case sea

    /// 対応しきれないときのカテゴリ（02 の §3.1「対応しきれない場合は town にする」）
    static let fallback: Self = .town

    /// 場所名にこれを含むと寺社とみなす語（02 の §3.1 の `shrine` の行）
    static let shrineNameKeywords = ["神社", "寺", "宮"]

    /// MapKit の検索結果から、アプリのカテゴリを決める。
    ///
    /// 02 の §3.1 の対応表どおりに、まず MapKit のカテゴリで決める。対応表に無い（または取れない）ときだけ、
    /// 場所名に「神社」「寺」「宮」を含めば寺社、それ以外は街歩きにする。
    /// MapKit のカテゴリが付いていればそちらを優先するのは、「宮」を含む美術館・駅などを寺社にしないため。
    /// 投稿の確認（S-09）で手で選び直せるので、ここでは迷ったら既定に寄せる。
    /// - Parameters:
    ///   - pointOfInterestCategory: `MKMapItem.pointOfInterestCategory`（無ければ nil）
    ///   - placeName: 場所名（`MKMapItem.name`）
    /// - Returns: アプリのカテゴリ
    static func classify(pointOfInterestCategory: MKPointOfInterestCategory?, placeName: String) -> Self {
        if let pointOfInterestCategory, let category = mapped(from: pointOfInterestCategory) {
            return category
        }
        if shrineNameKeywords.contains(where: { placeName.contains($0) }) {
            return .shrine
        }
        return fallback
    }

    /// 02 の §3.1 の対応表の 1 行を引く。表に無い MapKit のカテゴリは nil。
    ///
    /// `MKPointOfInterestCategory` を辞書の鍵にした `static let` にしないのは、型が `Sendable` かどうかに
    /// 依存させず、`nonisolated` のまま共有できるようにするため（switch なら保存しない）。
    /// - Parameter pointOfInterestCategory: MapKit のカテゴリ
    /// - Returns: 対応するアプリのカテゴリ。表に無ければ nil
    static func mapped(from pointOfInterestCategory: MKPointOfInterestCategory) -> Self? {
        switch pointOfInterestCategory {
        case .aquarium:
            .aquarium
        case .park, .nationalPark, .campground:
            .nature
        case .museum:
            .art
        case .restaurant, .cafe, .bakery, .foodMarket, .brewery, .winery:
            .food
        case .marina, .stadium, .fitnessCenter:
            .activity
        case .amusementPark, .zoo:
            .park
        case .store, .nightlife:
            .town
        case .beach:
            .sea
        default:
            nil
        }
    }
}
