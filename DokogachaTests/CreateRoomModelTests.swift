//
//  CreateRoomModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// `CreateRoomModelTests.ControlledFunctions` の `createRoom` のふるまい
enum CreateRoomBehavior {
    /// 擬似のサーバーで作る
    case create
    /// このエラーを投げる
    case fail(any Error)
    /// `finish()` を呼ぶまで止まり、その後で作る
    case suspend
}

/// S-03 ルーム作成（F-02）の初期値・入力の検証・二重送信の防止・成功で S-04 へ・通信エラーのトーストを確かめる
struct CreateRoomModelTests {
    /// `createRoom` の結果を決められ、送られた入力を記録する擬似の Functions（ほかの Callable は擬似のサーバーに渡す）
    final class ControlledFunctions: FunctionsClient {
        let server: InMemoryServer
        var behavior: CreateRoomBehavior
        /// 送られた `createRoom` の入力（送られた順）
        private(set) var requests: [CreateRoomRequest] = []
        private var pending: CheckedContinuation<Void, Never>?

        init(server: InMemoryServer, behavior: CreateRoomBehavior = .create) {
            self.server = server
            self.behavior = behavior
        }

        /// 作成の途中で止まっているか
        var isWaiting: Bool {
            pending != nil
        }

        /// 止めていた作成を進める
        func finish() {
            pending?.resume()
            pending = nil
        }

        func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
            requests.append(request)
            switch behavior {
            case .create:
                break
            case let .fail(error):
                throw error
            case .suspend:
                await withCheckedContinuation { pending = $0 }
            }
            return try await server.createRoom(request)
        }

