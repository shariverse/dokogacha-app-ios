//
//  ScreenshotDemo+Invite.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-04 招待を、「前回のメンバー（{前回ルーム名}・N人）を招待」を出した状態で開く（03 の S-04 の 4）。
    ///
    /// `-demo-scenario memories` の擬似のサーバーで、自分が「年末の旅行」を作った直後の S-04 を出す（ルームを作ってから開く）。
    /// 前回のルームは、いちばん新しい終了したルーム「夏の日帰り」（自分・はるか・そうた）。
    /// 起動引数 `-screenshot-invite-last-members` を付けると、ボタンが出たら押した状態（トースト「前回のメンバーN人に招待を送りました」）で開く
    struct InviteLastMembersScene: View {
        /// ボタンが出たら押しておく起動引数
        static let inviteArgument = "-screenshot-invite-last-members"
        /// ボタンが出るのを確かめる間隔と回数の上限（出なければ押さずに撮る。撮影モードだけの処理）
        private static let pollInterval: Duration = .milliseconds(50)
        private static let maxPolls = 100

        @State private var toasts = DGToastCenter()
        /// 作ったルームの S-04 の値（ルームを作るまでは nil）
        @State private var inviteModel: InviteModel?
        /// 作ったルームの前回のメンバーへの招待（ルームを作るまでは nil）
        @State private var lastMembersModel: LastMembersInviteModel?
        private let services: DataServices

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            self.services = services
        }

        var body: some View {
            NavigationStack {
                if let inviteModel, let lastMembersModel {
                    InviteView(model: inviteModel, lastMembers: lastMembersModel) {}
                }
            }
            .dgToast(toasts)
            .task {
                await open()
            }
        }

        /// ルームを作って S-04 を出し、起動引数があればボタンが出たら押す
        private func open() async {
            let request = CreateRoomRequest(name: "年末の旅行", postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost)
            guard let created = try? await services.functions.createRoom(request),
                  let code = InviteCode(created.inviteCode) else {
                return
            }
            let lastMembers = LastMembersInviteModel(
                roomID: created.roomId,
                userID: services.auth.currentUserID ?? DemoScenario.myUserID,
                repository: services.rooms,
                functions: services.functions,
                toasts: toasts
            )
            inviteModel = InviteModel(
                destination: InviteDestination(roomID: created.roomId, roomName: request.name, inviteCode: code),
                toasts: toasts
            )
            lastMembersModel = lastMembers
            guard ProcessInfo.processInfo.arguments.contains(Self.inviteArgument) else {
                return
            }
            // 画面の購読で終了したルームが届き、ボタンが出るのを待ってから押す
            var polls = 0
            while lastMembers.invitation == nil, polls < Self.maxPolls {
                try? await Task.sleep(for: Self.pollInterval)
                polls += 1
            }
            await lastMembers.invite()
        }
    }
}
