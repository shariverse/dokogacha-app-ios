//
//  MembersModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-11 メンバー一覧（`MembersModel`）の表示（準備OK・投稿数・作成者の印）・作成者と作成者以外でできること（F-05）・
/// 退出・メンバー削除・失敗のトースト・二重送信の防止・外されたときにシートを閉じることを、擬似のサーバーで確かめる。
///
/// - `room-with-candidates` のデモのルーム: 自分（たくみ）が作成者。メンバーは参加順に たくみ・はるか・そうた・みお。
///   候補は たくみの江の島・そうたの明治神宮・はるかのサンシャイン水族館（自分とそうたがいいね）
/// - `several-rooms` の「春のお花見」（`DemoScenario.othersRoomID`）: はるかが作成者で、はるか・たくみ・みお
struct MembersModelTests {
    /// デモのデータの「今」
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// 待たずに購読し直す
    static let immediateResubscribe = ResubscribeDelay(delay: .zero) { _ in }

    /// テストで使う画面の状態と、その窓口
    struct Fixture {
        let model: MembersModel
        let functions: RoomSheetControlledFunctions
        let toasts: DGToastCenter
    }

    static func make(_ scenario: DemoScenario = .roomWithCandidates, roomID: String = DemoScenario.roomID) -> Fixture {
        let server = InMemoryServer.demo(scenario) { Self.now }
        let functions = RoomSheetControlledFunctions(server: server)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = MembersModel(
            roomID: roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: functions,
            toasts: toasts,
            resubscribeDelay: immediateResubscribe
        )
        return Fixture(model: model, functions: functions, toasts: toasts)
    }

    /// ルーム・メンバー・候補がそろうまで待つ
    static func waitUntilLoaded(_ model: MembersModel, members: Int, candidates: Int) async -> Bool {
        await AsyncTestSupport.eventually {
            model.room.loadState == .loaded && model.rows.count == members && model.room.candidates.count == candidates
        }
    }

    static func row(_ model: MembersModel, _ memberID: String) throws -> MembersModel.Row {
        try #require(model.rows.first { $0.id == memberID })
    }

    // MARK: - 表示

