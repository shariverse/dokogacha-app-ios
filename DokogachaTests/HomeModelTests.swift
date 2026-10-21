//
//  HomeModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// `HomeModelTests.FlakyRoomRepository` の 1 回目の購読のふるまい
enum HomeFirstSubscription {
    /// 一覧を 1 回流してから、一時的な失敗で終わる
    case valueThenFailure
    /// 一覧を流さずに、すぐ一時的な失敗で終わる
    case failure
}

/// S-02 ホームの進行中のルーム（`HomeModel`）を擬似のサーバーで動かし、並び・空の表示・通信エラー（画面を壊さずトーストと購読のやり直し）・
/// 購読の止め方を確かめる。画面（`HomeView`）の `.task` の代わりに、`observe()` を `Task` で動かして最後に cancel する
struct HomeModelTests {
    /// 進行中のルームの購読を、決めた回数だけ失敗させる窓口（それ以外は擬似のサーバーのまま）
    final class FlakyRoomRepository: RoomRepository {
        let server: InMemoryServer
        let first: HomeFirstSubscription
        /// 進行中のルームを購読した回数
        private(set) var activeRoomsSubscriptionCount = 0

        init(server: InMemoryServer, first: HomeFirstSubscription) {
            self.server = server
            self.first = first
        }

        func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>> {
            activeRoomsSubscriptionCount += 1
            guard activeRoomsSubscriptionCount == 1 else {
                return server.activeRooms(userID: userID)
            }
            let (stream, continuation) = AsyncStream.makeStream(of: LiveUpdate<[Identified<Room>]>.self)
            if first == .valueThenFailure {
                let rooms = server.rooms.map { Identified(id: $0.key, value: $0.value.room) }
                continuation.yield(.value(rooms))
            }
            continuation.yield(.failure(AppError(.network, code: .unavailable)))
            continuation.finish()
            return stream
        }

        func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>> {
            server.room(id: roomID)
        }

        func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>> {
            server.members(roomID: roomID)
        }

        func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>> {
            server.candidates(roomID: roomID)
        }

        func setReady(_ ready: Bool, roomID: String, userID: String) async throws {}

        func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws {}

        func markSeen(roomID: String, userID: String) async throws {}
    }

    /// トーストを出したままにする窓口（テストの間に消えないよう、出しておく時間を長くする）
    static func makeToasts() -> DGToastCenter {
        DGToastCenter(visibleFor: .seconds(3_600))
    }

    /// 待たずに購読し直す
    static let immediateResubscribe = ResubscribeDelay(delay: .zero) { _ in }
    /// cancel されるまで購読し直さない（失敗した直後の表示を確かめる）
    static let neverResubscribe = ResubscribeDelay(delay: .seconds(3_600)) { try await Task.sleep(for: $0) }

    static func makeModel(
        _ repository: any RoomRepository,
        toasts: DGToastCenter = makeToasts(),
        resubscribeDelay: ResubscribeDelay = immediateResubscribe
    ) -> HomeModel {
        HomeModel(userID: DemoScenario.myUserID, repository: repository, toasts: toasts, resubscribeDelay: resubscribeDelay)
    }

    /// 最初の一覧が届くまでは読み込み中（空の表示を出さない）
    @Test
    func startsLoading() {
        let model = Self.makeModel(InMemoryServer.demo(.oneRoom))
        #expect(model.roomsState == .loading)
        #expect(!model.isEmpty)
        #expect(model.cards.isEmpty)
    }

    /// 進行中のルームを作成日時の新しい順に並べ、メンバーのアバターと準備OKを映す
    @Test
    func listsActiveRoomsNewestFirstWithMembers() async throws {
        let server = InMemoryServer.demo(.severalRooms)
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.membersByRoom.count == 3 })
        let cards = model.cards
        #expect(cards.map(\.id) == [DemoScenario.unlockedRoomID, DemoScenario.roomID, DemoScenario.othersRoomID])
        #expect(cards.map(\.name) == ["週末のランチ", "年末の旅行", "春のお花見"])
        #expect(cards.map(\.status) == [.unlocked, .open, .open])
        #expect(cards.map(\.capsuleCount) == [3, 3, 0])

        let mine = try #require(cards.first { $0.id == DemoScenario.roomID })
        #expect(mine.members.map(\.name) == ["たくみ", "はるか", "そうた", "みお"])
        #expect(mine.members.map(\.avatarColorIndex) == [2, 0, 1, 3])
        let unlocked = try #require(cards.first)
        #expect(unlocked.members.allSatisfy { $0.isReady })
        #expect(!model.isEmpty)
    }

    /// ルームが無ければ、空の表示にする
    @Test
    func showsEmptyWhenNoRooms() async {
        let model = Self.makeModel(InMemoryServer.demo(.empty))
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { model.roomsState == .loaded })
        #expect(model.isEmpty)
    }

    /// ルームの状態・メンバーの準備OKが変わったら、カードに映る。行き先が決まって `closed` になったルームは消える
    @Test
    func followsRoomChanges() async throws {
        let server = InMemoryServer.demo(.oneRoom)
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await AsyncTestSupport.eventually { model.membersByRoom[DemoScenario.roomID] != nil })

        server.rooms[DemoScenario.roomID]?.members["demo-haruka"]?.ready = true
        #expect(await AsyncTestSupport.eventually {
            model.cards.first?.members.filter(\.isReady).map(\.id) == ["demo-haruka"]
        })

        server.rooms[DemoScenario.roomID]?.room.status = .closed
        #expect(await AsyncTestSupport.eventually { model.isEmpty })
        // 消えたルームのメンバーは捨てる
        #expect(model.membersByRoom.isEmpty)
    }

    /// 一覧を出した後に購読が一時的に失敗しても、一覧は残したままトーストを出し、購読し直す
    @Test
    func failureAfterLoadKeepsRoomsShowsToastAndResubscribes() async {
        let server = InMemoryServer.demo(.oneRoom)
        let repository = FlakyRoomRepository(server: server, first: .valueThenFailure)
        let toasts = Self.makeToasts()
        let model = Self.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { repository.activeRoomsSubscriptionCount == 2 })
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.roomsState == .loaded)
        #expect(model.cards.map(\.id) == [DemoScenario.roomID])

        // 購読し直した後も変化を受け取る
        server.rooms[DemoScenario.roomID]?.room.name = "年越しの旅行"
        #expect(await AsyncTestSupport.eventually { model.cards.first?.name == "年越しの旅行" })
    }

    /// 最初の一覧より先に失敗したら、空の表示にはせず読み込み中のままトーストを出す
    @Test
    func failureBeforeFirstValueStaysLoading() async {
        let repository = FlakyRoomRepository(server: InMemoryServer.demo(.oneRoom), first: .failure)
        let toasts = Self.makeToasts()
        let model = Self.makeModel(repository, toasts: toasts, resubscribeDelay: Self.neverResubscribe)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await AsyncTestSupport.eventually { toasts.current != nil })
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.roomsState == .loading)
        #expect(!model.isEmpty)
    }

    /// 画面が消えた（`observe()` を cancel した）ら、ルームとメンバーの購読をすべて止める
    @Test
    func cancellingStopsAllSubscriptions() async {
        let server = InMemoryServer.demo(.severalRooms)
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        // ルーム 1 つ＋メンバー 3 つ
        #expect(await AsyncTestSupport.eventually { server.subscriberCount == 4 })

        observing.cancel()
        await observing.value
        #expect(await AsyncTestSupport.eventually { server.subscriberCount == 0 })
    }
}

