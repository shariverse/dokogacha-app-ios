//
//  ScreenshotDemo+CandidateDetail.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-10 候補の詳細を、デモのルーム（`room-with-candidates`）の S-07 の上にシートで開く。
    ///
    /// 起動引数で撮る状態を選ぶ:
    /// - `-screenshot-candidate <候補の ID>`: 開く候補（既定は自分の江の島 `demo-candidate-3`）
    /// - `-screenshot-not-owner`: ルームの作成者をはるかにする（他人の候補で「この候補を削除」が出ない状態を撮るため）
    /// - `-screenshot-confirm-delete`: 削除の確認のダイアログを出した状態で開く
    ///
    /// はるかのサンシャイン水族館（`demo-candidate-1`）には、参考 URL を入れておく（参考 URL の行を撮るため。撮影のデータだけ）
    struct CandidateDetailScene: View {
        /// 開く候補の起動引数
        static let candidateArgument = "-screenshot-candidate"
        /// 作成者をほかの人にする起動引数
        static let notOwnerArgument = "-screenshot-not-owner"
        /// 確認のダイアログを出しておく起動引数
        static let confirmDeleteArgument = "-screenshot-confirm-delete"
        /// 既定で開く候補（自分の江の島）
        static let defaultCandidateID = "demo-candidate-3"
        /// 参考 URL を入れておく候補（はるかのサンシャイン水族館）
        static let candidateWithURL = "demo-candidate-1"
        /// 撮影用の参考 URL
        static let demoURL = "https://sunshinecity.jp/aquarium/"

        @State private var roomToasts: DGToastCenter
        @State private var sheetToasts: DGToastCenter
        @State private var isPresented = true
        private let roomModel: RoomModel
        private let detailModel: CandidateDetailModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            let arguments = ProcessInfo.processInfo.arguments
            if let server = services.inMemoryServer {
                server.rooms[DemoScenario.roomID]?.candidates[Self.candidateWithURL]?.url = Self.demoURL
                if arguments.contains(Self.notOwnerArgument) {
                    server.rooms[DemoScenario.roomID]?.room.ownerId = "demo-haruka"
                }
            }
            let roomToasts = DGToastCenter()
            let sheetToasts = DGToastCenter()
            roomModel = RoomModel(roomID: DemoScenario.roomID, userID: userID, repository: services.rooms, toasts: roomToasts)
            let detailModel = CandidateDetailModel(
                roomID: DemoScenario.roomID,
                candidateID: ScreenshotDemo.value(after: Self.candidateArgument) ?? Self.defaultCandidateID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: sheetToasts
            )
            detailModel.isConfirmingDelete = arguments.contains(Self.confirmDeleteArgument)
            self.detailModel = detailModel
            _roomToasts = State(initialValue: roomToasts)
            _sheetToasts = State(initialValue: sheetToasts)
        }

        var body: some View {
            NavigationStack {
                RoomView(model: roomModel) { _ in }
            }
            .dgToast(roomToasts)
            .sheet(isPresented: $isPresented) {
                CandidateDetailView(model: detailModel, toasts: sheetToasts)
            }
        }
    }
}
