//
//  AccountDeletionTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// アカウントの削除（02 の §2.6 F-06）で、参加中のルームごとに何をするか（backend の `account/logic.test.ts` と同じケース）
struct AccountDeletionTests {
    /// 自分（`DemoScenario.myUserID`）が作成者で、はるか・そうた・みおがメンバーのデモのルーム
    static func room(_ status: RoomStatus) throws -> Room {
        var room = try #require(InMemoryServer.demo(.oneRoom).rooms[DemoScenario.roomID]?.room)
        room.status = status
        return room
    }

    /// 作成者は、終了していないルーム（open・unlocked・drawn）を終了して外れる
    @Test(arguments: [RoomStatus.open, .unlocked, .drawn])
    func ownerClosesUnclosedRoom(status: RoomStatus) throws {
        #expect(AccountDeletion.action(for: try Self.room(status), userID: DemoScenario.myUserID) == .closeAndLeave)
    }

    /// 作成者でも、終了したルームは退出と同じに外れる（終了し直さない）
    @Test
    func ownerLeavesClosedRoom() throws {
        #expect(AccountDeletion.action(for: try Self.room(.closed), userID: DemoScenario.myUserID) == .leave)
    }

    /// 作成者でないメンバーは、どの状態のルームでも退出と同じに外れる
    @Test(arguments: [RoomStatus.open, .unlocked, .drawn, .closed])
    func memberLeaves(status: RoomStatus) throws {
        #expect(AccountDeletion.action(for: try Self.room(status), userID: "demo-haruka") == .leave)
    }

    /// もうメンバーでない（前の呼び出しで外し終えた）ルームでは何もしない（作成者の ID が残っていても）
    @Test
    func nonMemberDoesNothing() throws {
        #expect(AccountDeletion.action(for: try Self.room(.open), userID: "carol") == .none)
        var departed = try Self.room(.closed)
        departed.memberIds.removeAll { $0 == DemoScenario.myUserID }
        #expect(AccountDeletion.action(for: departed, userID: DemoScenario.myUserID) == .none)
    }
}
