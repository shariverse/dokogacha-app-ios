//
//  CandidateDetailReportTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-10 の「この投稿を報告」（F-14。02 の §3.5・03 の S-10）を擬似のサーバーで動かし、理由のダイアログ・報告の送信・
/// 報告した人の画面でひとこととURLを隠すこと・エラーのトースト・二重送信・画面を閉じたときを確かめる
struct CandidateDetailReportTests {
    /// サンシャイン水族館（はるかの投稿・ひとことあり）
    static let aquarium = CandidateDetailModelTests.aquarium
    /// 江の島（自分の投稿）
    static let mine = CandidateDetailModelTests.mine
    /// 撮影と同じ参考 URL（はるかの候補に入れておく）
    static let url = "https://example.com/aquarium"

    /// はるかの候補に参考 URL を入れた擬似のサーバー
    static func makeServer() -> InMemoryServer {
        let server = RoomModelTests.makeServer()
        server.rooms[DemoScenario.roomID]?.candidates[aquarium]?.url = url
        return server
    }

    /// 購読を始め、そろうまで待ったモデル
    static func loadedModel(
        _ candidateID: String,
        server: InMemoryServer,
        functions: (any FunctionsClient)? = nil,
        toasts: DGToastCenter,
        reported: InMemoryReportedCandidateStore = InMemoryReportedCandidateStore()
    ) async -> (CandidateDetailModel, Task<Void, Never>) {
        let model = CandidateDetailModelTests.makeModel(
            candidateID,
            server: server,
            functions: functions,
            toasts: toasts,
            reportedCandidates: reported
        )
        let observing = Task { await model.observe() }
        _ = await CandidateDetailModelTests.waitUntilLoaded(model)
        return (model, observing)
    }

    /// 他人の投稿は「この投稿を報告」で理由のダイアログを出す。自分の投稿には出さない（押しても何もしない）
    @Test
    func reportMenuOnlyForOthersPosts() async {
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let (others, observingOthers) = await Self.loadedModel(Self.aquarium, server: Self.makeServer(), toasts: toasts)
        defer { observingOthers.cancel() }
        #expect(others.canReport)
        others.reportTapped()
        #expect(others.isChoosingReportReason)

        let (mine, observingMine) = await Self.loadedModel(Self.mine, server: Self.makeServer(), toasts: toasts)
        defer { observingMine.cancel() }
        #expect(!mine.canReport)
        mine.reportTapped()
        #expect(!mine.isChoosingReportReason)
    }

    /// 理由を選ぶと報告を送り、トースト「報告しました」。その候補のひとことと参考 URL を隠し、もう報告を出さない（02 の §3.5）
    @Test
    func reportHidesNoteAndURL() async throws {
        let server = Self.makeServer()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let reported = InMemoryReportedCandidateStore()
        let (model, observing) = await Self.loadedModel(Self.aquarium, server: server, toasts: toasts, reported: reported)
        defer { observing.cancel() }
        #expect(model.row?.note == "ペンギンが空を飛ぶ水槽が見たい")
        #expect(model.referenceURL?.absoluteString == Self.url)

        await model.report(reason: .inappropriate)

        #expect(toasts.current?.text == "報告しました")
        #expect(model.isReported)
        #expect(model.row?.note == nil)
        #expect(model.referenceURL == nil)
        #expect(!model.canReport)
        #expect(reported.hasReported(roomID: DemoScenario.roomID, candidateID: Self.aquarium))
        let report = try #require(server.reports.values.first)
        #expect(server.reports.count == 1)
        #expect(report.reporterId == DemoScenario.myUserID)
        #expect(report.candidateId == Self.aquarium)
        #expect(report.reason == .inappropriate)
        // 場所名・いいねは残す（候補そのものは変えない）
        #expect(model.row?.name == "サンシャイン水族館")
        #expect(server.rooms[DemoScenario.roomID]?.candidates[Self.aquarium]?.note == "ペンギンが空を飛ぶ水槽が見たい")
    }

    /// 別の端末で報告済み（サーバーはもう報告を持っている）でも、成功として隠す。報告は 2 つにならない
    @Test
    func alreadyReportedOnServerStillHides() async throws {
        let server = Self.makeServer()
        try server.reportCandidate(
            ReportCandidateRequest(roomId: DemoScenario.roomID, candidateId: Self.aquarium, reason: .spam),
            by: DemoScenario.myUserID
        )
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let (model, observing) = await Self.loadedModel(Self.aquarium, server: server, toasts: toasts)
        defer { observing.cancel() }
        #expect(model.canReport)

        await model.report(reason: .other)
        #expect(toasts.current?.text == "報告しました")
        #expect(model.isReported)
        #expect(server.reports.count == 1)
        #expect(server.reports.values.first?.reason == .spam)
    }

    /// 通信エラーならトースト「通信できませんでした」。隠さず、もう一度報告できる
    @Test
    func failureShowsToastAndKeepsContent() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.reportBehavior = .fail(AppError(.network))
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let (model, observing) = await Self.loadedModel(Self.aquarium, server: server, functions: functions, toasts: toasts)
        defer { observing.cancel() }

        await model.report(reason: .spam)
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(!model.isReported)
        #expect(model.row?.note == "ペンギンが空を飛ぶ水槽が見たい")
        #expect(model.canReport)
        #expect(server.reports.isEmpty)
    }

    /// 送っている途中はもう一度選んでも送らず、閉じる操作を止める（`isSending`）
    @Test
    func ignoresSecondReportWhileSending() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.reportBehavior = .suspend
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let (model, observing) = await Self.loadedModel(Self.aquarium, server: server, functions: functions, toasts: toasts)
        defer { observing.cancel() }

        model.reportReasonChosen(.spam)
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        #expect(model.isSending)
        model.reportReasonChosen(.other)
        model.reportTapped()
        #expect(!model.isChoosingReportReason)
        functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isReporting && model.isReported })
        #expect(functions.reportRequests.map(\.reason) == [.spam])
        #expect(!model.isSending)
    }

    /// 画面が消えて報告を止めたら、トーストを出さず、隠さない
    @Test
    func cancelledReportShowsNothing() async {
        let server = Self.makeServer()
        let functions = DeleteControlledFunctions(server: server)
        functions.reportBehavior = .suspend
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let (model, observing) = await Self.loadedModel(Self.aquarium, server: server, functions: functions, toasts: toasts)
        defer { observing.cancel() }

        model.reportReasonChosen(.spam)
        #expect(await AsyncTestSupport.eventually { functions.isWaiting })
        model.cancelSending()
        functions.finish()
        #expect(await AsyncTestSupport.eventually { !model.isReporting })
        #expect(!model.isReported)
        #expect(toasts.current == nil)
    }

    /// 報告した候補は、S-07 の候補の行でもひとことを隠す（同じ窓口を渡した `RoomModel`）
    @Test
    func roomRowsHideReportedNote() async throws {
        let reported = InMemoryReportedCandidateStore()
        reported.markReported(roomID: DemoScenario.roomID, candidateID: Self.aquarium)
        let model = RoomModel(
            roomID: DemoScenario.roomID,
            userID: DemoScenario.myUserID,
            repository: Self.makeServer(),
            functions: UnavailableServer(),
            toasts: DGToastCenter(),
            resubscribeDelay: RoomModelTests.immediateResubscribe,
            reportedCandidates: reported
        )
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))
        #expect(try RoomModelTests.row(model, Self.aquarium).note == nil)
        #expect(try RoomModelTests.row(model, Self.mine).note == "しらす丼を食べたい")
        #expect(model.reportedCandidateIDs == [Self.aquarium])
    }
}
