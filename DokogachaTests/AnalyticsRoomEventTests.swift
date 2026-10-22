//
//  AnalyticsRoomEventTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// ルームの作成・参加・候補の追加・いいね・準備OK・解禁の操作から、05 の §9 のイベントを名前とパラメータどおりに送ることを、
/// 画面の Model と擬似のサーバーで確かめる（送るのは操作が成功したときだけ）
struct AnalyticsRoomEventTests {
    // MARK: room_create

    /// 作成できたら、投稿数・解禁の条件・いいねの効き方を送る（ルーム名は送らない）
    @Test
    func roomCreateSendsSettings() async {
        let analytics = RecordingAnalyticsService()
        let model = CreateRoomModel(
            functions: InMemoryServer.demo(.empty),
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            analytics: analytics
        )
        model.name = "年末の旅行"
        model.postLimit = 5
        model.unlockRule = .majority
        model.likeMode = .equal

        await model.submit()

        #expect(model.createdRoom != nil)
        #expect(analytics.events == [.roomCreate(postLimit: 5, unlockRule: .majority, likeMode: .equal)])
        #expect(analytics.events.first?.parameters == [
            "post_limit": .int(5), "unlock_rule": .string("majority"), "like_mode": .string("equal")
        ])
    }

    /// 作成に失敗したら送らない
    @Test
    func roomCreateFailureSendsNothing() async {
        let analytics = RecordingAnalyticsService()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = CreateRoomModel(functions: UnavailableServer(), toasts: toasts, analytics: analytics)
        model.name = "年末の旅行"
        await model.submit()
        #expect(model.createdRoom == nil)
        #expect(analytics.events.isEmpty)
    }

    // MARK: room_join

    static func confirmModel(
        server: InMemoryServer,
        via: RoomJoinVia,
        analytics: RecordingAnalyticsService
    ) async throws -> JoinConfirmModel {
        let code = DemoScenario.joinableInviteCode
        let preview = try await server.previewRoom(PreviewRoomRequest(inviteCode: code))
        return JoinConfirmModel(
            destination: JoinConfirmDestination(preview: preview, inviteCode: try #require(InviteCode(code))),
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            via: via,
            analytics: analytics
        )
    }

    /// 参加できたら、開いた道（link / code / push）を送る。もとからメンバーだったときは送らない
    @Test(arguments: RoomJoinVia.allCases)
    func roomJoinSendsVia(via: RoomJoinVia) async throws {
        let server = InMemoryServer.demo(.joinable)
        let analytics = RecordingAnalyticsService()
        let model = try await Self.confirmModel(server: server, via: via, analytics: analytics)

        await model.join()

        #expect(model.joinedRoomID != nil)
        #expect(analytics.events == [.roomJoin(via: via)])
        #expect(analytics.events.first?.parameters == ["via": .string(via.rawValue)])

        let again = try await Self.confirmModel(server: server, via: via, analytics: analytics)
        await again.join()
        #expect(again.joinedRoomID != nil)
        #expect(analytics.events.count == 1)
    }

    /// 招待リンクで開いたら link、前回のメンバーへの招待の通知で開いたら push、ホームの「招待コードで参加」なら code の行き先になる
    @Test
    func joinViaFollowsHowTheCodeArrived() throws {
        let router = DeepLinkRouter()
        let code = try #require(InviteCode(DemoScenario.joinableInviteCode))

        router.handle(PushDestination(kind: .invited, roomID: "demo-room", target: .join, inviteCode: code))
        #expect(router.pendingInviteVia == .push)
        router.handle(try #require(URL(string: "https://dokogacha.app/r/\(code.value)")))
        #expect(router.pendingInviteVia == .link)

        #expect(AppRoute.joinByInviteLink(code).joinVia == .link)
        #expect(AppRoute.joinByInviteLink(code, via: .push).joinVia == .push)
        #expect(AppRoute.joinByInviteLink(code, via: .push).inviteLinkCode == code)
        #expect(AppRoute.joinByCode.joinVia == .code)
        #expect(AppRoute.settings.joinVia == nil)
    }

    // MARK: candidate_add

    static func addModel(_ server: InMemoryServer, analytics: RecordingAnalyticsService) -> AddCandidateModel {
        AddCandidateModel(
            roomID: DemoScenario.roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            places: DemoPlaceSearchService(),
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            sleep: { _ in },
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics
        )
    }

    /// 検索から追加したら source が search で、カテゴリを送る（ひとことは送らない）
    @Test
    func candidateAddFromSearch() async throws {
        let analytics = RecordingAnalyticsService()
        let model = Self.addModel(AddCandidateModelTests.makeServer(), analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AddCandidateModelTests.waitUntilLoaded(model))

        model.addTapped(try AddCandidateModelTests.place("すみだ水族館"))
        model.note = "ペンギンが見たい"
        await model.submit()

        #expect(model.finish != nil)
        #expect(analytics.events == [.candidateAdd(source: .search, category: .aquarium)])
        #expect(analytics.events.first?.parameters == ["source": .string("search"), "category": .string("aquarium")])
    }

    /// 過去のアイデアから持ち込んだら source が past
    @Test
    func candidateAddFromPastIdea() async throws {
        let analytics = RecordingAnalyticsService()
        let model = Self.addModel(try AddCandidatePastIdeaTests.makeServer(), analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AddCandidatePastIdeaTests.waitUntilLoaded(model))

        model.bringTapped(try AddCandidatePastIdeaTests.idea("summer_c2", in: model))
        await model.submit()

        #expect(model.finish != nil)
        #expect(analytics.events == [.candidateAdd(source: .past, category: .shrine)])
    }

    /// 同じ場所の重複の確認から「いいねする」と、いいね（on は 1）を送り、追加は送らない
    @Test
    func duplicateLikeSendsLikeToggle() async throws {
        let server = AddCandidateModelTests.makeServer()
        let analytics = RecordingAnalyticsService()
        let model = Self.addModel(server, analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AddCandidateModelTests.waitUntilLoaded(model))

        await model.likeDuplicate(AddCandidateModel.DuplicatePrompt(candidateID: AddCandidateModelTests.shrineCandidate))

        #expect(model.finish != nil)
        #expect(analytics.events == [.likeToggle(on: true)])
    }

    // MARK: like_toggle・ready_toggle

    static func roomModel(
        _ server: InMemoryServer,
        analytics: RecordingAnalyticsService,
        logsRoomChanges: Bool = false
    ) -> RoomModel {
        RoomModel(
            roomID: DemoScenario.roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics,
            logsRoomChanges: logsRoomChanges
        )
    }

    /// いいねを付ける・外す、準備OKを付ける・外すたびに、on を 1・0 で送る
    @Test
    func likeAndReadyToggleSendOn() async {
        let server = RoomModelTests.makeServer()
        let analytics = RecordingAnalyticsService()
        let model = Self.roomModel(server, analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        await model.toggleLike(RoomModelTests.shrine)
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        await model.toggleLike(RoomModelTests.shrine)
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        await model.toggleReady()
        #expect(await AsyncTestSupport.eventually { model.pendingReady == nil })
        await model.toggleReady()

        #expect(analytics.events == [.likeToggle(on: true), .likeToggle(on: false), .readyToggle(on: true), .readyToggle(on: false)])
        #expect(analytics.events.first?.parameters == ["on": .int(1)])
    }

    /// 押せない候補（自分の投稿）のいいねは送らない
    @Test
    func likeOnOwnCandidateSendsNothing() async {
        let analytics = RecordingAnalyticsService()
        let model = Self.roomModel(RoomModelTests.makeServer(), analytics: analytics)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))
        await model.toggleLike(RoomModelTests.mine)
        #expect(analytics.events.isEmpty)
    }

    /// S-10 候補の詳細のいいねも送る
    @Test
    func candidateDetailLikeSendsEvent() async {
        let server = RoomModelTests.makeServer()
        let analytics = RecordingAnalyticsService()
        let model = CandidateDetailModel(
            roomID: DemoScenario.roomID,
            candidateID: RoomModelTests.shrine,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: DGToastCenter(visibleFor: .seconds(3_600)),
            mapOpener: RecordingMapOpener(),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            analytics: analytics
        )
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model.room))
        await model.room.toggleLike(RoomModelTests.shrine)
        #expect(analytics.events == [.likeToggle(on: true)])
    }

    // MARK: room_unlock

    /// S-07 を出している間に解禁されたら、解禁の条件と強制解禁かを送る（強制解禁）
    @Test
    func forcedUnlockSendsRuleAndForced() async {
        let server = RoomModelTests.makeServer()
        let analytics = RecordingAnalyticsService()
        let model = Self.roomModel(server, analytics: analytics, logsRoomChanges: true)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        await model.forceUnlock()

        #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked })
        #expect(analytics.events == [.roomUnlock(rule: .all, forced: true)])
        #expect(analytics.events.first?.parameters == ["rule": .string("all"), "forced": .int(1)])
    }

    /// 全員の準備OKで解禁されたら forced は 0。S-07 以外の Model（`logsRoomChanges` が false）は送らない
    @Test
    func unlockByReadySendsNotForced() async {
        let server = RoomModelTests.makeServer()
        let analytics = RecordingAnalyticsService()
        let nested = RecordingAnalyticsService()
        let model = Self.roomModel(server, analytics: analytics, logsRoomChanges: true)
        let other = Self.roomModel(server, analytics: nested)
        let observing = Task { await model.observe() }
        let observingOther = Task { await other.observe() }
        defer {
            observing.cancel()
            observingOther.cancel()
        }
        #expect(await RoomModelTests.waitUntilLoaded(model))
        #expect(await RoomModelTests.waitUntilLoaded(other))

        for member in [RoomModelReadyTests.haruka, RoomModelReadyTests.sota, RoomModelReadyTests.mio] {
            await RoomModelReadyTests.setReady(true, member, on: server)
        }
        await other.toggleReady()

        #expect(await AsyncTestSupport.eventually { model.room?.status == .unlocked })
        #expect(analytics.events == [.roomUnlock(rule: .all, forced: false)])
        #expect(nested.events == [.readyToggle(on: true)])
    }
}
