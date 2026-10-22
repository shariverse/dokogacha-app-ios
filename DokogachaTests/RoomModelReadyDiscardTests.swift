//
//  RoomModelReadyDiscardTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 準備OK（F-30）を送っている途中に、ルームが準備OKを受け付けない状態になったら、楽観的な表示を捨てることを確かめる（PR #61 の持ち越し）。
///
/// 受け付けない状態では書き込みがルールで拒まれ、一致する値が届かないので、捨てないと送っている途中の表示のまま残る
struct RoomModelReadyDiscardTests {
    /// 送っている途中にルームが drawn・closed になったら、楽観的な準備OKを捨て、送り終えても戻さない。トーストは出さない
    @Test(arguments: [RoomStatus.drawn, .closed])
    func pendingReadyIsDiscardedWhenRoomStops(_ status: RoomStatus) async {
        let server = RoomModelTests.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsReady = true
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = RoomModelTests.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        model.readyTapped()
        #expect(await AsyncTestSupport.eventually { repository.isHoldingReady })
        #expect(model.isReady)

        server.rooms[DemoScenario.roomID]?.room.status = status
        #expect(await AsyncTestSupport.eventually { model.room?.status == status })
        #expect(model.pendingReady == nil)
        #expect(!model.isReady)
        #expect(!model.showsReadyButton)

        repository.releaseReady()
        #expect(await AsyncTestSupport.eventually { !repository.isHoldingReady })
        // 書き込みはルールで拒まれる（擬似のサーバーは拒んだ書き込みを残す）
        #expect(await AsyncTestSupport.eventually { !server.rejectedWrites.isEmpty })
        #expect(model.pendingReady == nil)
        #expect(!model.isReady)
        #expect(server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID]?.ready == false)
        #expect(toasts.current == nil)
    }

    /// 送っている途中に自分がメンバーから外されたら、楽観的な準備OKを捨てる
    @Test
    func pendingReadyIsDiscardedWhenRemoved() async {
        let server = RoomModelTests.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsReady = true
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = RoomModelTests.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        model.readyTapped()
        #expect(await AsyncTestSupport.eventually { repository.isHoldingReady })
        #expect(model.pendingReady != nil)

        // 自分をメンバーから外す（作成者による削除と同じ形。メンバーの文書と memberIds から消える）
        server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID] = nil
        server.rooms[DemoScenario.roomID]?.room.memberIds.removeAll { $0 == DemoScenario.myUserID }
        #expect(await AsyncTestSupport.eventually { model.pendingReady == nil })
        #expect(!model.isReady)

        repository.releaseReady()
        #expect(await AsyncTestSupport.eventually { !repository.isHoldingReady })
        #expect(model.pendingReady == nil)
        #expect(server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID] == nil)
        #expect(toasts.current == nil)
    }
}