        func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
            try await server.saveProfile(request)
        }

        func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
            try await server.joinRoom(request)
        }

        func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
            try await server.previewRoom(request)
        }

        func leaveRoom(_ request: RoomRequest) async throws {
            try await server.leaveRoom(request)
        }

        func removeMember(_ request: RemoveMemberRequest) async throws {
            try await server.removeMember(request)
        }

        func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
            try await server.updateRoomSettings(request)
        }

        func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
            try await server.addCandidate(request)
        }

        func deleteCandidate(_ request: CandidateRequest) async throws {
            try await server.deleteCandidate(request)
        }

        func forceUnlock(_ request: RoomRequest) async throws {
            try await server.forceUnlock(request)
        }

        func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse {
            try await server.drawGacha(request)
        }

        func proposeReroll(_ request: RoomRequest) async throws {
            try await server.proposeReroll(request)
        }

        func voteReroll(_ request: VoteRerollRequest) async throws {
            try await server.voteReroll(request)
        }

        func closeRoom(_ request: RoomRequest) async throws {
            try await server.closeRoom(request)
        }

        func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse {
            try await server.inviteLastMembers(request)
        }

        func reportCandidate(_ request: ReportCandidateRequest) async throws {
            try await server.reportCandidate(request)
        }

        func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse {
            try await server.verifyPurchase(request)
        }

        func deleteAccount() async throws {
            try await server.deleteAccount()
        }
    }

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

    /// テストで使う画面の状態と、その窓口
    struct Fixture {
        let model: CreateRoomModel
        let functions: ControlledFunctions
        let toasts: DGToastCenter
    }

    /// 表示名を登録済みの自分がいる擬似のサーバー（時刻は `now` に固定）と、それを使う画面の状態を作る
    static func make(behavior: CreateRoomBehavior = .create) throws -> Fixture {
        let now = try now()
        let server = InMemoryServer.demo(.empty) { now }
        let functions = ControlledFunctions(server: server, behavior: behavior)
        // トーストを出したままにする（テストの間に 2.2 秒が過ぎて消えないよう、出しておく時間を長くする）
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = CreateRoomModel(functions: functions, toasts: toasts, now: now, calendar: calendar)
        return Fixture(model: model, functions: functions, toasts: toasts)
    }

    // MARK: 初期値（02 の §2.2 の表）

    /// ルーム名は空・投稿数 3・全員OK・締切は 3 日後の 21:00・共感ブースト。ルーム名が空なので押せない
    @Test
    func initialValues() throws {
        let fixture = try Self.make()
        let model = fixture.model
        #expect(model.name.isEmpty)
        #expect(model.postLimit == 3)
        #expect(model.unlockRule == .all)
        #expect(model.likeMode == .boost)
        let expectedDeadline = try #require(Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 21)))
        #expect(model.deadline == expectedDeadline)
        let now = try Self.now()
        #expect(model.deadlineRange == now.addingTimeInterval(60 * 60)...now.addingTimeInterval(30 * 24 * 60 * 60 - 5 * 60))
        #expect(!model.showsDeadlinePicker)
        #expect(model.nameLimit == 20)
        #expect(!model.canSubmit)
    }

    // MARK: 入力の検証

    /// ルーム名が空（空白・見えない文字だけを含む）のときは「ルームを作成」が押せず、エラーの文言も出さない（F-02 の AC）
    @Test(arguments: ["", "   ", "\u{200B}"])
    func emptyNameCannotSubmit(input: String) throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = input
        #expect(model.nameCount == 0)
        #expect(model.nameIssue == nil)
        #expect(!model.canSubmit)
    }

    /// 1〜20 文字なら押せる（前後の空白は数えない）
    @Test(arguments: [("年", 1), ("年末の旅行", 5), ("12345678901234567890", 20), ("  年末の旅行 ", 5)])
    func acceptsOneToTwentyCharacters(name: (input: String, count: Int)) throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = name.input
        #expect(model.nameCount == name.count)
        #expect(model.nameIssue == nil)
        #expect(model.canSubmit)
    }

    /// 21 文字は押せず、上限を超えたことを出す
    @Test
    func rejectsTwentyOneCharacters() throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = "123456789012345678901"
        #expect(model.nameIssue == .tooLong(limit: 20))
        #expect(!model.canSubmit)
    }

    /// 改行などの使えない文字は押せず、その理由を出す
    @Test
    func rejectsForbiddenCharacter() throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = "年末\nの旅行"
        #expect(model.nameIssue == .forbiddenCharacter)
        #expect(!model.canSubmit)
    }

    /// 投稿数は 1 未満・10 超にできない（F-02 の AC。範囲の外の値は端に戻す）
    @Test(arguments: [(0, 1), (-3, 1), (1, 1), (10, 10), (11, 10), (99, 10)])
    func postLimitStaysInRange(value: (input: Int, expected: Int)) throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.postLimit = value.input
        #expect(model.postLimit == value.expected)
    }

    /// 「締切日時」を選んだときだけ日時ピッカーを出し、締切を送る
    @Test
    func deadlineIsSentOnlyForDeadlineRule() throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = "年末の旅行"
        #expect(try #require(model.request).deadlineAt == nil)

        model.unlockRule = .deadline
        #expect(model.showsDeadlinePicker)
        #expect(try #require(model.request).deadlineAt == CallableTime.milliseconds(from: model.deadline))

        model.unlockRule = .majority
        #expect(!model.showsDeadlinePicker)
        #expect(try #require(model.request).deadlineAt == nil)
    }

    /// 締切日時が範囲（今から 1 時間後〜30 日後）の外なら押せない。範囲の端は押せる
    @Test
    func deadlineOutsideRangeCannotSubmit() throws {
        let fixture = try Self.make()
        let model = fixture.model
        model.name = "年末の旅行"
        model.unlockRule = .deadline

        model.deadline = model.deadlineRange.lowerBound
        #expect(model.canSubmit)
        model.deadline = model.deadlineRange.upperBound
        #expect(model.canSubmit)
        model.deadline = model.deadlineRange.lowerBound.addingTimeInterval(-1)
        #expect(!model.canSubmit)
        model.deadline = model.deadlineRange.upperBound.addingTimeInterval(1)
        #expect(!model.canSubmit)
    }

    // MARK: 作成

    /// 作成すると、入力どおりの `open` のルームができ、メンバーは作成者 1 人（F-02 の AC）。S-04 の行き先が入る
    @Test
    func submitCreatesRoomAndOpensInvite() async throws {
        let fixture = try Self.make()
        let model = fixture.model
        let functions = fixture.functions
        let toasts = fixture.toasts
        model.name = "  年末の旅行 "
        model.postLimit = 5
        model.unlockRule = .deadline
        model.likeMode = .equal
        await model.submit()

        let request = try #require(functions.requests.first)
        #expect(request.name == "年末の旅行")
        #expect(request.postLimit == 5)
        #expect(request.unlockRule == .deadline)
        #expect(request.likeMode == .equal)

        let created = try #require(model.createdRoom)
        #expect(created.roomName == "年末の旅行")
        let record = try #require(functions.server.rooms[created.roomID])
        #expect(record.room.status == .open)
        #expect(record.room.memberIds == [DemoScenario.myUserID])
        #expect(record.room.memberCount == 1)
        #expect(record.members.keys.sorted() == [DemoScenario.myUserID])
        #expect(record.room.inviteCode == created.inviteCode.value)
        #expect(record.room.settings.deadlineAt == CallableTime.date(fromMilliseconds: try #require(request.deadlineAt)))

        // 作成した後は、もう押せず入力も変えられない
        #expect(!model.canSubmit)
        #expect(!model.isEditable)
        #expect(toasts.current == nil)
    }

    /// 送っている途中は、もう一度押しても送らない（二重送信の防止）
    @Test
    func preventsDoubleSubmit() async throws {
        let fixture = try Self.make(behavior: .suspend)
        let model = fixture.model
        let functions = fixture.functions
        model.name = "年末の旅行"

        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        #expect(!model.isEditable)

        model.submitTapped()
        await model.submit()
        #expect(functions.requests.count == 1)

        functions.finish()
        #expect(await AsyncTestSupport.eventually { model.createdRoom != nil })
        #expect(functions.requests.count == 1)
        #expect(functions.server.rooms.count == 1)
    }

    /// Task が動き出す前に続けて 2 回押しても、送るのは 1 回だけ
    @Test
    func doubleTapBeforeTaskStartsSubmitsOnce() async throws {
        let fixture = try Self.make(behavior: .suspend)
        let model = fixture.model
        let functions = fixture.functions
        model.name = "年末の旅行"

        model.submitTapped()
        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        functions.finish()
        #expect(await AsyncTestSupport.eventually { model.createdRoom != nil })
        #expect(functions.requests.count == 1)
    }

    /// 画面が消えたら送っている途中の作成を止め、結果が返っても S-04 へ進まず、トーストも出さない
    @Test
    func cancelSubmitStopsWithoutNavigatingOrToast() async throws {
        let fixture = try Self.make(behavior: .suspend)
        let model = fixture.model
        let functions = fixture.functions
        let toasts = fixture.toasts
        model.name = "年末の旅行"

        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        model.cancelSubmit()
        functions.finish()

        #expect(await AsyncTestSupport.eventually { !model.isSubmitting })
        #expect(model.createdRoom == nil)
        #expect(toasts.current == nil)
    }

    /// 通信エラーではトースト「通信できませんでした」を出し、入力を残してもう一度押せる
    @Test
    func networkFailureShowsToastAndAllowsRetry() async throws {
        let fixture = try Self.make(behavior: .fail(ServerFailure(code: .unavailable)))
        let model = fixture.model
        let functions = fixture.functions
        let toasts = fixture.toasts
        model.name = "年末の旅行"
        await model.submit()

        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.createdRoom == nil)
        #expect(model.name == "年末の旅行")
        #expect(model.canSubmit)

        functions.behavior = .create
        await model.submit()
        #expect(model.createdRoom != nil)
        #expect(functions.requests.count == 2)
    }

    /// サーバーが入力を拒んだら、その理由の文言を出す
    @Test
    func serverRejectionShowsReasonMessage() async throws {
        let failure = ServerFailure(code: .failedPrecondition, reason: AppError.Reason.profileRequired.rawValue)
        let fixture = try Self.make(behavior: .fail(failure))
        let model = fixture.model
        let toasts = fixture.toasts
        model.name = "年末の旅行"
        await model.submit()
        #expect(toasts.current?.text == "表示名を登録してください")
        #expect(model.createdRoom == nil)
    }

    /// cancel（画面を閉じた）のエラーではトーストを出さない
    @Test
    func cancellationShowsNoToast() async throws {
        let fixture = try Self.make(behavior: .fail(CancellationError()))
        let model = fixture.model
        let toasts = fixture.toasts
        model.name = "年末の旅行"
        await model.submit()
        #expect(toasts.current == nil)
        #expect(model.canSubmit)
    }
}
