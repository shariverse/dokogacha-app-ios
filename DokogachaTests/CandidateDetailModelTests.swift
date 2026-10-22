//
//  CandidateDetailModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import MapKit
import Testing

/// 「マップで開く」で開いた場所を記録する（マップのアプリを開かない）
final class RecordingMapOpener: MapOpener {
    /// 開いた場所（開いた順）
    private(set) var opened: [Place] = []

    func open(_ place: Place) {
        opened.append(place)
    }
}

/// S-10 候補の詳細（`CandidateDetailModel`）を擬似のサーバーで動かし、表示・削除できる人・確認のダイアログ・削除・
/// エラーのトースト・二重送信・候補が消えたら閉じること・「マップで開く」の呼び出しを確かめる（02 の F-11・03 の S-10）。
///
/// デモのルーム（`room-with-candidates`）は自分が作成者。作成者でない場合は、テストの中で作成者をはるかに替える
struct CandidateDetailModelTests {
    /// 江の島（自分の投稿。はるかがいいね）
    static let mine = RoomModelTests.mine
    /// 明治神宮（そうたの投稿・いいね 0）
    static let shrine = RoomModelTests.shrine
    /// サンシャイン水族館（はるかの投稿・自分とそうたがいいね）
    static let aquarium = RoomModelTests.aquarium

    static func makeModel(
        _ candidateID: String,
        server: InMemoryServer,
        functions: (any FunctionsClient)? = nil,
        toasts: DGToastCenter = DGToastCenter(visibleFor: .seconds(3_600)),
        mapOpener: any MapOpener = RecordingMapOpener(),
        reportedCandidates: any ReportedCandidateStore = InMemoryReportedCandidateStore()
    ) -> CandidateDetailModel {
        CandidateDetailModel(
            roomID: DemoScenario.roomID,
            candidateID: candidateID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: functions ?? server,
            toasts: toasts,
            mapOpener: mapOpener,
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            reportedCandidates: reportedCandidates
        )
    }

    /// ルーム・メンバー・候補がそろうまで待つ
    static func waitUntilLoaded(_ model: CandidateDetailModel) async -> Bool {
        await RoomModelTests.waitUntilLoaded(model.room)
    }

    // MARK: - 表示

