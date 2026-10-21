//
//  DGCategoryStyle+PlaceCategory.swift
//  Dokogacha
//
//  アプリのカテゴリ（`Domain/Category.swift` の `PlaceCategory`）から、カテゴリタイルの見た目を引く。
//

import SwiftUI

nonisolated extension DGCategoryStyle {
    /// カテゴリの表示名・色・アイコンを返す。
    ///
    /// 表示名とアイコン名の正本はここ（`DGCategoryStyle`。tokens.json の `color.category` の写し）で、
    /// `PlaceCategory` は保存する値と MapKit からの対応だけを持つ。画面はこの関数で見た目を引く。
    /// switch で全件を書くので、カテゴリを足したのに見た目を書き忘れるとビルドが通らない。
    /// - Parameter category: アプリのカテゴリ
    /// - Returns: そのカテゴリのタイルの見た目
    static func of(_ category: PlaceCategory) -> Self {
        switch category {
        case .aquarium: .aquarium
        case .nature: .nature
        case .art: .art
        case .food: .food
        case .activity: .activity
        case .park: .park
        case .town: .town
        case .shrine: .shrine
        case .sea: .sea
        }
    }
}
