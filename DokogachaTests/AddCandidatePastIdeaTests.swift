//
//  AddCandidatePastIdeaTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-08 の「過去のアイデア」のタブ（`AddCandidateModel+PastIdeas.swift`。02 の §3.4 F-13）を擬似のサーバーで確かめる。
///
/// デモのルーム（`room-with-candidates`）は `AddCandidateModelTests` と同じ（投稿数 3・自分の投稿は江の島の 1 件・
/// はるかのサンシャイン水族館・そうたの明治神宮）。過去のアイデアはテストごとにサーバーに入れる
struct AddCandidatePastIdeaTests {
    typealias Base = AddCandidateModelTests

    /// 元のルームが終了した日時（新しいルーム）
    static let recent = Base.now.addingTimeInterval(-3 * 86_400)
    /// 元のルームが終了した日時（古いルーム）
    static let older = Base.now.addingTimeInterval(-30 * 86_400)

    static func idea(_ name: String, room: String, closedAt: Date, likes: Int, place: Place? = nil) -> PastIdea {
        PastIdea(
            sourceRoomId: room,
            sourceRoomName: room == "summer" ? "夏の日帰り" : "ゼミの打ち上げ",
            sourceClosedAt: closedAt,
            sourceWinnerName: room == "summer" ? "城ヶ島" : "月島もんじゃストリート",
            place: place ?? Place(name: name, area: "神奈川・鎌倉市", latitude: 35.316_7, longitude: 139.535_8, mapItemId: nil),
            category: .shrine,
            prevLikeCount: likes
        )
    }

    /// デモのルームの候補と同じ場所
    static func samePlace(as candidateID: String, in server: InMemoryServer) throws -> Place {
        try #require(server.rooms[DemoScenario.roomID]?.candidates[candidateID]?.place)
    }

    /// 自分の過去のアイデア（鎌倉大仏・新しいルーム／江の島（自分の投稿と同じ）・新しいルーム／サンシャイン水族館（はるかの投稿と同じ）・古いルーム）
    static func makeServer() throws -> InMemoryServer {
        let server = Base.makeServer()
        server.pastIdeas[DemoScenario.myUserID] = [
            "summer_c2": idea("鎌倉大仏", room: "summer", closedAt: recent, likes: 3),
            "summer_c3": idea("江の島", room: "summer", closedAt: recent, likes: 1, place: try samePlace(as: "demo-candidate-3", in: server)),
            "seminar_c2": idea(
                "サンシャイン水族館",
                room: "seminar",
                closedAt: older,
                likes: 0,
                place: try samePlace(as: Base.aquariumCandidate, in: server)
            )
        ]
        return server
    }

    static func waitUntilLoaded(_ model: AddCandidateModel) async -> Bool {
        let loaded = await Base.waitUntilLoaded(model)
        return await AsyncTestSupport.eventually { loaded && model.hasLoadedPastIdeas }
    }

    static func idea(_ id: String, in model: AddCandidateModel) throws -> Identified<PastIdea> {
        try #require(model.pastIdeas.first { $0.id == id })
    }

    /// 自分の過去のアイデアを、ルームごとに新しいルーム順で並べる（中は前回のいいねが多い順）
    @Test
    func listsPastIdeasByRoom() async throws {
        let model = Base.makeModel(server: try Self.makeServer())
        #expect(!model.hasLoadedPastIdeas)
        #expect(!model.isPastIdeasEmpty)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        #expect(model.pastIdeaGroups.map(\.roomName) == ["夏の日帰り", "ゼミの打ち上げ"])
        #expect(model.pastIdeaGroups.first?.winnerName == "城ヶ島")
        #expect(model.pastIdeaGroups.first?.ideas.map(\.id) == ["summer_c2", "summer_c3"])
        #expect(!model.isPastIdeasEmpty)
    }

