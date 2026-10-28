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
    /// - `-screenshot-report-reasons`: 報告の理由を選ぶダイアログを出した状態で開く（F-14。他人の候補を開いたとき）
    /// - `-screenshot-reported`: 開く候補を報告した後の状態で開く（ひとことと参考 URL が隠れる。F-14）
    ///
    /// 参考 URL は、はるかのサンシャイン水族館（`demo-candidate-1`）のデモのデータに入っている
    struct CandidateDetailScene: View {
        /// 開く候補の起動引数
        static let candidateArgument = "-screenshot-candidate"
        /// 作成者をほかの人にする起動引数
        static let notOwnerArgument = "-screenshot-not-owner"
        /// 確認のダイアログを出しておく起動引数
        static let confirmDeleteArgument = "-screenshot-confirm-delete"
        /// 報告の理由のダイアログを出しておく起動引数
        static let reportReasonsArgument = "-screenshot-report-reasons"
        /// 報告した後の状態にする起動引数
        static let reportedArgument = "-screenshot-reported"
        /// 既定で開く候補（自分の江の島）
        static let defaultCandidateID = "demo-candidate-3"

        @State private var roomToasts: DGToastCenter
        @State private var sheetToasts: DGToastCenter
        @State private var isPresented = true
        private let roomModel: RoomModel
        private let detailModel: CandidateDetailModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            let arguments = ProcessInfo.processInfo.arguments
            let candidateID = ScreenshotDemo.value(after: Self.candidateArgument) ?? Self.defaultCandidateID
            if let server = services.inMemoryServer, arguments.contains(Self.notOwnerArgument) {
                server.rooms[DemoScenario.roomID]?.room.ownerId = "demo-haruka"
            }
            if arguments.contains(Self.reportedArgument) {
                services.reportedCandidates.markReported(roomID: DemoScenario.roomID, candidateID: candidateID)
            }
            let roomToasts = DGToastCenter()
            let sheetToasts = DGToastCenter()
            roomModel = RoomModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: roomToasts,
                reportedCandidates: services.reportedCandidates
            )
            let detailModel = CandidateDetailModel(
                roomID: DemoScenario.roomID,
                candidateID: candidateID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: sheetToasts,
                reportedCandidates: services.reportedCandidates
            )
            detailModel.isConfirmingDelete = arguments.contains(Self.confirmDeleteArgument)
            detailModel.isChoosingReportReason = arguments.contains(Self.reportReasonsArgument)
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
