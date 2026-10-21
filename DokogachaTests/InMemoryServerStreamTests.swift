//
//  InMemoryServerStreamTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 擬似のサーバーの購読（変更を流す・cancel で外れる）と、直接の書き込みのルールを確かめる
struct InMemoryServerStreamTests {
    @Test
    func activeRoomsStreamsChanges() async throws {
        let server = InMemoryServerTests.makeServer()
        try await InMemoryServerTests.addUser(server, "owner")
        var iterator = server.activeRooms(userID: "owner").makeAsyncIterator()
        #expect(await iterator.next() == .value([]))

        let room = try await server.createRoom(InMemoryServerTests.simpleRoom())
        #expect(await iterator.next()?.value?.map(\.id) == [room.roomId])

        // 終了したルームはホームに出ない
        server.rooms[room.roomId]?.room.status = .closed
        #expect(await iterator.next() == .value([]))
    }

    @Test
    func membersStreamFollowsJoinAndFailsAfterRemoval() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        try await InMemoryServerTests.addUser(server, "guest")
        _ = try await InMemoryServerTests.join(server, "guest", code: room.inviteCode)

        // guest の端末として購読する
        server.signedInUserID = "guest"
        var iterator = server.members(roomID: room.roomId).makeAsyncIterator()
        // 参加の日時が同じ（時計を止めている）ので、並びは見ない
        #expect(Set(await iterator.next()?.value?.map(\.id) ?? []) == ["owner", "guest"])

        // 作成者に削除されたら、読めなくなって購読が終わる（Firestore のリスナーと同じ）
        try await server.perform(as: "owner") {
            try await server.removeMember(RemoveMemberRequest(roomId: room.roomId, memberId: "guest"))
        }
        #expect(await iterator.next() == .failure(InMemoryServer.permissionDenied))
        #expect(await iterator.next() == nil)
    }

    @Test
    func cancellingRemovesSubscriber() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        let stream = server.candidates(roomID: room.roomId)
        #expect(server.subscriberCount == 1)
        let task = Task {
            for await _ in stream {}
        }
        task.cancel()
        await task.value
        #expect(await AsyncTestSupport.eventually { server.subscriberCount == 0 })
    }

    @Test
    func nonMemberCannotReadRoom() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        server.signedInUserID = "stranger"
        var iterator = server.room(id: room.roomId).makeAsyncIterator()
        #expect(await iterator.next() == .failure(InMemoryServer.permissionDenied))
    }

    /// 無いルームの購読は、本番のルールと同じく permission-denied で終わる（nil は流さない）
    @Test
    func missingRoomFailsLikeSecurityRules() async throws {
        let server = InMemoryServerTests.makeServer()
        var missing = server.room(id: "missing").makeAsyncIterator()
        #expect(await missing.next() == .failure(InMemoryServer.permissionDenied))
        #expect(await missing.next() == nil)
    }

    /// 準備OKは自分の分だけ、open・unlocked のときだけ（05 の §4 のルール）
    @Test
    func readyIsOwnAndOnlyWhileInteractive() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        try await server.setReady(true, roomID: room.roomId, userID: "owner")
        #expect(server.rooms[room.roomId]?.members["owner"]?.ready == true)
        #expect(server.rooms[room.roomId]?.room.readyCount == 1)

        try await InMemoryServerTests.addUser(server, "guest")
        _ = try await InMemoryServerTests.join(server, "guest", code: room.inviteCode)
        await #expect(throws: InMemoryServer.permissionDenied) {
            try await server.setReady(true, roomID: room.roomId, userID: "guest")
        }
        server.rooms[room.roomId]?.room.status = .drawn
        await #expect(throws: InMemoryServer.permissionDenied) {
            try await server.setReady(false, roomID: room.roomId, userID: "owner")
        }
    }

    /// いいねは他人の候補にだけ付けられ、もう一度で外れる（F-20）
    @Test
    func likeOnlyOthersCandidates() async throws {
        let server = InMemoryServerTests.makeServer()
        let room = try await InMemoryServerTests.makeRoom(server)
        server.rooms[room.roomId]?.candidates["mine"] = InMemoryServerTests.candidate(postedBy: "owner", likedBy: [])
        server.rooms[room.roomId]?.candidates["theirs"] = InMemoryServerTests.candidate(postedBy: "guest", likedBy: ["x"])

        try await server.setLike(true, candidateID: "theirs", roomID: room.roomId, userID: "owner")
        try await server.setLike(true, candidateID: "theirs", roomID: room.roomId, userID: "owner")
        #expect(server.rooms[room.roomId]?.candidates["theirs"]?.likedBy == ["x", "owner"])
        try await server.setLike(false, candidateID: "theirs", roomID: room.roomId, userID: "owner")
        #expect(server.rooms[room.roomId]?.candidates["theirs"]?.likedBy == ["x"])

        // いいねし直しても並びを変えない（`arrayUnion` は既にある値の位置を変えない）
        try await server.setLike(true, candidateID: "theirs", roomID: room.roomId, userID: "owner")
        server.rooms[room.roomId]?.candidates["theirs"]?.likedBy.append("y")
        try await server.setLike(true, candidateID: "theirs", roomID: room.roomId, userID: "owner")
        #expect(server.rooms[room.roomId]?.candidates["theirs"]?.likedBy == ["x", "owner", "y"])

        await #expect(throws: InMemoryServer.permissionDenied) {
            try await server.setLike(true, candidateID: "mine", roomID: room.roomId, userID: "owner")
        }
    }

    @Test
    func markSeenUsesServerClock() async throws {
        var now = InMemoryServerTests.now
        let server = InMemoryServer(clock: { now }, signedInUserID: "owner")
        try await InMemoryServerTests.addUser(server, "owner")
        let room = try await server.createRoom(InMemoryServerTests.simpleRoom())
        now = now.addingTimeInterval(600)
        try await server.markSeen(roomID: room.roomId, userID: "owner")
        #expect(server.rooms[room.roomId]?.members["owner"]?.lastSeenAt == now)
    }

    @Test
    func profileStreamShowsOwnProfileOnly() async throws {
        let server = InMemoryServerTests.makeServer()
        var mine = server.profile(userID: "owner").makeAsyncIterator()
        #expect(await mine.next() == .value(nil))
        _ = try await server.saveDisplayName("たくみ")
        guard case let .value(profile?) = try #require(await mine.next()) else {
            Issue.record("プロフィールが流れていない")
            return
        }
        #expect(profile.displayName == "たくみ")
        var others = server.profile(userID: "guest").makeAsyncIterator()
        #expect(await others.next() == .failure(InMemoryServer.permissionDenied))
    }
}
