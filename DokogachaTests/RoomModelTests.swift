//
//  RoomModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-07 ルーム（`RoomModel`）を擬似のサーバーで動かし、候補の並び・出やすさ・NEW・いいねの楽観的更新と失敗で戻すこと・
/// 状態ごとの押せる／押せない・購読の寿命・通信エラーのトーストを確かめる。
/// 画面（`RoomView`）の `.task` の代わりに、`observe()` を `Task` で動かして最後に cancel する。
///
/// デモのルーム（`room-with-candidates`）: メンバー 4 人（自分・はるか・そうた・みお）・共感ブースト・自分が作成者。
/// 候補は新しい順に、自分の江の島（はるかがいいね・5 分前）・そうたの明治神宮（いいね 0・30 分前）・
/// はるかのサンシャイン水族館（自分とそうたがいいね・1 時間前）。自分の `lastSeenAt` はルームの作成時（2 時間前）
struct RoomModelTests {
    /// 江の島（自分の投稿）
    static let mine = "demo-candidate-3"
    /// 明治神宮（そうたの投稿・いいね 0）
    static let shrine = "demo-candidate-2"
    /// サンシャイン水族館（はるかの投稿・自分とそうたがいいね）
    static let aquarium = "demo-candidate-1"
    /// デモのデータの「今」
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// 待たずに購読し直す
    static let immediateResubscribe = ResubscribeDelay(delay: .zero) { _ in }

    static func makeServer(_ scenario: DemoScenario = .roomWithCandidates) -> InMemoryServer {
        InMemoryServer.demo(scenario) { Self.now }
    }

    static func makeModel(
        _ repository: any RoomRepository,
        toasts: DGToastCenter = DGToastCenter(visibleFor: .seconds(3_600))
    ) -> RoomModel {
        RoomModel(
            roomID: DemoScenario.roomID,
            userID: DemoScenario.myUserID,
            repository: repository,
            toasts: toasts,
            resubscribeDelay: immediateResubscribe
        )
    }

    /// ルーム・メンバー・候補がそろうまで待つ
    static func waitUntilLoaded(_ model: RoomModel, candidates: Int = 3) async -> Bool {
        await AsyncTestSupport.eventually {
            model.loadState == .loaded && model.members.count == 4 && model.candidates.count == candidates
        }
    }

    static func row(_ model: RoomModel, _ candidateID: String) throws -> RoomCandidateRow {
        try #require(model.rows.first { $0.id == candidateID })
    }

    // MARK: - 表示

    /// 候補は新しい順（F-12）に並び、出やすさ（F-21〜23）・いいね・投稿者を映す
    @Test
    func rowsAreNewestFirstWithOddsAndLikes() async throws {
        let model = Self.makeModel(Self.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        let rows = model.rows
        #expect(rows.map(\.id) == [Self.mine, Self.shrine, Self.aquarium])
        // いいね [1, 0, 2] の重みは [2, 1, 1+√2]。合計 5.414 → [37, 18, 45]%
        #expect(rows.map { $0.odds?.displayPercent } == [37, 18, 45])
        #expect(rows.map { $0.odds?.level } == [.mid, .low, .high])
        #expect(rows.allSatisfy { $0.maxPercent == 45 })
        // 4 人のルームで投稿者以外の 2 人がいいね → 「みんな推し」
        #expect(rows.map(\.highlight) == [nil, nil, .popular])
        #expect(rows.map(\.likeStatus) == [.mine, .notLiked, .liked])
        #expect(rows.map(\.author) == [.me, .member("そうた"), .member("はるか")])
        #expect(rows[2].likers.map(\.name) == ["たくみ", "そうた"])
        #expect(rows[2].likers.map(\.avatarColorIndex) == [2, 1])
        #expect(rows[1].note == nil)
        // カプセル・あなたの投稿・準備OK・作成者
        #expect(model.capsuleCount == 3)
        #expect(model.myPostCount == 1)
        #expect(model.readyCount == 0)
        #expect(model.memberCount == 4)
        #expect(model.isOwner)
        #expect(!model.isEmpty)
    }

    /// 前回見た時刻より後のほかの人の投稿に NEW を付け、数を数える。開いている間に届いた投稿も NEW にする
    @Test
    func marksNewCandidatesSinceLastSeen() async throws {
        let server = Self.makeServer()
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        #expect(model.rows.map(\.isNew) == [false, true, true])
        #expect(model.newCount == 2)

        var added = try #require(server.rooms[DemoScenario.roomID]?.candidates[Self.shrine])
        added.place.name = "高尾山"
        added.postedBy = "demo-mio"
        added.createdAt = Self.now
        server.rooms[DemoScenario.roomID]?.candidates["demo-candidate-4"] = added
        #expect(await AsyncTestSupport.eventually { model.newCount == 3 })
        #expect(model.rows.first?.id == "demo-candidate-4")
    }

    /// 画面を離れたら `lastSeenAt` を今にする。開いている間の NEW は、開いたときの値のまま変えない
    @Test
    func recordSeenWritesLastSeenAndKeepsNewWhileOpen() async {
        let server = Self.makeServer()
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.recordSeen()
        #expect(server.rooms[DemoScenario.roomID]?.members[DemoScenario.myUserID]?.lastSeenAt == Self.now)
        #expect(await AsyncTestSupport.eventually {
            model.members.first { $0.id == DemoScenario.myUserID }?.lastSeenAt == Self.now
        })
        #expect(model.newCount == 2)