    /// メンバーは参加順に、名前・準備OK・投稿数・作成者の印を出す。作成者（自分）は自分以外を削除でき、退出はできない
    @Test
    func ownerSeesMembersAndCanRemoveOthers() async throws {
        let fixture = Self.make()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))

        #expect(model.rows.map(\.id) == [DemoScenario.myUserID, "demo-haruka", "demo-sota", "demo-mio"])
        #expect(model.rows.map(\.name) == ["たくみ", "はるか", "そうた", "みお"])
        #expect(model.rows.map(\.postCount) == [1, 1, 1, 0])
        #expect(model.rows.map(\.isOwner) == [true, false, false, false])
        #expect(model.rows.map(\.isMe) == [true, false, false, false])
        #expect(model.rows.map(\.canRemove) == [false, true, true, true])
        #expect(model.rows.allSatisfy { !$0.isReady })
        #expect(model.memberCount == 4)
        // 作成者は退出できない（F-05）
        #expect(!model.canLeave)
        model.leaveTapped()
        #expect(!model.isConfirmingLeave)
        // 招待の文面は S-04 と同じ
        #expect(model.shareMessage == "「年末の旅行」で行き先ガチャやろう！行きたい場所を投稿してね\nhttps://dokogacha.app/r/DK729Q")
    }

    /// 準備OKにしたメンバーは準備OKとして出る（購読の値）
    @Test
    func showsReadiness() async throws {
        let fixture = Self.make()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))

        await fixture.functions.server.device(of: "demo-sota")
            .setReady(true, roomID: DemoScenario.roomID)
        #expect(await AsyncTestSupport.eventually { (try? Self.row(model, "demo-sota").isReady) == true })
        #expect(try !Self.row(model, "demo-haruka").isReady)
    }

    /// 作成者以外は、退出できるが誰も削除できない。作成者の印は作成者（はるか）に付く
    @Test
    func memberCanLeaveButNotRemove() async throws {
        let fixture = Self.make(.severalRooms, roomID: DemoScenario.othersRoomID)
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 3, candidates: 0))

        #expect(model.canLeave)
        #expect(model.rows.allSatisfy { !$0.canRemove })
        #expect(model.rows.first { $0.isOwner }?.id == "demo-haruka")
        model.removeTapped(try Self.row(model, "demo-mio"))
        #expect(model.memberPendingRemoval == nil)
    }

    /// 行き先が決まったルーム（`drawn`）には招待できない（参加できないため）
    @Test
    func cannotInviteToDecidedRoom() async {
        let fixture = Self.make()
        let model = fixture.model
        fixture.functions.server.rooms[DemoScenario.roomID]?.room.status = .drawn
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))
        #expect(model.shareMessage == nil)
    }

    /// 満員（20 人）のルームには招待できない（招待しても参加できないため。S-07 の招待の「＋」と同じ判定）。
    /// 誰かが抜けて 19 人になると、また招待できる
    @Test
    func cannotInviteToFullRoomUntilSomeoneLeaves() async throws {
        let fixture = Self.make(.fullRoom)
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: DomainConstants.Limits.maxMembers, candidates: 3))
        #expect(model.shareMessage == nil)

        try await fixture.functions.server.device(of: "demo-guest-16").leaveRoom(RoomRequest(roomId: DemoScenario.roomID))
        #expect(await AsyncTestSupport.eventually { model.shareMessage != nil })
    }

    // MARK: - 退出

    /// 確認してから退出すると `leaveRoom` を呼び、メンバーから外れて `didLeave` が立つ。外れて購読が読めなくなってもシートは閉じない
    /// （親がホームへ戻す）
    @Test
    func leaveRemovesMeAndSetsDidLeave() async throws {
        let fixture = Self.make(.severalRooms, roomID: DemoScenario.othersRoomID)
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 3, candidates: 0))

        model.leaveTapped()
        #expect(model.isConfirmingLeave)
        model.confirmLeaveTapped()
        #expect(await AsyncTestSupport.eventually { model.didLeave })

        let record = try #require(fixture.functions.server.rooms[DemoScenario.othersRoomID])
        #expect(!record.room.memberIds.contains(DemoScenario.myUserID))
        #expect(fixture.functions.leaveRequests == [RoomRequest(roomId: DemoScenario.othersRoomID)])
        #expect(await AsyncTestSupport.eventually { model.room.loadState == .missing })
        #expect(!model.shouldClose)
        #expect(fixture.toasts.current == nil)
    }

    /// 退出に失敗したら `AppError` の文言のトーストを出し、退出したことにしない（もう一度押せる）
    @Test
    func leaveFailureShowsToast() async {
        let fixture = Self.make(.severalRooms, roomID: DemoScenario.othersRoomID)
        let model = fixture.model
        fixture.functions.leaveBehavior = .fail(ServerFailure(code: .unavailable))
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 3, candidates: 0))

        await model.leave()
        #expect(fixture.toasts.current?.text == "通信できませんでした")
        #expect(!model.didLeave)
        #expect(!model.isSending)
        #expect(model.canLeave)
    }

    /// 退出を送っている途中は、もう一度確認しても送らない（二重送信の防止）。送っている途中は閉じられない印が立つ
    @Test
    func preventsDoubleLeave() async {
        let fixture = Self.make(.severalRooms, roomID: DemoScenario.othersRoomID)
        let model = fixture.model
        fixture.functions.leaveBehavior = .suspend
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 3, candidates: 0))

        model.confirmLeaveTapped()
        model.confirmLeaveTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        #expect(model.isSending)
        model.leaveTapped()
        #expect(!model.isConfirmingLeave)
        await model.leave()
        #expect(fixture.functions.leaveRequests.count == 1)

        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { model.didLeave })
        #expect(fixture.functions.leaveRequests.count == 1)
    }

    /// 画面が消えたら送っている途中の退出を止め、結果が返っても `didLeave` を立てず、トーストも出さない
    @Test
    func cancelSendingStopsWithoutToast() async {
        let fixture = Self.make(.severalRooms, roomID: DemoScenario.othersRoomID)
        let model = fixture.model
        fixture.functions.leaveBehavior = .suspend
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 3, candidates: 0))

        model.confirmLeaveTapped()
        #expect(await AsyncTestSupport.eventually { fixture.functions.isWaiting })
        model.cancelSending()
        fixture.functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isSending })
        #expect(fixture.toasts.current == nil)
    }

    // MARK: - 削除

    /// 作成者が確認してから削除すると `removeMember` を呼び、そのメンバーが一覧から消え、その人のいいねも取り消される（F-05）
    @Test
    func ownerRemovesMember() async throws {
        let fixture = Self.make()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))

        let sota = try Self.row(model, "demo-sota")
        model.removeTapped(sota)
        #expect(model.memberPendingRemoval == sota)
        model.confirmRemoveTapped(sota)
        #expect(model.memberPendingRemoval == nil)

        #expect(await AsyncTestSupport.eventually { model.rows.count == 3 })
        #expect(!model.rows.contains { $0.id == "demo-sota" })
        #expect(fixture.functions.removeRequests == [RemoveMemberRequest(roomId: DemoScenario.roomID, memberId: "demo-sota")])
        let record = try #require(fixture.functions.server.rooms[DemoScenario.roomID])
        #expect(record.candidates.values.allSatisfy { !$0.likedBy.contains("demo-sota") })
        // 退出した人の候補は残る
        #expect(record.candidates.count == 3)
        #expect(fixture.toasts.current == nil)
    }

    /// 作成者自身の行は削除できない（確認も出さず、送らない）
    @Test
    func cannotRemoveOwnerRow() async throws {
        let fixture = Self.make()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))

        model.removeTapped(try Self.row(model, DemoScenario.myUserID))
        #expect(model.memberPendingRemoval == nil)
        await model.remove(memberID: DemoScenario.myUserID)
        #expect(fixture.functions.removeRequests.isEmpty)
    }

    /// 削除の確認を出している間にそのメンバーが退出したら、確認を閉じる（ダイアログはそのメンバーの行に付くので、行と一緒に消える）
    @Test
    func removalConfirmationClosesWhenMemberLeaves() async throws {
        let fixture = Self.make()
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))

        model.removeTapped(try Self.row(model, "demo-sota"))
        // 一覧にいて削除できるうちは閉じない
        model.closeUnavailableRemoval()
        #expect(model.memberPendingRemoval?.id == "demo-sota")

        // 別の端末でそうたが退出した
        try await fixture.functions.server.device(of: "demo-sota").leaveRoom(RoomRequest(roomId: DemoScenario.roomID))
        #expect(await AsyncTestSupport.eventually { model.rows.count == 3 })
        model.closeUnavailableRemoval()
        #expect(model.memberPendingRemoval == nil)
        #expect(fixture.functions.removeRequests.isEmpty)
    }

    /// サーバーに断られたら（もういないメンバー）、その理由の文言のトーストを出す
    @Test
    func removeRejectionShowsReason() async throws {
        let fixture = Self.make()
        let model = fixture.model
        let reason = AppError.Reason.memberNotFound.rawValue
        fixture.functions.removeBehavior = .fail(ServerFailure(code: .notFound, reason: reason))
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 4, candidates: 3))

        await model.remove(memberID: "demo-mio")
        #expect(fixture.toasts.current?.text == "このメンバーはもうルームにいません")
        #expect(model.rows.count == 4)
    }

    // MARK: - 外されたとき

    /// 作成者に削除された（自分が外された）ら、シートを閉じる
    @Test
    func closesWhenRemovedByOwner() async throws {
        let fixture = Self.make(.severalRooms, roomID: DemoScenario.othersRoomID)
        let model = fixture.model
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, members: 3, candidates: 0))
        #expect(!model.shouldClose)

        try await fixture.functions.server.device(of: "demo-haruka")
            .removeMember(RemoveMemberRequest(roomId: DemoScenario.othersRoomID, memberId: DemoScenario.myUserID))
        #expect(await AsyncTestSupport.eventually { model.shouldClose })
        #expect(!model.didLeave)
    }
}
