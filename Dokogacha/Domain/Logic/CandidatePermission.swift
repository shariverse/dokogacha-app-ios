//
//  CandidatePermission.swift
//  Dokogacha
//

import Foundation

/// 候補に対して自分ができる操作の判定（02 の F-11・F-14）。
///
/// サーバー（`deleteCandidate` の `assertCanDeleteCandidate`・`isDrawnCandidate`）も同じ規則で確かめる。画面（S-10）は、ここで「できる」とした操作だけを出す
/// （出しても、画面を開いている間に状態が変わればサーバーに断られる。その文言は `AppError` が持つ）。
nonisolated enum CandidatePermission {
    /// 候補を追加・削除できるルームの状態（02 の §2.1「投稿・削除できるのは open/unlocked のときだけ」。backend の `CANDIDATE_EDITABLE_STATUSES`）
    static let editableStatuses: Set<RoomStatus> = [.open, .unlocked]

    /// 候補を削除できるか（02 の §3.2・F-11）。
    ///
    /// - 投稿した本人か、ルームの作成者（作成者は誰の候補でも削除できる）
    /// - ルームが `open`・`unlocked` のとき（`drawn`・`closed` では、作成者も削除できない）
    /// - ガチャで当選した候補でない（`isDrawn`。引き直しの可決の後の `unlocked` でも、前の当選は消せない）
    /// - Parameters:
    ///   - postedBy: 候補を投稿した人の uid
    ///   - ownerID: ルームの作成者の uid
    ///   - roomStatus: ルームの状態
    ///   - userID: 自分の uid
    ///   - isDrawn: ガチャで当選した候補か（`isDrawn(candidateID:in:)`。呼ぶ場所が渡し忘れないよう、既定の値を持たせない）
    static func canDelete(postedBy: String, ownerID: String, roomStatus: RoomStatus, userID: String, isDrawn: Bool) -> Bool {
        (postedBy == userID || ownerID == userID) && editableStatuses.contains(roomStatus) && !isDrawn
    }

    /// ガチャで当選した候補か（今の当選 `winnerCandidateId`・引き直しで除外した前の当選 `excludedCandidateIds`）。
    ///
    /// backend の `isDrawnCandidate` と同じ規則。backend は抽選の記録（`draws`）が指す候補も見るが、
    /// アプリは抽選の記録を購読しないので、ルームの 2 つのフィールドで判定する（前の当選はすべて除外に入るので、通常は同じ結果になる）
    /// - Parameters:
    ///   - candidateID: 候補の ID
    ///   - room: ルーム
    static func isDrawn(candidateID: String, in room: Room) -> Bool {
        room.winnerCandidateId == candidateID || room.excludedCandidateIds.contains(candidateID)
    }

    /// 候補を報告できるか（02 の §3.5・03 の S-10「他人の投稿なら『この投稿を報告』」）。自分の投稿は報告しない
    /// - Parameters:
    ///   - postedBy: 候補を投稿した人の uid
    ///   - userID: 自分の uid
    static func canReport(postedBy: String, userID: String) -> Bool {
        postedBy != userID
    }
}
