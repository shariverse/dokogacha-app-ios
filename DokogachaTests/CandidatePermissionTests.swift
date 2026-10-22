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
                userID: "me"
            ) == testCase.expected
        )
    }

    /// 報告できるのは他人の投稿だけ
    @Test
    func canReportOnlyOthersPosts() {
        #expect(CandidatePermission.canReport(postedBy: "other", userID: "me"))
        #expect(!CandidatePermission.canReport(postedBy: "me", userID: "me"))
    }
}