    /// 過去のアイデアが無ければ、届いた後に 0 件の表示にする
    @Test
    func emptyWhenNoPastIdeas() async {
        let model = Base.makeModel(server: Base.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(model.isPastIdeasEmpty)
        #expect(model.pastIdeaGroups.isEmpty)
    }

    /// 行の状態は「場所を探す」と同じ判定（新しい場所は「持ち込む」・自分の投稿と同じは「追加済み」・ほかの人の投稿と同じは重複の確認・上限）
    @Test
    func availabilityMatchesSearch() async throws {
        let server = try Self.makeServer()
        let model = Base.makeModel(server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        #expect(model.availability(of: try Self.idea("summer_c2", in: model)) == .addable)
        #expect(model.availability(of: try Self.idea("summer_c3", in: model)) == .added)
        #expect(model.availability(of: try Self.idea("seminar_c2", in: model)) == .duplicate(candidateID: Base.aquariumCandidate))

        server.rooms[DemoScenario.roomID]?.room.settings.postLimit = 1
        #expect(await AsyncTestSupport.eventually { model.postLimit == 1 })
        #expect(model.availability(of: try Self.idea("summer_c2", in: model)) == .limitReached)
        // 上限でも、ほかの人の投稿と同じ場所は重複の確認（いいねできる）
        #expect(model.availability(of: try Self.idea("seminar_c2", in: model)) == .duplicate(candidateID: Base.aquariumCandidate))
    }

    /// 「持ち込む」で S-09 を開き（前回のカテゴリから）、投稿すると持ち込み元を付けて自分の投稿として追加し、
    /// トースト「過去のアイデアを持ち込みました」を出して S-07 に戻る。過去のアイデアは残る
    @Test
    func bringAddsCandidateFromPastIdea() async throws {
        let server = try Self.makeServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let functions = AddCandidateControlledFunctions(server: server)
        let model = Base.makeModel(server: server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.bringTapped(try Self.idea("summer_c2", in: model))
        let draft = try #require(model.draft)
        #expect(draft.pastIdeaID == "summer_c2")
        #expect(draft.category == .shrine)
        #expect(draft.place.place.name == "鎌倉大仏")
        model.note = "大仏の中に入りたい"

        await model.submit()

        #expect(functions.requests.last?.fromPastIdeaId == "summer_c2")
        #expect(toasts.current?.text == "過去のアイデアを持ち込みました")
        #expect(model.finish == .fromSheet)
        let added = try #require(server.rooms[DemoScenario.roomID]?.candidates.values.first { $0.place.name == "鎌倉大仏" })
        #expect(added.postedBy == DemoScenario.myUserID)
        #expect(added.likedBy.isEmpty)
        #expect(added.fromPastIdeaId == "summer_c2")
        #expect(added.note == "大仏の中に入りたい")
        #expect(server.pastIdeas[DemoScenario.myUserID]?["summer_c2"] != nil)
    }

    /// 「場所を探す」からの追加は持ち込み元を付けず、トーストは「候補に追加しました」のまま
    @Test
    func searchAddHasNoPastIdea() async throws {
        let server = try Self.makeServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let functions = AddCandidateControlledFunctions(server: server)
        let model = Base.makeModel(server: server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.addTapped(try Base.place("すみだ水族館"))
        #expect(model.draft?.pastIdeaID == nil)
        await model.submit()
        #expect(functions.requests.last?.fromPastIdeaId == nil)
        #expect(toasts.current?.text == "候補に追加しました")
    }

    /// ほかの人の投稿と同じ場所の「持ち込む」は、S-09 を開かずに重複の確認を出す。「追加済み」「上限」は何もしない
    @Test
    func bringDuplicateShowsPromptAndDisabledRowsDoNothing() async throws {
        let model = Base.makeModel(server: try Self.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.bringTapped(try Self.idea("summer_c3", in: model))
        #expect(model.draft == nil)
        #expect(model.duplicatePrompt == nil)

        model.bringTapped(try Self.idea("seminar_c2", in: model))
        #expect(model.draft == nil)
        #expect(model.duplicatePrompt?.candidateID == Base.aquariumCandidate)
    }

    /// 過去のアイデアの購読が失敗したら、トースト（1 回）を出し、購読し直して並べる（画面は壊さない）
    @Test
    func subscriptionFailureShowsToastAndRetries() async throws {
        let server = try Self.makeServer()
        let repository = RoomControlledRepository(server: server)
        repository.pastIdeaFailures = [AppError(.network, code: .unavailable)]
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Base.makeModel(server: server, repository: repository, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }

        #expect(await Self.waitUntilLoaded(model))
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(model.pastIdeaGroups.count == 2)
    }
}
