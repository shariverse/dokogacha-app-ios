//
//  InMemoryServer+Report.swift
//  Dokogacha
//
//  擬似のサーバーの投稿の報告（backend の `reports/service.ts` の `reportCandidate`。02 の §3.5 F-14）。
//  backend と同じ順で検証し、同じ理由で失敗する（`InMemoryServerReportTests` で確かめる）。
//  backend は運営向けのメール（`mail`）も書くが、擬似のサーバーはメールを扱わないので報告だけを残す。
//

import Foundation

extension InMemoryServer {
    func reportCandidate(_ request: ReportCandidateRequest) async throws {
        try reportCandidate(request, by: signedInUserID)
    }

    /// 報告の鍵（backend の `reportDocumentId` の代わり。ルーム・候補・報告した人で 1 つ）
    static func reportKey(roomID: String, candidateID: String, reporterID: String) -> String {
        [roomID, candidateID, reporterID].joined(separator: "\u{0}")
    }

    /// 候補を報告する（backend の `reportCandidate`）。呼んだ人の uid を `callerID` で受け取る。
    ///
    /// 入力の検証 → ルーム（無ければ `room-not-found`）→ メンバーか（`not-room-member`）→ 候補（`candidate-not-found`）
    /// → 自分の投稿か（`cannot-report-own-candidate`。`CandidatePermission.canReport`）→ もう報告していれば何もしない（1 人 1 候補につき 1 回）。
    /// ルームの状態は問わない
    /// - Returns: 同じ人がこの候補をもう報告していたか（backend の `alreadyReported`）
    @discardableResult
    func reportCandidate(_ request: ReportCandidateRequest, by callerID: String?) throws -> Bool {
        let userID = try Self.requireCaller(callerID)
        let roomID = try Self.documentID(request.roomId)
        let candidateID = try Self.documentID(request.candidateId)
        guard let record = rooms[roomID] else {
            throw Self.error(.roomNotFound)
        }
        guard record.members[userID] != nil else {
            throw Self.error(.notRoomMember)
        }
        guard let candidate = record.candidates[candidateID] else {
            throw Self.error(.candidateNotFound)
        }
        guard CandidatePermission.canReport(postedBy: candidate.postedBy, userID: userID) else {
            throw Self.error(.cannotReportOwnCandidate)
        }
        let key = Self.reportKey(roomID: roomID, candidateID: candidateID, reporterID: userID)
        guard reports[key] == nil else {
            return true
        }
        reports[key] = CandidateReport(
            roomId: roomID,
            candidateId: candidateID,
            reporterId: userID,
            reason: request.reason,
            createdAt: clock()
        )
        return false
    }
}