    /// 自分の投稿: S-07 と同じカードの値・いいねした人の名前・削除できる・報告は出さない
    @Test
    func showsOwnCandidate() async throws {
        let model = Self.makeModel(Self.mine, server: RoomModelTests.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        let row = try #require(model.row)
        #expect(row.name == "江の島")
        #expect(row.area == "神奈川・藤沢市")
        #expect(row.category == .sea)
        #expect(row.note == "しらす丼を食べたい")
        #expect(row.author == .me)
        #expect(row.likeStatus == .mine)
        // S-07 と同じ出やすさ（いいね [1, 0, 2] → [37, 18, 45]%）
        #expect(row.odds?.displayPercent == 37)
        #expect(model.likerNames == ["はるか"])
        #expect(model.place?.latitude == 35.2994)
        #expect(model.referenceURL == nil)
        #expect(model.canDelete)
        #expect(!model.canReport)
        #expect(!model.shouldClose)
    }

    /// 参考 URL は `http`・`https` のものだけを開ける形で出す
    @Test
    func referenceURLAcceptsOnlyWebSchemes() async {
        let server = RoomModelTests.makeServer()
        server.rooms[DemoScenario.roomID]?.candidates[Self.shrine]?.url = "https://www.meijijingu.or.jp/"
        server.rooms[DemoScenario.roomID]?.candidates[Self.aquarium]?.url = "javascript:alert(1)"
        let shrine = Self.makeModel(Self.shrine, server: server)
        let aquarium = Self.makeModel(Self.aquarium, server: server)
        let observing = Task { await shrine.observe() }
        let observingAquarium = Task { await aquarium.observe() }
        defer {
            observing.cancel()
            observingAquarium.cancel()
        }
        #expect(await Self.waitUntilLoaded(shrine))
        #expect(await Self.waitUntilLoaded(aquarium))

        #expect(shrine.referenceURL == URL(string: "https://www.meijijingu.or.jp/"))
        #expect(aquarium.referenceURL == nil)
    }

    /// 作成者は他人の候補も削除できる。他人の投稿には「この投稿を報告」を出す
    @Test
    func ownerCanDeleteOthersCandidate() async {
        let model = Self.makeModel(Self.aquarium, server: RoomModelTests.makeServer())
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        #expect(model.canDelete)
        #expect(model.canReport)
        #expect(model.likerNames == ["たくみ", "そうた"])
    }

    /// 作成者でなければ、他人の候補は削除できない（自分の候補は削除できる）
    @Test
    func memberCannotDeleteOthersCandidate() async {
        let server = RoomModelTests.makeServer()
        server.rooms[DemoScenario.roomID]?.room.ownerId = "demo-haruka"
        let others = Self.makeModel(Self.shrine, server: server)
        let mine = Self.makeModel(Self.mine, server: server)
        let observing = Task { await others.observe() }
        let observingMine = Task { await mine.observe() }
        defer {
            observing.cancel()
            observingMine.cancel()
        }
        #expect(await Self.waitUntilLoaded(others))
        #expect(await Self.waitUntilLoaded(mine))

        #expect(!others.canDelete)
        #expect(others.canReport)
        others.deleteTapped()
        #expect(!others.isConfirmingDelete)
        #expect(mine.canDelete)
    }

    /// 行き先が決まったら（`drawn`）、作成者も削除できない
    @Test
    func cannotDeleteAfterDrawn() async {
        let server = RoomModelTests.makeServer()
        let model = Self.makeModel(Self.mine, server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(model.canDelete)

        server.rooms[DemoScenario.roomID]?.room.status = .drawn
        #expect(await AsyncTestSupport.eventually { !model.canDelete })
        model.deleteTapped()
        #expect(!model.isConfirmingDelete)
    }

    /// 引き直しの可決の後（`unlocked`）でも、前の当選（除外した候補）は削除できない
    @Test
    func cannotDeleteDrawnCandidate() async {
        let server = RoomModelTests.makeServer()
        let model = Self.makeModel(Self.mine, server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(model.canDelete)

        server.rooms[DemoScenario.roomID]?.room.excludedCandidateIds = [Self.mine]
        #expect(await AsyncTestSupport.eventually { !model.canDelete })
    }

    // MARK: - 削除

    /// 「この候補を削除」で確認のダイアログを出し、「削除する」で `deleteCandidate` を送る。
    /// 消えた候補はいいねごと無くなり、シートを閉じる
    @Test
    func deleteAfterConfirmationClosesSheet() async throws {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        let model = Self.makeModel(Self.aquarium, server: server, functions: functions)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.deleteTapped()
        #expect(model.isConfirmingDelete)
        // 確認のダイアログを出しただけでは送らない
        #expect(functions.deleteRequests.isEmpty)

        model.confirmDeleteTapped()
        #expect(await AsyncTestSupport.eventually { model.didDelete })
        #expect(functions.deleteRequests == [CandidateRequest(roomId: DemoScenario.roomID, candidateId: Self.aquarium)])
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Self.aquarium] == nil)
        #expect(server.rooms[DemoScenario.roomID]?.room.candidateCount == 2)
        #expect(model.shouldClose)
        #expect(!model.isDeleting)
    }

    /// 送っている途中に続けて押しても、送るのは 1 回だけ（二重送信の防止）
    @Test
    func deleteIsSentOnlyOnce() async {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.deleteBehavior = .suspend
        let model = Self.makeModel(Self.mine, server: server, functions: functions)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.confirmDeleteTapped()
        model.confirmDeleteTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        #expect(model.isDeleting)
        await model.delete()
        model.deleteTapped()
        #expect(!model.isConfirmingDelete)
        #expect(functions.deleteRequests.count == 1)

        functions.finish()
        #expect(await AsyncTestSupport.eventually { model.didDelete })
        #expect(functions.deleteRequests.count == 1)
    }

    /// 通信エラーではトースト「通信できませんでした」を出し、シートは閉じずにもう一度押せる
    @Test
    func networkErrorShowsToastAndKeepsSheet() async {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.deleteBehavior = .fail(AppError(.network))
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(Self.mine, server: server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.delete()
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(!model.didDelete)
        #expect(!model.shouldClose)
        #expect(!model.isDeleting)
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Self.mine] != nil)

        functions.deleteBehavior = .pass
        await model.delete()
        #expect(model.didDelete)
    }

