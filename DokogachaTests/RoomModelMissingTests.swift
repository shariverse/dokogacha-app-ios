//
//  RoomModelMissingTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ルームを読めなくなったとき（作成者に削除された・自分で退出した・無いルームを開いた）に、`RoomModel` が
/// 読み込み中のまま購読し直し続けず、「ルームが見つかりません」（`.missing`）になることを確かめる。
///
/// `several-rooms` の「春のお花見」（`DemoScenario.othersRoomID`）は、はるかが作成者で、自分（たくみ）とみおがメンバー
struct RoomModelMissingTests {
    /// デモのデータの「今」
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// 購読し直すたびに数える、待たずに進む待ち方（購読し直していないことを確かめる）
    final class ResubscribeCounter {
        var times = 0
    }

    static func makeModel(
        _ repository: any RoomRepository,
        roomID: String = DemoScenario.othersRoomID,
        toasts: DGToastCenter,
        counter: ResubscribeCounter? = nil
    ) -> RoomModel {
        let delay = ResubscribeDelay(delay: .zero) { _ in
            await MainActor.run { counter?.times += 1 }
        }
        return RoomModel(
            roomID: roomID,
            userID: DemoScenario.myUserID,
            repository: repository,
            functions: UnavailableServer(),
            toasts: toasts,
            resubscribeDelay: delay
        )
    }

    /// 作成者に削除されたら `.missing` になり、出していた値を捨て、トーストを出さず、購読し直さない（購読も外す）
    @Test
    func removedByOwnerBecomesMissing() async throws {
        let server = InMemoryServer.demo(.severalRooms) { Self.now }
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let counter = ResubscribeCounter()
        let model = Self.makeModel(server, toasts: toasts, counter: counter)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { model.loadState == .loaded && model.members.count == 3 })

        try await server.device(of: "demo-haruka")
            .removeMember(RemoveMemberRequest(roomId: DemoScenario.othersRoomID, memberId: DemoScenario.myUserID))

        #expect(await AsyncTestSupport.eventually { model.loadState == .missing })
        // 3 つの購読がすべて終わる（購読し直さない）
        await observing.value
        #expect(model.room == nil)
        #expect(model.members.isEmpty)
        #expect(model.candidates.isEmpty)
        #expect(counter.times == 0)
        #expect(server.subscriberCount == 0)
        #expect(toasts.current == nil)
    }

    /// 自分で退出しても `.missing` になる（S-11 がホームに戻すので、ここではトーストを出さない）
    @Test
    func leavingBecomesMissing() async throws {
        let server = InMemoryServer.demo(.severalRooms) { Self.now }
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(server, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { model.loadState == .loaded })

        try await server.leaveRoom(RoomRequest(roomId: DemoScenario.othersRoomID))

        #expect(await AsyncTestSupport.eventually { model.loadState == .missing })
        #expect(toasts.current == nil)
    }

    /// 無いルームを開いたら、読み込み中のままにせず `.missing` にする（購読し直さない）
    @Test
    func unknownRoomBecomesMissing() async {
        let server = InMemoryServer.demo(.severalRooms) { Self.now }
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let counter = ResubscribeCounter()
        let model = Self.makeModel(server, roomID: "no-such-room", toasts: toasts, counter: counter)
        await model.observe()
        #expect(model.loadState == .missing)
        #expect(counter.times == 0)
        #expect(toasts.current == nil)
    }

    /// 一時的な失敗（通信できない）は、これまでどおり出していた値のまま購読し直して戻る（`.missing` にしない）
    @Test
    func transientFailureStillResubscribes() async {
        let repository = RoomControlledRepository(server: InMemoryServer.demo(.severalRooms) { Self.now })
        repository.roomFailures = [AppError(.network, code: .unavailable)]
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let counter = ResubscribeCounter()
        let model = Self.makeModel(repository, toasts: toasts, counter: counter)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.loadState == .loaded })
        #expect(counter.times == 1)
        #expect(toasts.current?.text == "通信できませんでした")
    }

    /// ルールで拒まれた失敗だけを「読めなくなった」とみなす
    @Test
    func onlyPermissionDeniedMeansUnavailable() {
        #expect(AppError.server(ServerFailure(code: .permissionDenied)).isPermissionDenied)
        #expect(AppError(.permissionDenied).isPermissionDenied)
        #expect(!AppError(.network, code: .unavailable).isPermissionDenied)
        #expect(!AppError(.unreadableData).isPermissionDenied)
        #expect(!AppError(.cancelled, code: .cancelled).isPermissionDenied)
    }
}
