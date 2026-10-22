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
    /// 静止画で撮るため、きっぷとハンコは動かさない（起動引数 `-screenshot-result-animate` を付けると動かす）。
    /// 文字を最大にした画面は `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` を付けて撮る
    struct ResultScene: View {
        /// 撮る状態の起動引数
        static let modeArgument = "-screenshot-result"
        /// きっぷとハンコを動かす起動引数
        static let animateArgument = "-screenshot-result-animate"
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
            let drawID = services.inMemoryServer.flatMap { Self.prepareDraw(on: $0, roomID: roomID, winner: winner) } ?? ""
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
            animatesIn = ProcessInfo.processInfo.arguments.contains(Self.animateArgument)
        }

        var body: some View {
            ResultView(model: model, toasts: toasts, animatesIn: animatesIn)
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
