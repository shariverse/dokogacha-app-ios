//
//  AccountDeletion.swift
//  Dokogacha
//

import Foundation

/// アカウントの削除（02 の §2.6 F-06）で、参加中のルームごとに何をするかの判定。
///
/// backend の `functions/src/account/logic.ts`（`accountDeletionActionOf`）と同じ規則。擬似のサーバー（`InMemoryServer+Account.swift`）が使う。
/// - 作成者で、まだ終了していないルーム（`open`・`unlocked`・`drawn`）: 終了（`closed`）して、本人をメンバーから外す
///   （02 の F-06「作成者だったルームは closed にする」。過去のアイデアは残るメンバーにだけ登録する）
/// - それ以外（作成者でないルーム・作成者でも終了済みのルーム）: 退出と同じに外す（02 の F-06「F-05 と同じ処理」）
/// - もうメンバーでないルーム: 何もしない（削除をやり直しても同じルームを二度書かない）
nonisolated enum AccountDeletion {
    /// 1 つのルームで行うこと
    enum Action: Equatable, Sendable {
        /// 何もしない（もうメンバーでない）
        case none
        /// 退出と同じに外す
        case leave
        /// 終了して外す（作成者のルーム）
        case closeAndLeave
    }

    /// アカウントを削除する人が、1 つのルームで何をするか
    /// - Parameters:
    ///   - room: ルーム
    ///   - userID: 削除する人
    static func action(for room: Room, userID: String) -> Action {
        guard room.memberIds.contains(userID) else {
            return .none
        }
        if room.ownerId == userID, room.status != .closed {
            return .closeAndLeave
        }
        return .leave
    }
}
