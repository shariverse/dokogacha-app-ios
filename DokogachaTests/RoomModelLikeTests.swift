//
//  RoomModelLikeTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// いいねの楽観的更新の確定（`OptimisticWrite`）を、届く値の順を決めて確かめる（`RoomModelTests` の続き）。
///
/// 押した候補の自分のいいねが一致したときだけ確定し、ほかの人のいいね・別の候補の変化・書き込みの前の古い値では表示を戻さないこと
extension RoomModelTests {
    /// 送っている途中に、ほかの人のいいね（押した候補・別の候補）が届いても楽観的な表示を消さない。
    /// 送り終えて押した候補の値が追いついたら確定し、出やすさは購読の値だけで作った表示と同じになる
    @Test
    func likeStaysOptimisticWhileOthersChangesArrive() async throws {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsLikes = true
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.likeTapped(Self.shrine)
        #expect(await AsyncTestSupport.eventually { repository.isHoldingLike })
        // みおが同じ候補と、別の候補（自分の江の島）にいいねする
        await server.device(of: "demo-mio").setLike(true, candidateID: Self.shrine, roomID: DemoScenario.roomID)
        await server.device(of: "demo-mio").setLike(true, candidateID: Self.mine, roomID: DemoScenario.roomID)
        #expect(await AsyncTestSupport.eventually { (try? Self.row(model, Self.mine))?.likers.count == 2 })
        let pending = try Self.row(model, Self.shrine)
        #expect(pending.likeStatus == .liked)
        #expect(Set(pending.likers.map(\.id)) == [DemoScenario.myUserID, "demo-mio"])
        #expect(model.pendingLikes[Self.shrine] != nil)

        repository.release()
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        // 購読の値だけで作った表示（別の Model）と同じ
        let reference = Self.makeModel(server)
        let observingReference = Task { await reference.observe() }
        defer { observingReference.cancel() }
        #expect(await Self.waitUntilLoaded(reference))
        #expect(model.rows.map { $0.odds?.displayPercent } == reference.rows.map { $0.odds?.displayPercent })
        #expect(model.rows.map(\.likeStatus) == reference.rows.map(\.likeStatus))
        #expect(try Self.row(model, Self.shrine).likers.count == 2)
    }

    /// 送り終えた後に、書き込みの前の古い候補の値が届いても表示を戻さない（ちらつかない）。押した候補の値が追いついたら確定する
    @Test
    func staleCandidatesAfterSendingDoNotRevertLike() async throws {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.feedCandidates()
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        repository.sendCandidates()
        #expect(await Self.waitUntilLoaded(model))
        let before = try #require(server.rooms[DemoScenario.roomID]?.candidates)

        await model.toggleLike(Self.shrine)
        #expect(model.pendingLikes[Self.shrine]?.isSent == true)
        // 書き込みの前の値に、別の候補の変化（みおが水族館にいいね）だけが入ったものが届く
        var stale = before
        stale[Self.aquarium]?.likedBy.append("demo-mio")
        repository.sendCandidates(stale)
        #expect(await AsyncTestSupport.eventually { (try? Self.row(model, Self.aquarium))?.likers.count == 3 })
        #expect(try Self.row(model, Self.shrine).likeStatus == .liked)
        #expect(model.pendingLikes[Self.shrine] != nil)

        repository.sendCandidates()
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        #expect(try Self.row(model, Self.shrine).likeStatus == .liked)
    }

    /// 送っている途中に書き込みが映った後、サーバーに拒まれて値が戻ったら、送り終えた時点で確定して戻った値を映す（逃げ道）
    @Test
    func rejectedLikeAfterReflectionShowsRevertedValue() async throws {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.feedCandidates()
        repository.holdsLikes = true
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        repository.sendCandidates()
        #expect(await Self.waitUntilLoaded(model))
        let before = try #require(server.rooms[DemoScenario.roomID]?.candidates)

        model.likeTapped(Self.shrine)
        #expect(await AsyncTestSupport.eventually { repository.isHoldingLike })
        // キャッシュに書いた値（自分のいいねあり）→ 拒まれて戻した値（いいねなし）の順に届く
        var reflected = before
        reflected[Self.shrine]?.likedBy = [DemoScenario.myUserID]
        repository.sendCandidates(reflected)
        #expect(await AsyncTestSupport.eventually { model.pendingLikes[Self.shrine]?.wasReflected == true })
        repository.sendCandidates(before)
        #expect(await AsyncTestSupport.eventually { model.candidates.first { $0.id == Self.shrine }?.likedBy.isEmpty == true })
        // 戻った値が届いても、送っている途中は楽観的な表示のまま
        #expect(try Self.row(model, Self.shrine).likeStatus == .liked)

        repository.release()
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        // 確定の後は購読の値（最後に届いた、戻した値）を映す
        #expect(try Self.row(model, Self.shrine).likeStatus == .notLiked)
    }
}
