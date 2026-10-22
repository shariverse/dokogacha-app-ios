//
//  RoomSettingsModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-12 ルーム設定（`RoomSettingsModel`）の初期値（今の設定）・F-03 の変更ルール（作成者だけ・投稿数は引き上げのみ・
/// 解禁の条件は `open` だけ・いいねの効き方は `open`・`unlocked` だけ・`closed` は変えられない）・変えた項目だけを送ること・
/// 締切日時の範囲の計算し直し・保存・失敗のトースト・二重送信の防止を、擬似のサーバーで確かめる。
///
/// `room-with-candidates` のデモのルーム「年末の旅行」: 自分が作成者・`open`・投稿数 3・全員OK・共感ブースト
struct RoomSettingsModelTests {
    /// 日本時間のグレゴリオ暦
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }

    /// 今の時刻（2026-10-22 12:00 日本時間）
    static func now() throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12)))
    }

    /// 待たずに購読し直す
    static let immediateResubscribe = ResubscribeDelay(delay: .zero) { _ in }

    /// テストで使う画面の状態と、その窓口
    struct Fixture {
        let model: RoomSettingsModel
        let functions: RoomSheetControlledFunctions
        let toasts: DGToastCenter
        let clock: TestClock

        var server: InMemoryServer {
            functions.server
        }

        /// デモのルームの今の値
        var room: Room? {
            server.rooms[DemoScenario.roomID]?.room
        }
    }

    /// デモのルームを開いた画面の状態を作る（`prepare` でルームを書き換えてから画面を作る）
    static func make(
        userID: String = DemoScenario.myUserID,
        prepare: (InMemoryServer) -> Void = { _ in }
    ) throws -> Fixture {
        let clock = TestClock(try now())
        let server = InMemoryServer.demo(.roomWithCandidates, clock: clock.read)
        prepare(server)
        let functions = RoomSheetControlledFunctions(server: server)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = RoomSettingsModel(
            roomID: DemoScenario.roomID,
            userID: userID,
            repository: server,
            functions: functions,
            toasts: toasts,
            clock: clock.read,
            calendar: calendar,
            resubscribeDelay: immediateResubscribe
        )
        return Fixture(model: model, functions: functions, toasts: toasts, clock: clock)
    }

    /// 購読を始めてルームが届くまで待ち、購読の Task を返す（テストの最後に cancel する）
    static func observe(_ model: RoomSettingsModel) async -> Task<Void, Never> {
        let observing = Task { await model.observe() }
        _ = await AsyncTestSupport.eventually { model.isLoaded }
        return observing
    }

    // MARK: - 初期値

    /// ルームが届く前は読み込み中で、保存できない。届いたら今の設定を出し、何も変えていないので保存できない
    @Test
    func showsCurrentSettings() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        #expect(!model.isLoaded)
        #expect(!model.canSave)

        let observing = await Self.observe(model)
        defer { observing.cancel() }
        #expect(model.name == "年末の旅行")
        #expect(model.postLimit == 3)
        #expect(model.postLimitChoices == 3...10)
        #expect(model.unlockRule == .all)
        #expect(model.likeMode == .boost)
        #expect(!model.showsDeadlinePicker)
        #expect(model.formLock == nil)
        #expect(model.isNameEditable && model.isPostLimitEditable && model.isUnlockRuleEditable && model.isLikeModeEditable)
        #expect(model.request == nil)
        #expect(!model.canSave)
    }

    // MARK: - 変更ルール（F-03）

    /// 投稿数は今の値より少なくできない（範囲の下限が今の値。外の値は端に戻す）。引き上げは送れる
    @Test
    func postLimitCanOnlyBeRaised() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.postLimit = 2
        #expect(model.postLimit == 3)
        #expect(model.request == nil)
        model.postLimit = 5
        #expect(model.request == UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, postLimit: 5))
        model.postLimit = 11
        #expect(model.postLimit == 10)
    }

    /// 投稿数がもう上限（10）なら、投稿数は変えられない
    @Test
    func postLimitAtMaximumIsLocked() async throws {
        let fixture = try Self.make { $0.rooms[DemoScenario.roomID]?.room.settings.postLimit = 10 }
        let observing = await Self.observe(fixture.model)
        defer { observing.cancel() }
        #expect(fixture.model.postLimitChoices == 10...10)
        #expect(!fixture.model.isPostLimitEditable)
    }

    /// `unlocked` では解禁の条件を変えられず（今の値を出して送らない）、いいねの効き方とルーム名・投稿数は変えられる
    @Test
    func unlockedRoomLocksUnlockRule() async throws {
        let fixture = try Self.make { $0.rooms[DemoScenario.roomID]?.room.status = .unlocked }
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        #expect(model.unlockRuleLock == .status)
        #expect(!model.isUnlockRuleEditable)
        model.unlockRule = .majority
        #expect(model.unlockRule == .all)
        #expect(model.request == nil)

        #expect(model.likeModeLock == nil)
        model.likeMode = .equal
        model.name = "年越しの旅行"
        #expect(model.request == UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, name: "年越しの旅行", likeMode: .equal))
    }

    /// `drawn` では解禁の条件もいいねの効き方も変えられない。ルーム名と投稿数は変えられる
    @Test
    func drawnRoomLocksUnlockRuleAndLikeMode() async throws {
        let fixture = try Self.make { $0.rooms[DemoScenario.roomID]?.room.status = .drawn }
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        #expect(model.unlockRuleLock == .status)
        #expect(model.likeModeLock == .status)
        model.likeMode = .equal
        #expect(model.likeMode == .boost)
        model.postLimit = 4
        #expect(model.request == UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, postLimit: 4))
    }

    /// `closed` ではどの項目も変えられず、保存できない
    @Test
    func closedRoomLocksEverything() async throws {
        let fixture = try Self.make { $0.rooms[DemoScenario.roomID]?.room.status = .closed }
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        #expect(model.formLock == .closed)
        #expect(!model.isNameEditable && !model.isPostLimitEditable && !model.isUnlockRuleEditable && !model.isLikeModeEditable)
        model.name = "年越しの旅行"
        #expect(model.request == nil)
        #expect(!model.canSave)
    }

    /// 作成者以外は、どの項目も変えられず、保存できない
    @Test
    func nonOwnerCannotEdit() async throws {
        let fixture = try Self.make { $0.rooms[DemoScenario.roomID]?.room.ownerId = "demo-haruka" }
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        #expect(model.formLock == .notOwner)
        #expect(!model.isNameEditable)
        model.postLimit = 5
        #expect(model.request == nil)
        #expect(!model.canSave)
    }

    /// ルーム名は S-03 と同じ検証（空・21 文字は送れない）。前後の空白を除いて今と同じなら送らない
    @Test
    func nameIsValidatedAndSentOnlyWhenChanged() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.name = "  "
        #expect(model.request == nil)
        model.name = String(repeating: "あ", count: 21)
        #expect(model.nameCheck.issue == .tooLong(limit: 20))
        #expect(model.request == nil)
        model.name = " 年末の旅行 "
        #expect(model.request == nil)
        model.name = " 年越しの旅行 "
        #expect(model.request == UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, name: "年越しの旅行"))
    }

    /// 条件を戻したら送らない（今と同じ値は「変えない」）
    @Test
    func revertingUnlockRuleSendsNothing() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let observing = await Self.observe(model)
        defer { observing.cancel() }

        model.unlockRule = .majority
        #expect(model.request == UpdateRoomSettingsRequest(roomId: DemoScenario.roomID, unlockRule: .majority))
        model.unlockRule = .all
        #expect(model.request == nil)
    }
}
