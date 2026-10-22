//
//  InMemoryServerProfileSyncTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーで表示名を変えると、backend の `onUserProfileUpdate` と同じく参加中のルームの複製が変わることを確かめる
/// （backend の `test/emulator/profile-sync.test.ts` と同じ観点）
struct InMemoryServerProfileSyncTests {
    /// 購読に流れた回数を数える箱（Task の中から数を足すため）
    final class Counter {
        var value = 0
    }

    /// 自分
    private static let me = DemoScenario.myUserID

    /// 参加中のすべてのルームのメンバーと、自分の候補の投稿者名を新しい名前にする。ほかの人の複製は変えない
    @Test
    func renameUpdatesCopiesInJoinedRooms() async throws {
        let server = InMemoryServer.demo(.severalRooms)
        _ = try await server.saveProfile(SaveProfileRequest(displayName: " ゆい "))

        let roomIDs = [DemoScenario.roomID, DemoScenario.unlockedRoomID, DemoScenario.othersRoomID]
        for roomID in roomIDs {
            let record = try #require(server.rooms[roomID])
            #expect(record.members[Self.me]?.displayName == "ゆい")
            #expect(record.members["demo-haruka"]?.displayName == "はるか")
            for candidate in record.candidates.values where candidate.postedBy == Self.me {
                #expect(candidate.postedByName == "ゆい")
            }
        }
        let room = try #require(server.rooms[DemoScenario.roomID])
        #expect(room.candidates["demo-candidate-3"]?.postedByName == "ゆい")
        #expect(room.candidates["demo-candidate-1"]?.postedByName == "はるか")
    }

    /// 退出したルームの複製は変えない（参加中のルームだけ）
    @Test
    func renameSkipsRoomsAlreadyLeft() async throws {
        let server = InMemoryServer.demo(.severalRooms)
        try await server.leaveRoom(RoomRequest(roomId: DemoScenario.othersRoomID))
        // 退出の後に残ったメンバーのドキュメントの代わりに、前の名前の複製を入れておく
        server.rooms[DemoScenario.othersRoomID]?.members[Self.me] = server.rooms[DemoScenario.roomID]?.members[Self.me]

        _ = try await server.saveProfile(SaveProfileRequest(displayName: "ゆい"))
        #expect(server.rooms[DemoScenario.othersRoomID]?.members[Self.me]?.displayName == "たくみ")
        #expect(server.rooms[DemoScenario.roomID]?.members[Self.me]?.displayName == "ゆい")
    }

    /// 自分が広告非表示の購入者なら、購入者の表示名も変える
    @Test
    func renameUpdatesAdFreeSponsor() async throws {
        let server = InMemoryServer.demo(.oneRoom)
        server.rooms[DemoScenario.roomID]?.room.adFreeSponsor = AdFreeSponsor(uid: Self.me, displayName: "たくみ")
        _ = try await server.saveProfile(SaveProfileRequest(displayName: "ゆい"))
        #expect(server.rooms[DemoScenario.roomID]?.room.adFreeSponsor == AdFreeSponsor(uid: Self.me, displayName: "ゆい"))
    }

    /// アバターの色の複製がずれていたら、プロフィールの色にそろえる
    @Test
    func syncAlignsAvatarColor() throws {
        let server = InMemoryServer.demo(.oneRoom)
        server.rooms[DemoScenario.roomID]?.members[Self.me]?.avatarColor = "#000000"
        server.syncProfileCopies(of: Self.me)
        let color = try #require(server.users[Self.me]?.avatarColor)
        #expect(server.rooms[DemoScenario.roomID]?.members[Self.me]?.avatarColor == color)
    }

    /// すでに今の値なら何も変えない（購読に新しい値を流さない）
    @Test
    func syncIsIdempotent() async throws {
        let server = InMemoryServer.demo(.severalRooms)
        _ = try await server.saveProfile(SaveProfileRequest(displayName: "ゆい"))
        let before = server.rooms

        let updates = Counter()
        let stream = server.observe { $0.rooms }
        let counting = Task {
            for await _ in stream {
                updates.value += 1
            }
        }
        #expect(await AsyncTestSupport.eventually { updates.value == 1 })
        server.syncProfileCopies(of: Self.me)
        _ = try await server.saveProfile(SaveProfileRequest(displayName: "ゆい"))
        #expect(server.rooms == before)
        // 最初に流した値のほかに、新しい値を流していない
        await Task.yield()
        #expect(updates.value == 1)
        counting.cancel()
    }
}
