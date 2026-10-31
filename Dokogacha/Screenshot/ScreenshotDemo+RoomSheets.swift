//
//  ScreenshotDemo+RoomSheets.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-11・S-12・ルームから開いた S-04 で撮る状態を、起動引数からデモのルーム（`room-with-candidates`）に入れる。
    ///
    /// - `-screenshot-not-owner`: ルームの作成者をはるかにする（作成者以外の S-11（「ルームから退出」）・S-12（すべて無効）を撮るため）
    /// - `-screenshot-ready <uid,uid,…>`: そのメンバーを準備OKにする（S-07 の撮影と同じ起動引数）
    /// - `-screenshot-unlocked`: 作成者が強制解禁した状態にする（S-12 の解禁の条件が無効の状態を撮るため）
    enum RoomSheetState {
        /// 作成者をほかの人にする起動引数
        static let notOwnerArgument = "-screenshot-not-owner"
        /// 強制解禁しておく起動引数
        static let unlockedArgument = "-screenshot-unlocked"
        /// 作成者にするほかの人
        static let otherOwnerID = "demo-haruka"

        /// 起動引数の状態を擬似のサーバーに入れる（擬似のサーバーの書き込みを通すので、解禁の判定もされる）
        static func prepare(_ server: InMemoryServer, userID: String) {
            let arguments = ProcessInfo.processInfo.arguments
            let readyIDs = ScreenshotDemo.value(after: RoomScene.readyArgument)?.split(separator: ",").map(String.init) ?? []
            for memberID in readyIDs {
                server.applyDirectWrite {
                    try server.writeReady(true, roomID: DemoScenario.roomID, userID: memberID, by: memberID)
                }
            }
            if arguments.contains(unlockedArgument) {
                try? server.forceUnlock(RoomRequest(roomId: DemoScenario.roomID), by: userID)
            }
            if arguments.contains(notOwnerArgument) {
                server.rooms[DemoScenario.roomID]?.room.ownerId = otherOwnerID
                server.rooms[DemoScenario.roomID]?.members[otherOwnerID]?.role = .owner
                server.rooms[DemoScenario.roomID]?.members[userID]?.role = .member
            }
        }
    }

    /// S-11 メンバー一覧を、デモのルームの S-07 の上にシートで開く（起動引数は `RoomSheetState`）
    struct MembersScene: View {
        @State private var roomToasts = DGToastCenter()
        @State private var sheetToasts: DGToastCenter
        @State private var isPresented = true
        private let roomModel: RoomModel
        private let membersModel: MembersModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            if let server = services.inMemoryServer {
                RoomSheetState.prepare(server, userID: userID)
            }
            let sheetToasts = DGToastCenter()
            roomModel = RoomModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: DGToastCenter()
            )
            membersModel = MembersModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: sheetToasts
            )
            _sheetToasts = State(initialValue: sheetToasts)
        }

        var body: some View {
            NavigationStack {
                RoomView(model: roomModel) { _ in }
            }
            .dgToast(roomToasts)
            .sheet(isPresented: $isPresented) {
                MembersView(model: membersModel, toasts: sheetToasts) {}
            }
        }
    }

    /// S-04 招待を、デモのルームの S-07 の上にシートで開く（S-07 のアバターの並びの招待の「＋」を押したところ。起動引数は `RoomSheetState`）
    struct RoomInviteScene: View {
        /// デモのルームの名前（`InMemoryServer.demo` の年末の旅行）
        private static let roomName = "年末の旅行"

        @State private var roomToasts = DGToastCenter()
        @State private var sheetToasts: DGToastCenter
        @State private var isPresented = true
        private let roomModel: RoomModel
        private let inviteModel: InviteModel
        private let lastMembersModel: LastMembersInviteModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            if let server = services.inMemoryServer {
                RoomSheetState.prepare(server, userID: userID)
            }
            let sheetToasts = DGToastCenter()
            roomModel = RoomModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: DGToastCenter()
            )
            let code = InviteCode(DemoScenario.inviteCode) ?? InviteCode.generate { _ in 0 }
            inviteModel = InviteModel(
                destination: InviteDestination(roomID: DemoScenario.roomID, roomName: Self.roomName, inviteCode: code),
                toasts: sheetToasts
            )
            lastMembersModel = LastMembersInviteModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: sheetToasts
            )
            _sheetToasts = State(initialValue: sheetToasts)
        }

        var body: some View {
            NavigationStack {
                RoomView(model: roomModel) { _ in }
            }
            .dgToast(roomToasts)
            .sheet(isPresented: $isPresented) {
                InviteView(model: inviteModel, lastMembers: lastMembersModel, context: .sheet(toasts: sheetToasts))
            }
        }
    }

    /// S-12 ルーム設定を、デモのルームの S-07 の上にシートで開く（起動引数は `RoomSheetState`）。
    ///
    /// 起動引数 `-screenshot-post-limit <数>` で投稿数を変えた（保存できる）状態にする
    struct RoomSettingsScene: View {
        /// 投稿数を変えておく起動引数
        static let postLimitArgument = "-screenshot-post-limit"

        @State private var roomToasts = DGToastCenter()
        @State private var sheetToasts: DGToastCenter
        @State private var isPresented = true
        private let roomModel: RoomModel
        private let settingsModel: RoomSettingsModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            if let server = services.inMemoryServer {
                RoomSheetState.prepare(server, userID: userID)
            }
            let sheetToasts = DGToastCenter()
            roomModel = RoomModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: DGToastCenter()
            )
            settingsModel = RoomSettingsModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: sheetToasts
            )
            _sheetToasts = State(initialValue: sheetToasts)
        }

        var body: some View {
            NavigationStack {
                RoomView(model: roomModel) { _ in }
            }
            .dgToast(roomToasts)
            .sheet(isPresented: $isPresented) {
                RoomSettingsView(model: settingsModel, toasts: sheetToasts) {}
                    // ルームが届いてから投稿数を変える（届く前は今の値が分からず、範囲の端に戻されるため）
                    .onChange(of: settingsModel.isLoaded, initial: true) { _, isLoaded in
                        if isLoaded, let value = ScreenshotDemo.value(after: Self.postLimitArgument).flatMap(Int.init) {
                            settingsModel.postLimit = value
                        }
                    }
            }
        }
    }
}
