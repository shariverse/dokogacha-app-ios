//
//  Place.swift
//  Dokogacha
//

import Foundation

/// 候補の場所（`candidates.place`・`pastIdeas.place`。05 の §3）。
///
/// MapKit の検索結果（`MKMapItem`）から作る。MapKit の型を持たないのは、Firestore に保存でき、
/// TypeScript 側と同じ形にするため。
nonisolated struct Place: Codable, Sendable, Equatable, Hashable {
    /// 場所名
    var name: String
    /// エリアの表示（「東京・豊島区」の形）
    var area: String
    /// 緯度
    var latitude: Double
    /// 経度
    var longitude: Double
    /// `MKMapItem.identifier` の文字列（iOS 18 以降で取れたときだけ）
    var mapItemId: String?
}
