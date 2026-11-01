//
//  ScreenshotDemo+Result.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-14 結果（行き先きっぷ）を、`several-rooms` の解禁済みのルーム（週末のランチ）で開く（S-13 を通らずに、回した後の S-14 だけを出す）。
    ///
    /// はるかが回した抽選を擬似のサーバーに作り、当選する候補を決めて書き換える。起動引数 `-screenshot-result <状態>` で選ぶ（既定は `normal`）:
    /// - `normal`: いいねが多いサンシャイン水族館が当選（45%）
    /// - `rare`: いいねの無い明治神宮が当選（18%。平均 33% の 0.85 倍より小さいのでレア当選）
    ///
    /// 起動引数 `-screenshot-reroll <状態>` で引き直し（F-43）の欄の状態を選ぶ（無ければ提案前）:
    /// - `voting`: はるかが提案した投票中（賛成 1/3 人。自分はまだ投票していない）
    /// - `passed`: はるかが提案し、そうたが賛成して可決した後（「過半数が賛成。もう一度引けます」）
    /// - `used`: 可決の後に、はるかがもう一度回して明治神宮が当たった結果（「引き直しは使用済みです」）
    ///
    /// 起動引数 `-screenshot-confirm-decide` を付けると、「この行き先で決定」の確認のダイアログを出した状態で開く。
    ///
    /// 静止画で撮るため、きっぷとハンコは動かさない（起動引数 `-screenshot-result-animate` を付けると動かす）。
    /// 文字を最大にした画面は `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` を付けて撮る
    struct ResultScene: View {
        /// 撮る状態の起動引数
        static let modeArgument = "-screenshot-result"
        /// きっぷとハンコを動かす起動引数
        static let animateArgument = "-screenshot-result-animate"
        /// 引き直しの欄の状態の起動引数
        static let rerollArgument = "-screenshot-reroll"
        /// 「この行き先で決定」の確認のダイアログを出しておく起動引数
        static let confirmDecideArgument = "-screenshot-confirm-decide"
        /// 引き直しに賛成するほかの人（そうた）
        static let approver = "demo-sota"
        /// 回すほかの人（はるか）
        static let drawer = "demo-haruka"
        /// `normal` で当選させる候補（サンシャイン水族館）
        static let normalWinner = "demo-candidate-1"
        /// `rare` で当選させる候補（明治神宮）
        static let rareWinner = "demo-candidate-2"

        @State private var toasts: DGToastCenter
        @State private var model: ResultModel
        private let animatesIn: Bool

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let roomID = DemoScenario.unlockedRoomID
            let winner = ScreenshotDemo.value(after: Self.modeArgument) == "rare" ? Self.rareWinner : Self.normalWinner
            let drawID = services.inMemoryServer.flatMap { server in
                Self.prepareDraw(on: server, roomID: roomID, winner: winner).map {
                    Self.prepareReroll(on: server, roomID: roomID, drawID: $0)
                }
            } ?? ""
            let toasts = DGToastCenter()
            let model = ResultModel(
                roomID: roomID,
                drawID: drawID,
                userID: services.auth.currentUserID ?? DemoScenario.myUserID,
                repository: services.rooms,
                functions: services.functions,
                toasts: toasts
            )
            model.closing.isConfirming = ProcessInfo.processInfo.arguments.contains(Self.confirmDecideArgument)
            _model = State(initialValue: model)
            _toasts = State(initialValue: toasts)
            animatesIn = ProcessInfo.processInfo.arguments.contains(Self.animateArgument)
        }

        var body: some View {
            ResultView(model: model, toasts: toasts, animatesIn: animatesIn)
        }

        /// 起動引数の引き直しの状態にする（擬似のサーバーの提案・投票を通す）。S-14 に出す抽選の ID を返す
        private static func prepareReroll(on server: InMemoryServer, roomID: String, drawID: String) -> String {
            let mode = ScreenshotDemo.value(after: rerollArgument)
            guard let mode, ["voting", "passed", "used"].contains(mode) else {
                return drawID
            }
            try? server.proposeReroll(RoomRequest(roomId: roomID), by: drawer)
            guard mode != "voting" else {
                return drawID
            }
            try? server.voteReroll(VoteRerollRequest(roomId: roomID, approve: true), by: approver)
            guard mode == "used" else {
                return drawID
            }
            return prepareDraw(on: server, roomID: roomID, winner: rareWinner) ?? drawID
        }

        /// はるかの端末から回し、当選を `winner` に書き換える（確率は記録の重みのスナップショットから出し直す）。抽選の ID を返す
        private static func prepareDraw(on server: InMemoryServer, roomID: String, winner: String) -> String? {
            guard let response = try? server.drawGacha(RoomRequest(roomId: roomID), by: drawer),
                  var draw = server.rooms[roomID]?.draws[response.drawId] else {
                return nil
            }
            let total = draw.weights.values.reduce(0, +)
            draw.candidateId = winner
            draw.probability = total > 0 ? (draw.weights[winner] ?? 0) / total : 0
            server.rooms[roomID]?.draws[response.drawId] = draw
            server.rooms[roomID]?.room.winnerCandidateId = winner
            return response.drawId
        }
    }
}