    /// 送っている間に行き先が決まって（`drawn`）サーバーに断られたら、その理由の文言を出す
    @Test
    func refusedByStatusShowsReason() async {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.deleteBehavior = .suspend
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(Self.mine, server: server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.confirmDeleteTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        server.rooms[DemoScenario.roomID]?.room.status = .drawn
        functions.finish()
        #expect(await AsyncTestSupport.eventually { toasts.current != nil })
        #expect(toasts.current?.text == "このルームはもう行き先が決まっています")
        #expect(!model.didDelete)
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Self.mine] != nil)
    }

    /// 権限で断られたら（投稿した人と作成者以外）、その理由の文言を出す
    @Test
    func refusedByPermissionShowsReason() async {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.deleteBehavior = .fail(ServerFailure(code: .permissionDenied, reason: AppError.Reason.notCandidateOwner.rawValue))
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(Self.shrine, server: server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        await model.delete()
        #expect(toasts.current?.text == "投稿した人と作成者だけが削除できます")
        #expect(!model.didDelete)
    }

    /// 画面が消えて削除を止めたら、トーストを出さず、閉じる指示も出さない
    @Test
    func cancelledDeleteShowsNothing() async {
        let server = RoomModelTests.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.deleteBehavior = .suspend
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = Self.makeModel(Self.mine, server: server, functions: functions, toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.confirmDeleteTapped()
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        model.cancelSending()
        functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isDeleting })
        #expect(!model.didDelete)
        #expect(toasts.current == nil)
    }

    // MARK: - 閉じる

    /// ほかの人が候補を削除して購読から消えたら、シートを閉じる
    @Test
    func closesWhenCandidateDisappears() async {
        let server = RoomModelTests.makeServer()
        let model = Self.makeModel(Self.shrine, server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        #expect(!model.shouldClose)

        server.rooms[DemoScenario.roomID]?.candidates[Self.shrine] = nil
        #expect(await AsyncTestSupport.eventually { model.shouldClose })
        #expect(!model.didDelete)
    }

    // MARK: - いいね・マップ（報告は CandidateDetailReportTests）

    /// いいねは S-07 と同じに付けられる（押すとすぐに表示が変わり、サーバーに送る）
    @Test
    func likeFromDetail() async throws {
        let server = RoomModelTests.makeServer()
        let model = Self.makeModel(Self.shrine, server: server)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))

        model.likeTapped()
        #expect(await AsyncTestSupport.eventually {
            server.rooms[DemoScenario.roomID]?.candidates[Self.shrine]?.likedBy == [DemoScenario.myUserID]
        })
        #expect(await AsyncTestSupport.eventually { model.room.pendingLikes.isEmpty && model.row?.likeStatus == .liked })
        #expect(model.likerNames == ["たくみ"])
    }

    /// 「マップで開く」は場所の座標と名前で地図を開く
    @Test
    func openInMapsPassesPlace() async throws {
        let opener = RecordingMapOpener()
        let model = Self.makeModel(Self.aquarium, server: RoomModelTests.makeServer(), mapOpener: opener)
        // 候補が届く前は開かない
        model.openInMapsTapped()
        #expect(opener.opened.isEmpty)

        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await Self.waitUntilLoaded(model))
        model.openInMapsTapped()
        let place = try #require(opener.opened.first)
        #expect(opener.opened.count == 1)
        #expect(place.name == "サンシャイン水族館")
        #expect(place.latitude == 35.728_9)
        #expect(place.longitude == 139.719_7)
    }

    /// Apple のマップに渡す `MKMapItem` は場所の名前と座標を持つ
    @Test
    func appleMapsItemHasNameAndCoordinate() {
        let place = Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.2994, longitude: 139.48, mapItemId: nil)
        let item = AppleMapsOpener.mapItem(for: place)
        #expect(item.name == "江の島")
        let coordinate = if #available(iOS 26, *) {
            item.location.coordinate
        } else {
            item.placemark.coordinate
        }
        #expect(abs(coordinate.latitude - 35.2994) < 1e-9)
        #expect(abs(coordinate.longitude - 139.48) < 1e-9)
    }
}