/// ホームのカードの値（`HomeRoomCard.cards`）の組み立て
struct HomeRoomCardTests {
    static let base = Date(timeIntervalSince1970: 1_790_000_000)

    static func room(name: String, status: RoomStatus = .open, createdAt: Date, members: [String] = ["a", "b", "c"]) -> Room {
        Room(
            name: name,
            ownerId: "a",
            inviteCode: "DK729Q",
            status: status,
            settings: RoomSettings(postLimit: 3, unlockRule: .all, deadlineAt: nil, likeMode: .boost),
            forcedUnlock: false,
            memberIds: members,
            memberCount: members.count,
            readyCount: 2,
            candidateCount: 5,
            adFreeSponsor: nil,
            currentDrawId: nil,
            winnerCandidateId: nil,
            excludedCandidateIds: ["x"],
            reroll: .initial,
            createdAt: createdAt,
            drawnAt: nil,
            closedAt: nil
        )
    }

    /// 新しい順（同じ日時は ID の降順）に並べ、`closed` を除く
    @Test
    func sortsNewestFirstAndDropsClosed() {
        let rooms = [
            Identified(id: "old", value: Self.room(name: "古い", createdAt: Self.base)),
            Identified(id: "same-a", value: Self.room(name: "同じA", createdAt: Self.base.addingTimeInterval(60))),
            Identified(id: "closed", value: Self.room(name: "終了", status: .closed, createdAt: Self.base.addingTimeInterval(120))),
            Identified(id: "same-b", value: Self.room(name: "同じB", createdAt: Self.base.addingTimeInterval(60)))
        ]
        let cards = HomeRoomCard.cards(rooms: rooms, members: [:])
        #expect(cards.map(\.id) == ["same-b", "same-a", "old"])
    }

    /// メンバーを読む前は、人数と準備OKの数だけ合わせた仮のメンバーを並べる。カプセルは外れた候補を除いた数
    @Test
    func placeholderMembersAndCapsuleCount() throws {
        let rooms = [Identified(id: "r", value: Self.room(name: "旅行", createdAt: Self.base))]
        let card = try #require(HomeRoomCard.cards(rooms: rooms, members: [:]).first)
        #expect(card.members.map(\.id) == ["a", "b", "c"])
        #expect(card.members.map(\.isReady) == [true, true, false])
        #expect(card.members.allSatisfy { $0.name.isEmpty && $0.avatarColorIndex == nil })
        #expect(card.capsuleCount == 4)
    }

    /// パレットに無い色のメンバーは、色の位置を nil にする（画面は未準備の色で塗る）
    @Test
    func unknownAvatarColorHasNoIndex() throws {
        let rooms = [Identified(id: "r", value: Self.room(name: "旅行", createdAt: Self.base, members: ["a"]))]
        let member = Member(
            displayName: "ゆい", avatarColor: "#000000", role: .owner, ready: true, joinedAt: Self.base, lastSeenAt: Self.base
        )
        let card = try #require(HomeRoomCard.cards(rooms: rooms, members: ["r": [Identified(id: "a", value: member)]]).first)
        #expect(card.members == [HomeRoomCard.Member(id: "a", name: "ゆい", avatarColorIndex: nil, isReady: true)])
    }
}

/// ホームからの行き先の出し方（03 の §1 の表示形式）
struct AppRouteTests {
    @Test
    func presentationFollowsScreenList() {
        #expect(AppRoute.createRoom.presentation == .push)
        #expect(AppRoute.room(id: "r1").presentation == .push)
        #expect(AppRoute.settings.presentation == .push)
        #expect(AppRoute.joinByCode.presentation == .sheet)
    }
}