        // 次に開いたとき（新しい Model）は、書いた時刻より後の投稿だけが NEW
        let reopened = Self.makeModel(server)
        let observingAgain = Task { await reopened.observe() }
        defer { observingAgain.cancel() }
        #expect(await Self.waitUntilLoaded(reopened))
        #expect(reopened.newCount == 0)
    }

    /// 引き直しで外れた候補は出やすさの表に入らず（nil）、ほかの候補の % とカプセルの数から外れる
    @Test
    func excludedCandidateHasNoOdds() async throws {
        let server = Self.makeServer()
        server.rooms[DemoScenario.roomID]?.room.excludedCandidateIds = [Self.aquarium]
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        // いいね [1, 0] の重みは [2, 1] → [67, 33]%
        #expect(model.rows.map { $0.odds?.displayPercent } == [67, 33, nil])
        #expect(model.capsuleCount == 2)
        #expect(model.rows.count == 3)
    }

    /// みんな平等では全候補が同じ % で「平等」（F-20〜23 の AC）
    @Test
    func equalModeShowsSamePercentForAll() async {
        let server = Self.makeServer()
        server.rooms[DemoScenario.roomID]?.room.settings.likeMode = .equal
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        #expect(model.rows.map { $0.odds?.displayPercent } == [33, 33, 33])
        #expect(model.rows.allSatisfy { $0.odds?.level == .flat })
    }

    /// 候補が無ければ空の表示。候補を追加でき、ガチャは準備OKを待つ
    @Test
    func emptyRoomShowsEmptyState() async {
        let model = Self.makeModel(Self.makeServer(.oneRoom))
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model, candidates: 0))
        #expect(await AsyncTestSupport.eventually { model.isEmpty })
        #expect(model.newCount == 0)
        #expect(model.acceptsCandidates)
        #expect(model.gachaButtonState == .waiting)
    }

    /// 解禁すると「ガチャを回す」を押せ、行き先が決まったら（`drawn`）ボタンを出さず、候補を追加できない
    @Test
    func gachaButtonFollowsStatus() async {
        let server = Self.makeServer()
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(model.gachaButtonState == .waiting)

        server.rooms[DemoScenario.roomID]?.room.status = .unlocked
        #expect(await AsyncTestSupport.eventually { model.gachaButtonState == .ready })
        #expect(model.acceptsCandidates)

        server.rooms[DemoScenario.roomID]?.room.status = .drawn
        #expect(await AsyncTestSupport.eventually { model.gachaButtonState == nil })
        #expect(!model.acceptsCandidates)
    }

    // MARK: - いいね

    /// 押したらすぐに表示を変え（人数・アバター・自分の %・ほかの候補の %）、送り終えたら購読の値で確定する。
    /// 送っている途中にもう一度押しても送らない（二度押し）
    @Test
    func likeIsOptimisticAndConfirmedBySubscription() async throws {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsLikes = true
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.likeTapped(Self.shrine)
        #expect(await AsyncTestSupport.eventually { repository.isHoldingLike })
        let liked = try Self.row(model, Self.shrine)
        #expect(liked.likeStatus == .liked)
        #expect(liked.likers.map(\.id) == [DemoScenario.myUserID])
        // いいね [1, 1, 2] の重みは [2, 2, 1+√2]。合計 6.414 → [31, 31, 38]%
        #expect(model.rows.map { $0.odds?.displayPercent } == [31, 31, 38])
        #expect(try Self.row(model, Self.shrine).odds?.level == .mid)

        // 二度押し
        await model.toggleLike(Self.shrine)
        #expect(repository.likeCallCount == 1)

        repository.release()
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Self.shrine]?.likedBy == [DemoScenario.myUserID])
        #expect(try Self.row(model, Self.shrine).likeStatus == .liked)
        #expect(try Self.row(model, Self.shrine).likers.count == 1)
    }

    /// いいね済みを押すと取り消す
    @Test
    func likeAgainRemovesLike() async throws {
        let server = Self.makeServer()
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.toggleLike(Self.aquarium)
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Self.aquarium]?.likedBy == ["demo-sota"])
        #expect(await AsyncTestSupport.eventually { model.pendingLikes.isEmpty })
        #expect(try Self.row(model, Self.aquarium).likeStatus == .notLiked)
        #expect(try Self.row(model, Self.aquarium).highlight == nil)
    }

    /// 送る前に分かる失敗なら、表示を戻してトースト「通信できませんでした」を出す
    @Test
    func likeFailureRevertsAndShowsToast() async throws {
        let repository = RoomControlledRepository(server: Self.makeServer())
        repository.likeError = AppError(.serverUnavailable)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.toggleLike(Self.shrine)
        #expect(model.pendingLikes.isEmpty)
        let row = try Self.row(model, Self.shrine)
        #expect(row.likeStatus == .notLiked)
        #expect(row.likers.isEmpty)
        #expect(model.rows.map { $0.odds?.displayPercent } == [37, 18, 45])
        #expect(toasts.current?.text == "通信できませんでした")
        // 戻した後は、もう一度押せる
        repository.likeError = nil
        await model.toggleLike(Self.shrine)
        #expect(repository.likeCallCount == 2)
    }

    /// cancel（画面を閉じた）で失敗したときは、戻すだけでトーストを出さない
    @Test
    func cancelledLikeRevertsWithoutToast() async throws {
        let repository = RoomControlledRepository(server: Self.makeServer())
        repository.likeError = AppError(.cancelled, code: .cancelled)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.toggleLike(Self.shrine)
        #expect(try Self.row(model, Self.shrine).likeStatus == .notLiked)
        #expect(toasts.current == nil)
    }

    /// 自分の投稿にはいいねできない（F-20 の AC）。行き先が決まった・終了したルームでは押せない状態にして送らない
    @Test(arguments: [RoomStatus.drawn, .closed])
    func cannotLikeOwnPostOrDecidedRoom(_ status: RoomStatus) async throws {
        let server = Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        let model = Self.makeModel(repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.toggleLike(Self.mine)
        #expect(repository.likeCallCount == 0)
        #expect(try Self.row(model, Self.mine).likeStatus == .mine)

        server.rooms[DemoScenario.roomID]?.room.status = status
        #expect(await AsyncTestSupport.eventually { model.room?.status == status })
        #expect(model.rows.map(\.likeStatus) == [.mine, .locked, .lockedLiked])
        await model.toggleLike(Self.shrine)
        await model.toggleLike(Self.aquarium)
        #expect(repository.likeCallCount == 0)
    }

    // MARK: - 購読

    /// ほかの人のいいねが届いたら、すぐに映す（リアルタイム反映）
    @Test
    func reflectsOthersLikes() async throws {
        let server = Self.makeServer()
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await server.device(of: "demo-mio").setLike(true, candidateID: Self.aquarium, roomID: DemoScenario.roomID)
        #expect(await AsyncTestSupport.eventually { (try? Self.row(model, Self.aquarium))?.likers.count == 3 })
        // 投稿者以外の 3 人全員 → 「全員いいね」
        #expect(try Self.row(model, Self.aquarium).highlight == .allLiked)
    }

    /// 画面が消えた（`observe()` を cancel した）ら 3 つの購読をすべて止め、その後の変化を映さない
    @Test
    func cancellingStopsSubscriptionsAndIgnoresLaterValues() async {
        let server = Self.makeServer()
        let model = Self.makeModel(server)
        let observing = Task { await model.observe() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(server.subscriberCount == 3)

        observing.cancel()
        await observing.value
        #expect(await AsyncTestSupport.eventually { server.subscriberCount == 0 })

        server.rooms[DemoScenario.roomID]?.room.name = "年越しの旅行"
        server.rooms[DemoScenario.roomID]?.candidates[Self.shrine] = nil
        #expect(model.room?.name == "年末の旅行")
        #expect(model.candidates.count == 3)
    }

    /// 購読の失敗が続いても（3 つとも・同じ購読が 2 回）トーストは 1 回だけ。出していた値は残し、購読し直して値を受け取る
    @Test
    func repeatedFailuresShowToastOnce() async {
        let repository = RoomControlledRepository(server: Self.makeServer())
        repository.roomFailures = [AppError(.network, code: .unavailable), AppError(.permissionDenied, code: .permissionDenied)]
        repository.memberFailures = [AppError(.internal)]
        repository.candidateFailures = [AppError(.unreadableData)]
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await Self.waitUntilLoaded(model))
        #expect(toasts.current != nil)
        #expect(toasts.queue.pending.isEmpty)
    }
}
