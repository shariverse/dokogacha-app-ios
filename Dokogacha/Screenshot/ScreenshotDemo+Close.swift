//
//  ScreenshotDemo+Close.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// ホーム（S-02）の思い出のきっぷを、終了したルーム 6 つ（`memories` のデータ）で開く。
    ///
    /// `-demo-scenario` によらず、擬似のサーバーに `memories` の行き先が決まったルームと終了したルームを足してから、
    /// 通常の起動の流れ（`RootView`）でホームを出す（5 枚と「すべて見る」を撮るため。きっぷを押すと S-14 の閲覧のみも開ける）。
    /// 思い出のきっぷは画面の下の方にあるので、起動引数 `-screenshot-memories-only` を付けると進行中のルームを足さない
    struct HomeMemoriesScene: View {
        /// 進行中のルームを足さない起動引数
        static let memoriesOnlyArgument = "-screenshot-memories-only"

        private let session: ServerSession
        private let deepLinks: DeepLinkRouter

        /// - Parameters:
        ///   - session: サーバーの接続（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        ///   - deepLinks: 招待リンクの行き先（撮影では使わない）
        init(session: ServerSession, deepLinks: DeepLinkRouter) {
            self.session = session
            self.deepLinks = deepLinks
            if let server = session.services.inMemoryServer {
                let now = server.clock()
                if !ProcessInfo.processInfo.arguments.contains(Self.memoriesOnlyArgument) {
                    InMemoryServer.addDrawnDemoRooms(to: server, now: now)
                }
                InMemoryServer.addClosedDemoRooms(to: server, now: now)
            }
        }

        var body: some View {
            RootView(session: session, deepLinks: deepLinks)
        }
    }

    /// S-14 結果を、作成者以外（はるかが作った「春のお花見」）の画面で開く（「作成者が決定するとルームが終了します」を撮る）。
    ///
    /// 起動引数 `-screenshot-result-closed` を付けると、終了した（`closed`）ルームの閲覧のみの画面にする
    /// （ホームの思い出のきっぷから開いたときの画面。引き直し・決定を出さない）
    struct ResultMemberScene: View {
        /// 終了したルームにする起動引数
        static let closedArgument = "-screenshot-result-closed"

        @State private var toasts: DGToastCenter
        @State private var model: ResultModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let roomID = DemoScenario.othersDrawnRoomID
            if let server = services.inMemoryServer {
                if server.rooms[roomID] == nil {
                    InMemoryServer.addDrawnDemoRooms(to: server, now: server.clock())
                }
                if ProcessInfo.processInfo.arguments.contains(Self.closedArgument) {
                    try? server.closeRoom(CloseRoomRequest(roomId: roomID, reason: .decide), by: server.rooms[roomID]?.room.ownerId)
                }
            }
            let drawID = services.inMemoryServer?.rooms[roomID]?.room.currentDrawId ?? ""
            let toasts = DGToastCenter()
            _model = State(initialValue: ResultModel(
                roomID: roomID,
                drawID: drawID,
                userID: services.auth.currentUserID ?? DemoScenario.myUserID,
                repository: services.rooms,
                functions: services.functions,
                toasts: toasts
            ))
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            ResultView(model: model, toasts: toasts, animatesIn: false)
        }
    }
}
