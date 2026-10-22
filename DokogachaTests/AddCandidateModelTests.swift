//
//  AddCandidateModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 候補を追加・S-09 投稿の確認（`AddCandidateModel`）を擬似のサーバーと擬似の検索で動かし、
/// 行の「追加」「追加済み」「上限」・S-09 の入力の検証とカテゴリの選び直し・投稿して S-07 に戻る・
/// 重複の確認（いいねへの誘導）・上限や状態のエラーのトースト・二重送信の防止を確かめる。
///
/// デモのルーム（`room-with-candidates`）: 投稿数 3・自分の投稿は江の島の 1 件。はるかのサンシャイン水族館（自分といいね済み）・
/// そうたの明治神宮（いいね 0）がある
struct AddCandidateModelTests {
    /// はるかのサンシャイン水族館（自分がいいね済み）
    static let aquariumCandidate = "demo-candidate-1"
    /// そうたの明治神宮（いいね 0）
    static let shrineCandidate = "demo-candidate-2"
    /// デモのデータの「今」
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func makeServer() -> InMemoryServer {
        InMemoryServer.demo(.roomWithCandidates) { Self.now }
    }

    static func makeModel(
        server: InMemoryServer,
        repository: (any RoomRepository)? = nil,
        functions: (any FunctionsClient)? = nil,
        toasts: DGToastCenter = DGToastCenter(visibleFor: .seconds(3_600)),
        sheetToasts: DGToastCenter = DGToastCenter(visibleFor: .seconds(3_600))
    ) -> AddCandidateModel {
        AddCandidateModel(
            roomID: DemoScenario.roomID,
            userID: DemoScenario.myUserID,
            repository: repository ?? server,
            functions: functions ?? server,
            places: DemoPlaceSearchService(),
            toasts: toasts,
            sheetToasts: sheetToasts,
            sleep: { _ in },
            resubscribeDelay: ResubscribeDelay(delay: .zero) { _ in }
        )
    }

    /// ルームと候補がそろうまで待つ
    static func waitUntilLoaded(_ model: AddCandidateModel, candidates: Int = 3) async -> Bool {
        await AsyncTestSupport.eventually {
            model.room != nil && model.hasLoadedCandidates && model.candidates.count == candidates
        }
    }

    /// 擬似の検索の結果 1 件
    static func place(_ query: String) throws -> SearchedPlace {
        try #require(DemoPlaceSearchService.results(for: query).first)
    }

    /// 同じ場所の候補を、ほかの人（またはこの端末の人）の投稿としてサーバーに足す（ほかの人が先に投稿した）
    static func insertCandidate(_ id: String, place: SearchedPlace, by userID: String, into server: InMemoryServer) {
        server.rooms[DemoScenario.roomID]?.candidates[id] = Candidate(
            place: place.place,
            category: place.category,
            note: "",
            url: nil,
            postedBy: userID,
            postedByName: userID,
            colorIndex: 9,
            likedBy: [],
            fromPastIdeaId: nil,
            createdAt: now
        )
    }

    // MARK: - 行の状態

    /// 新しい場所は「追加」、ほかの人の場所は重複の確認、自分の場所は「追加済み」。「n/上限」は 1/3
    @Test
    func availabilityFollowsRoom() async throws {
        let model = Self.makeModel(server: Self.makeServer())
        // 購読が届く前は押せない（追加済み・上限が分からない）
        #expect(model.availability(of: try Self.place("すみだ水族館")) == .unavailable)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        #expect(model.availability(of: try Self.place("すみだ水族館")) == .addable)
        #expect(model.availability(of: try Self.place("サンシャイン水族館")) == .duplicate(candidateID: Self.aquariumCandidate))
        #expect(model.availability(of: try Self.place("江の島")) == .added)
        #expect(model.myPostCount == 1)
        #expect(model.postLimit == 3)
    }

