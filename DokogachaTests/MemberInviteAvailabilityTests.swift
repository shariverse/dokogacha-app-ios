//
//  MemberInviteAvailabilityTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// メンバーを招待できるか（`MemberInviteAvailability`。02 の §2.4 F-04 の参加条件）を、ルームの状態と人数の組み合わせで確かめる。
/// サーバー（`joinRoom` の `assertJoinable`）と同じく、状態を人数より先に見る。
struct MemberInviteAvailabilityTests {
    /// 1 ケース分（状態・人数・結果）
    struct Case: CustomTestStringConvertible, Sendable {
        let status: RoomStatus
        let memberCount: Int
        let expected: MemberInviteAvailability

        var testDescription: String {
            "\(status.rawValue)・\(memberCount)人 → \(expected)"
        }
    }

    nonisolated static let cases: [Case] = [
        // 参加できる状態で 20 人未満なら招待できる（作成者 1 人だけのときも）
        Case(status: .open, memberCount: 1, expected: .available),
        Case(status: .open, memberCount: 19, expected: .available),
        Case(status: .unlocked, memberCount: 4, expected: .available),
        // 20 人（以上）は満員
        Case(status: .open, memberCount: 20, expected: .full),
        Case(status: .unlocked, memberCount: 20, expected: .full),
        Case(status: .open, memberCount: 21, expected: .full),
        // 行き先が決まった・終了したルームは、人数によらず招待の入口を出さない（満員より先に見る）
        Case(status: .drawn, memberCount: 4, expected: .unavailable),
        Case(status: .drawn, memberCount: 20, expected: .unavailable),
        Case(status: .closed, memberCount: 4, expected: .unavailable)
    ]

    @Test(arguments: cases)
    func availability(_ testCase: Case) {
        let availability = MemberInviteAvailability.of(status: testCase.status, memberCount: testCase.memberCount)
        #expect(availability == testCase.expected)
        #expect(availability.isShown == (testCase.expected != .unavailable))
    }

    /// 上限は 02 の §9「1ルーム最大20人」（`DomainConstants.Limits.maxMembers`）を既定にし、渡せば替えられる
    @Test
    func limitDefaultsToMaxMembers() {
        #expect(DomainConstants.Limits.maxMembers == 20)
        #expect(MemberInviteAvailability.of(status: .open, memberCount: 3, maxMembers: 3) == .full)
        #expect(MemberInviteAvailability.of(status: .open, memberCount: 2, maxMembers: 3) == .available)
    }

    /// 招待できる状態は、参加できる状態（`open`・`unlocked`。擬似のサーバーの `joinRoom` の判定）と同じ
    @Test
    func invitableStatusesMatchJoinableStatuses() {
        #expect(MemberInviteAvailability.invitableStatuses == [.open, .unlocked])
        #expect(MemberInviteAvailability.invitableStatuses == InMemoryServer.joinableStatuses)
    }
}
