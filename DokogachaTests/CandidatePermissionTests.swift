//
//  CandidatePermissionTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 候補を削除・報告できるかの判定（02 の F-11・§3.5）。backend の `assertCanDeleteCandidate` と同じ規則
struct CandidatePermissionTests {
    /// 削除できるかの 1 ケース
    struct DeleteCase: Sendable, CustomTestStringConvertible {
        let postedBy: String
        let ownerID: String
        let status: RoomStatus
        let expected: Bool

        var testDescription: String {
            "投稿 \(postedBy)・作成者 \(ownerID)・\(status) → \(expected)"
        }
    }

    nonisolated static let deleteCases: [DeleteCase] = [
        // 投稿した本人は open・unlocked で削除できる
        DeleteCase(postedBy: "me", ownerID: "owner", status: .open, expected: true),
        DeleteCase(postedBy: "me", ownerID: "owner", status: .unlocked, expected: true),
        // 作成者は誰の候補でも削除できる
        DeleteCase(postedBy: "other", ownerID: "me", status: .open, expected: true),
        DeleteCase(postedBy: "other", ownerID: "me", status: .unlocked, expected: true),
        // 投稿した人でも作成者でもなければ削除できない
        DeleteCase(postedBy: "other", ownerID: "owner", status: .open, expected: false),
        // drawn・closed では、投稿した本人も作成者も削除できない
        DeleteCase(postedBy: "me", ownerID: "me", status: .drawn, expected: false),
        DeleteCase(postedBy: "me", ownerID: "owner", status: .closed, expected: false),
        DeleteCase(postedBy: "other", ownerID: "me", status: .drawn, expected: false)
    ]

    @Test(arguments: deleteCases)
    func canDelete(_ testCase: DeleteCase) {
        #expect(
            CandidatePermission.canDelete(
                postedBy: testCase.postedBy,
                ownerID: testCase.ownerID,
                roomStatus: testCase.status,
                userID: "me",
                isDrawn: false
            ) == testCase.expected
        )
    }

    /// ガチャで当選した候補は、引き直しの可決の後（unlocked）でも、投稿した本人も作成者も削除できない（backend の `candidate-drawn`）
    @Test
    func cannotDeleteDrawnCandidate() {
        for userID in ["me", "owner"] {
            #expect(!CandidatePermission.canDelete(
                postedBy: "me", ownerID: "owner", roomStatus: .unlocked, userID: userID, isDrawn: true
            ))
        }
    }

    /// 当選した候補は、今の当選と引き直しで除外した前の当選（backend の `isDrawnCandidate` のルームのフィールドの分）
    @Test
    func drawnCandidatesAreWinnerAndExcluded() {
        var room = DomainModelsTests.sampleRoom()
        room.winnerCandidateId = "c2"
        room.excludedCandidateIds = ["c1"]
        #expect(CandidatePermission.isDrawn(candidateID: "c1", in: room))
        #expect(CandidatePermission.isDrawn(candidateID: "c2", in: room))
        #expect(!CandidatePermission.isDrawn(candidateID: "c3", in: room))
    }

    /// 報告できるのは他人の投稿だけ
    @Test
    func canReportOnlyOthersPosts() {
        #expect(CandidatePermission.canReport(postedBy: "other", userID: "me"))
        #expect(!CandidatePermission.canReport(postedBy: "me", userID: "me"))
    }
}
