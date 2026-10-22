//
//  InMemoryServer+Draw.swift
//  Dokogacha
//
//  擬似のサーバーの抽選の Callable（backend の `draw/service.ts` の `drawGacha`）。
//  backend の `draw/logic.ts` の `decideDraw` と同じ順で検証し、同じ理由で失敗する（`InMemoryServerDrawTests` で確かめる）。
//  当選は `GachaDraw`（backend の `domain/draw.ts` と同じ式）で、乱数は注入した `randomIndex` で選ぶ。
//  抽選の後の通知（`onRoomDrawn`）は送らない（擬似のサーバーを使う UI テスト・撮影モードでは通知を使わない。`PushNotificationPolicy`）。
//

import Foundation

extension InMemoryServer {
    /// この端末（サインインしている人）からガチャを回す（`FunctionsClient`）
    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
        try drawGacha(request, by: signedInUserID)
    }

    /// ガチャを回す（backend の `drawGacha`）。呼んだ人の uid を `callerID` で受け取る（ほかのメンバーの端末 `Device` からも呼ぶ）。
    ///
    /// 入力の検証 → ルーム → メンバーか → 状態（`drawn` で抽選の ID があればその結果を返す・`closed` は `room-already-decided`・
    /// `open` は `room-not-unlocked`）→ 数え直した準備OKで解禁の条件を満たすか（`rejudgeUnlock` と同じ規則。満たさなければ `room-not-unlocked`）
    /// → 除外した候補を外して抽選（0 件なら `no-candidates`）の順に確かめ、抽選の記録を作ってルームを `drawn` にする。
    /// 擬似のサーバーは 1 つの呼び出しを最後まで続けて処理するので、同時に呼んでも 2 回目は 1 回目の結果を受け取る（backend のトランザクションと同じ結果）
    func drawGacha(_ request: RoomRequest, by callerID: String?) throws -> DrawGachaResponse {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        guard var record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard let member = record.members[userID] else {
            throw Self.error(.notRoomMember)
        }
        if let previous = try previousDraw(of: record) {
            return previous
        }

        let candidates = record.candidates.map { OddsInput(id: $0.key, likeCount: $0.value.likedBy.count) }
        let excluded = Set(record.room.excludedCandidateIds)
        guard !GachaDraw.entries(of: candidates, mode: record.room.settings.likeMode, excluding: excluded).isEmpty else {
            throw Self.error(.noCandidates)
        }
        guard let outcome = GachaDraw.draw(
            candidates, mode: record.room.settings.likeMode, excluding: excluded, randomIndex: randomIndex
        ) else {
            throw Self.error(.internal)
        }
        let now = clock()
        let drawID = makeID()
        record.draws[drawID] = Draw(
            candidateId: outcome.candidateID,
            probability: outcome.probability,
            weights: outcome.weights,
            drawnBy: userID,
            drawnByName: member.displayName,
            isReroll: !record.room.excludedCandidateIds.isEmpty,
            createdAt: now
        )
        record.room.status = .drawn
        record.room.currentDrawId = drawID
        record.room.winnerCandidateId = outcome.candidateID
        record.room.drawnAt = now
        rooms[roomID] = record
        return DrawGachaResponse(drawId: drawID, candidateId: outcome.candidateID, alreadyDrawn: false)
    }

    /// 回してよい状態か確かめる（backend の `decideDraw` の状態の判定）。
    ///
    /// - Returns: 先に誰かが回していれば（`drawn`）その結果。回してよければ nil
    /// - Throws: `room-already-decided`（`closed`・壊れた `drawn`）・`room-not-unlocked`（`open`・数え直すと未解禁の `unlocked`）
    private func previousDraw(of record: RoomRecord) throws -> DrawGachaResponse? {
        switch record.room.status {
        case .drawn:
            guard let drawID = record.room.currentDrawId, !drawID.isEmpty,
                  let winnerID = record.room.winnerCandidateId, !winnerID.isEmpty else {
                throw Self.error(.roomAlreadyDecided)
            }
            return DrawGachaResponse(drawId: drawID, candidateId: winnerID, alreadyDrawn: true)
        case .closed:
            throw Self.error(.roomAlreadyDecided)
        case .open:
            throw Self.error(.roomNotUnlocked)
        case .unlocked:
            var recounted = record
            rejudgeUnlock(&recounted)
            guard recounted.room.status == .unlocked else {
                throw Self.error(.roomNotUnlocked)
            }
            return nil
        }
    }
}
