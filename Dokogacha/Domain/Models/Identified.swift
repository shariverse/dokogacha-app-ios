//
//  Identified.swift
//  Dokogacha
//

import Foundation

/// Firestore のドキュメントの ID と、ドキュメントの中身（モデル）の組。
///
/// モデル（`Room`・`Candidate` など）は Firestore のフィールドだけを持ち、ドキュメントの ID を持たない。
/// ID はドキュメントのパス（`rooms/{roomId}` など）にあってフィールドには無いので、モデルに入れると
/// `Codable` の形が Firestore の形（と TypeScript の型）からずれるため。画面で `ForEach` するときなどはこの型で包む。
///
/// `@dynamicMemberLookup` なので、`candidate.place.name` のように中身のプロパティをそのまま読める。
@dynamicMemberLookup
nonisolated struct Identified<Value>: Identifiable {
    /// ドキュメントの ID（`members` ではメンバーの uid、`inviteCodes` では招待コード）
    let id: String
    /// ドキュメントの中身
    var value: Value

    /// 中身のプロパティを読む
    subscript<Property>(dynamicMember keyPath: KeyPath<Value, Property>) -> Property {
        value[keyPath: keyPath]
    }
}

nonisolated extension Identified: Equatable where Value: Equatable {}
nonisolated extension Identified: Hashable where Value: Hashable {}
nonisolated extension Identified: Sendable where Value: Sendable {}
