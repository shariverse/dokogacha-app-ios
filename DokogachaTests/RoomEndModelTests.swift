//
//  RoomEndModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-12 の「ルームを終了する」（`RoomEndModel`・`RoomSettingsModel.showsEndRoom`。Discussion #155）。
/// 作成者で候補募集中・ガチャ解禁！のときだけ出し、確認の後に `closeRoom` の `endEarly` を呼び、終了できたらホームへ戻る・失敗したらトースト。
///
/// `room-with-candidates` のデモのルーム「年末の旅行」: 自分が作成者・`open`
struct RoomEndModelTests {
    /// 作成者で open・unlocked のときだけ出す。drawn・closed・作成者以外では出さない
    @Test
    func showsEndRoomOnlyForOwnerBeforeDraw() async throws {
        for (status, shows) in [(RoomStatus.open, true), (.unlocked, true), (.drawn, false), (.closed, false)] {
            let fixture = try RoomSettingsModelTests.make { $0.rooms[DemoScenario.roomID]?.room.status = status }
            let observing = await RoomSettingsModelTests.observe(fixture.model)
            #expect(fixture.model.showsEndRoom == shows, "\(status)")
            #expect(fixture.model.canEndRoom == shows, "\(status)")
            observing.cancel()
        }
        let member = try RoomSettingsModelTests.make(userID: "demo-haruka")
        let observing = await RoomSettingsModelTests.observe(member.model)
        defer { observing.cancel() }
        #expect(!member.model.showsEndRoom)
    }

    /// 「ルームを終了する」で確認のダイアログを出し、「終了する」で endEarly を送ってルームを終了し、ホームへ戻る処理を呼ぶ。
    /// 終了したら room_close（early）を送る
    @Test
    func confirmEndsRoomThenGoesHome() async throws {
        let server = InMemoryServer.demo(.roomWithCandidates) { RoomModelTests.now }
        let functions = RoomSheetControlledFunctions(server: server)
        let analytics = RecordingAnalyticsService()
        let model = RoomEndModel(
            roomID: DemoScenario.roomID,
            functions: functions,
            toasts: HomeModelTests.makeToasts(),
            analytics: analytics
        )
        model.endTapped()
        #expect(model.isConfirming)

        await confirmation("ホームへ戻る") { wentHome in
            await withCheckedContinuation { continuation in
                model.confirmTapped {
                    wentHome()
                    continuation.resume()
                }
            }
        }
        #expect(server.rooms[DemoScenario.roomID]?.room.status == .closed)
        #expect(!model.isEnding && !model.isBusy)
        #expect(analytics.events == [.roomClose(auto: false, early: true)])
    }

    /// 確認の間にほかの人がガチャを回して drawn になっていたら、サーバーの文言のトーストを出し、ルームは終了しない（ホームへ戻らない）
    @Test
    func drawnMeanwhileShowsToastAndKeepsRoom() async {
        let server = InMemoryServer.demo(.roomWithCandidates) { RoomModelTests.now }
        server.rooms[DemoScenario.roomID]?.room.status = .drawn
        let toasts = HomeModelTests.makeToasts()
        let analytics = RecordingAnalyticsService()
        let model = RoomEndModel(roomID: DemoScenario.roomID, functions: server, toasts: toasts, analytics: analytics)
        #expect(await model.end() == false)
        #expect(toasts.current?.text == "このルームはもう行き先が決まっています")
        #expect(server.rooms[DemoScenario.roomID]?.room.status == .drawn)
        #expect(analytics.events.isEmpty)
    }

    /// 通信できないときは AppError の文言のトーストを出す（もう一度押せる）
    @Test
    func failureShowsToast() async {
        let toasts = HomeModelTests.makeToasts()
        let model = RoomEndModel(roomID: DemoScenario.roomID, functions: UnavailableServer(), toasts: toasts)
        #expect(await model.end() == false)
        #expect(toasts.current?.text == "通信できませんでした")
        #expect(!model.isEnding)
    }

    /// 送っている途中は二重に送らず、シートを閉じさせず、保存もできない。送り終えたら 1 回だけホームへ戻る
    @Test
    func doesNotEndTwiceAndLocksSheetWhileSending() async throws {
        let server = InMemoryServer.demo(.roomWithCandidates) { RoomModelTests.now }
        let functions = SuspendedCloseFunctions(server: server)
        let settings = RoomSettingsModel(
            roomID: DemoScenario.roomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: functions,
            toasts: HomeModelTests.makeToasts(),
            resubscribeDelay: RoomSettingsModelTests.immediateResubscribe
        )
        let observing = await RoomSettingsModelTests.observe(settings)
        defer { observing.cancel() }
        settings.name = "冬の旅行"
        #expect(settings.canSave)

        var wentHome = 0
        settings.ending.confirmTapped { wentHome += 1 }
        #expect(await AsyncTestSupport.eventually { settings.ending.isEnding && functions.isWaiting })
        #expect(settings.locksNavigation)
        #expect(!settings.canSave)
        #expect(!settings.canEndRoom)
        settings.ending.endTapped()
        #expect(!settings.ending.isConfirming)
        settings.ending.confirmTapped { wentHome += 1 }
        #expect(await settings.ending.end() == false)

        functions.finish()
        #expect(await AsyncTestSupport.eventually { wentHome == 1 && !settings.ending.isBusy })
        #expect(functions.closeRoomRequests == [CloseRoomRequest(roomId: DemoScenario.roomID, reason: .endEarly)])
    }
}
