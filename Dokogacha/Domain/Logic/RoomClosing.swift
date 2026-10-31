//
//  RoomClosing.swift
//  Dokogacha
//

import Foundation

/// ルームの終了（02 の §6.5 F-44）と、終了したときの過去のアイデア（F-13）の判定。
///
/// backend の `functions/src/close/logic.ts`（`decideClose`・`planPastIdeas`）と同じ規則。
/// 画面（S-14 の「この行き先で決定」を出すか）と、擬似のサーバー（`InMemoryServer+Close.swift`）が使う。
/// 抽選から 7 日の自動の終了はサーバーのスケジュール（`autoCloseRooms`）だけが判定するので、ここには置かない。
nonisolated enum RoomClosing {
    /// S-14 の下部に出すもの（03 の S-14 の 6）
    enum Footer: Equatable, Sendable {
        /// 作成者に「この行き先で決定」を出す
        case decide
        /// 作成者以外に「作成者が決定するとルームが終了します」を出す
        case waitingForOwner
        /// 何も出さない（`closed` の閲覧のみ・引き直しが可決して `unlocked` に戻ったなど）
        case hidden
    }

    /// S-14 の下部に出すもの（`drawn` のときだけ。作成者かどうかで変える）
    /// - Parameters:
    ///   - room: ルーム
    ///   - userID: 自分の uid
    static func footer(for room: Room, userID: String) -> Footer {
        guard room.status == .drawn else {
            return .hidden
        }
        return room.ownerId == userID ? .decide : .waitingForOwner
    }

    /// `closeRoom` の状態の判定の結果（backend の `CloseDecision` と、失敗の理由）
    enum Decision: Equatable, Sendable {
        /// 終了する
        case close
        /// もう終了している（何も書かずに成功する。二度押し・自動の終了と重なった）
        case alreadyClosed
        /// 終了できない（理由）
        case reject(AppError.Reason)
    }

    /// 作成者の `closeRoom` で、今の状態と終了の意図を突き合わせる（backend の `decideClose` の 3 つ目の確認。メンバー・作成者の確認は呼ぶ側）。
    ///
    /// - `closed`: どちらの意図でも `alreadyClosed`
    /// - `decide`（S-14 の「この行き先で決定」）: `drawn` だけ終了する。`open`・`unlocked` は `room-not-drawn`
    /// - `endEarly`（S-12 の「ルームを終了する」）: `open`・`unlocked` だけ終了する。`drawn` は `room-already-decided`
    ///   （確認の間にほかの人がガチャを回したとき。途中でやめるつもりの操作で、決定と同じ終了にしない）
    /// - Parameters:
    ///   - status: ルームの今の状態
    ///   - reason: 終了の意図
    static func decision(status: RoomStatus, reason: CloseRoomRequest.Reason) -> Decision {
        switch (status, reason) {
        case (.closed, _):
            .alreadyClosed
        case (.drawn, .decide), (.open, .endEarly), (.unlocked, .endEarly):
            .close
        case (.open, .decide), (.unlocked, .decide):
            .reject(.roomNotDrawn)
        case (.drawn, .endEarly):
            .reject(.roomAlreadyDecided)
        }
    }

    /// 登録する過去のアイデア 1 件（backend の `PastIdeaWrite`）
    struct PastIdeaWrite: Equatable, Sendable {
        /// 登録するメンバーの uid
        let userID: String
        /// ドキュメントの ID（`pastIdeaID(roomID:candidateID:)`）
        let ideaID: String
        /// 過去のアイデア
        let idea: PastIdea
    }

    /// 過去のアイデアのドキュメントの ID（backend の `pastIdeaId`）。元のルームと候補から決まり、登録をやり直しても重ねて作らない
    static func pastIdeaID(roomID: String, candidateID: String) -> String {
        "\(roomID)_\(candidateID)"
    }

    /// 終了したルームに、行き先（今の当選）があるか（backend の `hasDecidedWinner`。過去のアイデアを登録するか。Discussion #155 の Q4）。
    ///
    /// 当選の ID があり、引き直しで外した候補に入っていなければ true。抽選の前に途中で終了した・アカウントの削除で終了した
    /// `open`・`unlocked` のルーム（当選が無い）と、引き直しが可決して `unlocked` に戻ったまま終了したルーム（前の当選は外した候補）は false
    static func hasDecidedWinner(_ room: Room) -> Bool {
        guard let winner = room.winnerCandidateId, !winner.isEmpty else {
            return false
        }
        return !room.excludedCandidateIds.contains(winner)
    }

    /// 終了したルームの、当選しなかった候補を、終了したときの各メンバーの過去のアイデアにする（backend の `planPastIdeas`）。
    /// 行き先が決まらないまま終了したルーム（`hasDecidedWinner` が false）は、何も登録しない。
    ///
    /// 当選（`winnerCandidateId`）以外のすべて（引き直しで外れた前の当選・自分以外の投稿を含む。02 の §3.4）を、
    /// `memberIds`（重なりは 1 回）の各メンバーに登録する。並び順は「メンバー（`memberIds` の順）→ 候補の ID」。
    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - room: 終了したルーム（`closedAt` が無ければ `closedAt` の引数を使う）
    ///   - candidates: ルームの候補（鍵は候補の ID）
    ///   - closedAt: 終了の日時
    static func pastIdeas(roomID: String, room: Room, candidates: [String: Candidate], closedAt: Date) -> [PastIdeaWrite] {
        guard hasDecidedWinner(room) else {
            return []
        }
        let winnerName = room.winnerCandidateId.flatMap { candidates[$0]?.place.name } ?? ""
        let ideas = candidates
            .filter { $0.key != room.winnerCandidateId }
            .sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
            .map { candidateID, candidate in
                (
                    ideaID: pastIdeaID(roomID: roomID, candidateID: candidateID),
                    idea: PastIdea(
                        sourceRoomId: roomID,
                        sourceRoomName: room.name,
                        sourceClosedAt: room.closedAt ?? closedAt,
                        sourceWinnerName: winnerName,
                        place: candidate.place,
                        category: candidate.category,
                        prevLikeCount: candidate.likedBy.count
                    )
                )
            }
        var seen: Set<String> = []
        let members = room.memberIds.filter { seen.insert($0).inserted }
        return members.flatMap { userID in
            ideas.map { PastIdeaWrite(userID: userID, ideaID: $0.ideaID, idea: $0.idea) }
        }
    }
}
