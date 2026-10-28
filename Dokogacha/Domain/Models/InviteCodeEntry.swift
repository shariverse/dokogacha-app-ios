//
//  InviteCodeEntry.swift
//  Dokogacha
//

import Foundation

/// 招待コードの索引（`inviteCodes/{code}`。05 の §3）。ドキュメントの ID が招待コード（ハイフンなし）。
///
/// Functions だけが読み書きする（アプリからは読めない）。擬似のサーバーと TypeScript 側の型をそろえるために置く。
nonisolated struct InviteCodeEntry: Codable, Sendable, Equatable {
    /// コードが指すルームの ID
    var roomId: String
    /// 発行した日時
    var createdAt: Date
}