    /// 上限に達すると「上限」、`drawn` になると押せない（購読で変わる）
    @Test
    func availabilityFollowsLimitAndStatus() async throws {
        let server = Self.makeServer()
        let model = Self.makeModel(server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        server.rooms[DemoScenario.roomID]?.room.settings.postLimit = 1
        #expect(await AsyncTestSupport.eventually { model.postLimit == 1 })
        #expect(model.availability(of: try Self.place("すみだ水族館")) == .limitReached)
        #expect(model.availability(of: try Self.place("江の島")) == .added)

        server.rooms[DemoScenario.roomID]?.room.status = .drawn
        #expect(await AsyncTestSupport.eventually { !model.acceptsCandidates })
        #expect(model.availability(of: try Self.place("すみだ水族館")) == .unavailable)
    }

    // MARK: - S-09

    /// 「追加」で S-09 を開き、自動判定のカテゴリから始まる。押せない行では開かない
    @Test
    func addOpensDraftOnlyWhenAddable() async throws {
        let model = Self.makeModel(server: Self.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.addTapped(try Self.place("江の島"))
        #expect(model.draft == nil)
        #expect(model.duplicatePrompt == nil)

        let aquarium = try Self.place("すみだ水族館")
        model.addTapped(aquarium)
        #expect(model.draft == AddCandidateModel.Draft(place: aquarium, category: .aquarium))
        #expect(model.request?.category == .aquarium)
        #expect(model.request?.note.isEmpty == true)
        #expect(model.request?.url == nil)
        #expect(model.canSubmit)
    }

    /// ひとことは 40 文字まで（41 文字は理由を出して送れない）、参考 URL は http(s) だけ。前後の空白は取り除いて送る
    @Test
    func validatesNoteAndURL() async throws {
        let model = Self.makeModel(server: Self.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        model.addTapped(try Self.place("すみだ水族館"))

        model.note = String(repeating: "あ", count: 41)
        #expect(model.noteCheck.issue == .tooLong(limit: 40))
        #expect(model.noteCheck.characterCount == 41)
        #expect(!model.canSubmit)
        model.note = " " + String(repeating: "あ", count: 40) + " "
        #expect(model.noteCheck.issue == nil)
        #expect(model.request?.note == String(repeating: "あ", count: 40))

        model.url = "ftp://example.com"
        #expect(model.urlInput == .invalid)
        #expect(!model.canSubmit)
        model.url = "  https://example.com/a  "
        #expect(model.request?.url == "https://example.com/a")
        #expect(model.canSubmit)
    }

    /// カテゴリを選び直すと、選んだカテゴリで投稿する。投稿できたらトースト「候補に追加しました」を出し、シートから S-07 に戻る
    @Test
    func submitAddsCandidateAndReturns() async throws {
        let server = Self.makeServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(server: server, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        model.addTapped(try Self.place("すみだ水族館"))
        model.selectCategory(.art)
        model.note = "クラゲが見たい"
        model.url = "https://example.com"

        await model.submit()

        #expect(model.finish == .fromSheet)
        #expect(model.draft == nil)
        #expect(toasts.current?.text == "候補に追加しました")
        let added = try #require(server.rooms[DemoScenario.roomID]?.candidates.values.first { $0.place.name == "すみだ水族館" })
        #expect(added.category == .art)
        #expect(added.note == "クラゲが見たい")
        #expect(added.url == "https://example.com")
        #expect(added.postedBy == DemoScenario.myUserID)
        #expect(added.place.mapItemId == DemoPlaceSearchService.sumidaAquariumID)
        #expect(await AsyncTestSupport.eventually { model.myPostCount == 2 })
    }

    /// 送っている途中は、もう一度押しても送らない（二重送信）。閉じるも効かない
    @Test
    func preventsDoubleSubmit() async throws {
        let server = Self.makeServer()
        let functions = AddCandidateControlledFunctions(server: server)
        functions.behavior = .suspend
        let model = Self.makeModel(server: server, functions: functions)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        model.addTapped(try Self.place("すみだ水族館"))

        model.submitTapped()
        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        model.submitTapped()
        await model.submit()
        model.closeDraft()
        #expect(model.draft != nil)
        #expect(functions.requests.count == 1)

        functions.finish()
        #expect(await AsyncTestSupport.eventually { model.finish == .fromSheet })
        #expect(functions.requests.count == 1)
    }

    /// 上限・状態のエラーは、シートの中のトーストに出し、入力をそのままにもう一度押せる（アプリの根元には出さない）
    @Test(arguments: [
        (AppError.Reason.postLimitReached, "投稿できる数の上限に達しています"),
        (AppError.Reason.roomAlreadyDecided, "このルームはもう行き先が決まっています")
    ])
    func serverErrorShowsSheetToast(_ reason: AppError.Reason, _ message: String) async throws {
        let server = Self.makeServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let sheetToasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(server: server, toasts: toasts, sheetToasts: sheetToasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        model.addTapped(try Self.place("すみだ水族館"))
        model.note = "行きたい"
        // S-09 を開いた後で、ほかの端末から上限・状態が変わった
        switch reason {
        case .postLimitReached:
            server.rooms[DemoScenario.roomID]?.room.settings.postLimit = 1
        default:
            server.rooms[DemoScenario.roomID]?.room.status = .drawn
        }

        await model.submit()

        #expect(sheetToasts.current?.text == message)
        #expect(toasts.current == nil)
        #expect(model.finish == nil)
        #expect(model.draft != nil)
        #expect(model.note == "行きたい")
    }

    /// 画面を閉じて cancel したときは、結果によらずトーストを出さず、戻りもしない
    @Test
    func cancelledSubmitIsSilent() async throws {
        let server = Self.makeServer()
        let functions = AddCandidateControlledFunctions(server: server)
        functions.behavior = .suspend
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let sheetToasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(server: server, functions: functions, toasts: toasts, sheetToasts: sheetToasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        model.addTapped(try Self.place("すみだ水族館"))

        model.submitTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        model.cancelTasks()
        functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isSubmitting })
        #expect(toasts.current == nil)
        #expect(sheetToasts.current == nil)
        #expect(model.finish == nil)
    }
}

/// S-08・S-09 の重複の確認（02 の F-10「すでに候補にあります。いいねしますか？」）を確かめる。
/// データと道具は `AddCandidateModelTests` と同じ
struct AddCandidateDuplicateTests {
    typealias Base = AddCandidateModelTests

    /// ほかの人の場所の「追加」は、S-09 を開かずに重複の確認を出す。「いいねする」でいいねして S-07 に戻る
    @Test
    func duplicateFromListLikesAndReturns() async throws {
        let server = Base.makeServer()
        let model = Base.makeModel(server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Base.waitUntilLoaded(model))

        model.addTapped(try Base.place("明治神宮"))
        #expect(model.draft == nil)
        let prompt = try #require(model.duplicatePrompt)
        #expect(prompt.candidateID == Base.shrineCandidate)

        await model.likeDuplicate(prompt)

        #expect(model.duplicatePrompt == nil)
        #expect(model.finish == .fromList)
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Base.shrineCandidate]?.likedBy == [DemoScenario.myUserID])
    }

    /// いいね済みの候補では、いいねを書かずに戻る。キャンセルなら確認を閉じてこの画面に留まる
    @Test
    func duplicateAlreadyLikedOrCancelled() async throws {
        let server = Base.makeServer()
        let repository = RoomControlledRepository(server: server)
        let model = Base.makeModel(server: server, repository: repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Base.waitUntilLoaded(model))

        model.addTapped(try Base.place("明治神宮"))
        #expect(model.duplicatePrompt != nil)
        model.dismissDuplicatePrompt()
        #expect(model.duplicatePrompt == nil)
        #expect(model.finish == nil)

        model.addTapped(try Base.place("サンシャイン水族館"))
        let prompt = try #require(model.duplicatePrompt)
        await model.likeDuplicate(prompt)
        #expect(model.finish == .fromList)
        #expect(repository.likeCallCount == 0)
    }

    /// S-09 を開いている間にほかの人が同じ場所を投稿したら、サーバーの重複（`duplicateOf`）で確認を出す。
    /// 「いいねする」でいいねし、シートから S-07 に戻る
    @Test
    func serverDuplicateFromSheetLikesAndReturns() async throws {
        let server = Base.makeServer()
        let model = Base.makeModel(server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Base.waitUntilLoaded(model))
        let aquarium = try Base.place("すみだ水族館")
        model.addTapped(aquarium)
        Base.insertCandidate("raced", place: aquarium, by: "demo-haruka", into: server)

        await model.submit()

        let prompt = try #require(model.duplicatePrompt)
        #expect(prompt.candidateID == "raced")
        #expect(model.draft != nil)
        #expect(model.finish == nil)
        #expect(await AsyncTestSupport.eventually { model.candidates.count == 4 })

        await model.likeDuplicate(prompt)
        #expect(model.finish == .fromSheet)
        #expect(model.draft == nil)
        #expect(server.rooms[DemoScenario.roomID]?.candidates["raced"]?.likedBy == [DemoScenario.myUserID])
    }

    /// サーバーの重複が自分の投稿だったら、いいねせずに閉じる（02 の F-10）
    @Test
    func serverDuplicateOfOwnPostClosesWithoutLike() async throws {
        let server = Base.makeServer()
        let repository = RoomControlledRepository(server: server)
        let model = Base.makeModel(server: server, repository: repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Base.waitUntilLoaded(model))
        let aquarium = try Base.place("すみだ水族館")
        model.addTapped(aquarium)
        // 別の端末で、自分が同じ場所を先に投稿した
        Base.insertCandidate("mine-elsewhere", place: aquarium, by: DemoScenario.myUserID, into: server)
        #expect(await AsyncTestSupport.eventually { model.candidates.count == 4 })

        await model.submit()
        let prompt = try #require(model.duplicatePrompt)
        await model.likeDuplicate(prompt)

        #expect(model.finish == .fromSheet)
        #expect(repository.likeCallCount == 0)
    }

    /// 重複の確認からいいねを送っている間は、ほかの行の「追加」で S-09 を開かない（いいねが届くと S-07 に戻るため）
    @Test
    func addIsIgnoredWhileLiking() async throws {
        let server = Base.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.holdsLikes = true
        let model = Base.makeModel(server: server, repository: repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Base.waitUntilLoaded(model))

        model.addTapped(try Base.place("明治神宮"))
        let prompt = try #require(model.duplicatePrompt)
        model.likeDuplicateTapped(prompt)
        #expect(await AsyncTestSupport.eventually { repository.isHoldingLike })
        #expect(model.isLiking)

        model.addTapped(try Base.place("すみだ水族館"))
        #expect(model.draft == nil)

        repository.release()
        #expect(await AsyncTestSupport.eventually { model.finish == .fromList })
        #expect(model.draft == nil)
    }

    /// サーバーの重複の候補がまだ購読で届いていなければ、いいねせずに閉じる（誰の投稿か分からないため）
    @Test
    func serverDuplicateNotYetDeliveredClosesWithoutLike() async throws {
        let server = Base.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.feedCandidates()
        let model = Base.makeModel(server: server, repository: repository)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        repository.sendCandidates()
        #expect(await Base.waitUntilLoaded(model))
        let aquarium = try Base.place("すみだ水族館")
        model.addTapped(aquarium)
        // 別の端末で自分が同じ場所を先に投稿したが、この画面の購読にはまだ届いていない
        Base.insertCandidate("mine-elsewhere", place: aquarium, by: DemoScenario.myUserID, into: server)

        await model.submit()
        let prompt = try #require(model.duplicatePrompt)
        #expect(prompt.candidateID == "mine-elsewhere")
        await model.likeDuplicate(prompt)

        #expect(model.finish == .fromSheet)
        #expect(repository.likeCallCount == 0)
    }

    /// いいねの書き込みに失敗したら、トースト「通信できませんでした」を出し、この画面に留まる
    @Test
    func duplicateLikeFailureShowsToast() async throws {
        let server = Base.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.likeError = AppError(.network)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Base.makeModel(server: server, repository: repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Base.waitUntilLoaded(model))

        model.addTapped(try Base.place("明治神宮"))
        let prompt = try #require(model.duplicatePrompt)
        await model.likeDuplicate(prompt)

        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.finish == nil)
        #expect(!model.isLiking)
        #expect(repository.likeCallCount == 1)
    }
}
