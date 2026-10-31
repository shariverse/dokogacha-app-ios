//
//  ScreenshotDemo+Gacha.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-13 ガチャを、`several-rooms` の解禁済みのルーム（週末のランチ）で開く（ルームから進まずに、S-13 だけを出す）。
    ///
    /// 起動引数 `-screenshot-gacha <状態>` で撮る状態を選ぶ（既定は `ready`）:
    /// - `ready`: 回す前
    /// - `others`: 開いて少し後にはるかが回し、「はるかさんが回しました！」の回転中のまま止める（静止画を撮るため）
    /// - `others-live`: 開いて少し後にはるかが回し、そのまま演出を再生する（動画を撮るため）
    /// - `play`: 開いて少し後に自分がレバーを回す（動画を撮るため。カプセルが落ちたら自動で開ける）
    ///
    /// 開け終えたら、アプリと同じく同じ画面の中で S-14 に替わり、結果の演出（起動引数 `-result-animation`。無ければ標準）を流す
    /// （`GachaFlowView`。S-13 から S-14 へのつながりを動画で撮るため）。
    /// 起動引数 `-screenshot-gacha-winner <候補の ID>` を付けると、自分が回したときにその候補を当てる（S-14 の演出の案を同じ結果で見比べるため。
    /// 例: `demo-candidate-1` のサンシャイン水族館）
    struct GachaScene: View {
        /// 撮る状態の起動引数
        static let modeArgument = "-screenshot-gacha"
        /// 当てる候補の起動引数
        static let winnerArgument = "-screenshot-gacha-winner"
        /// 開いてから操作するまでの間（動画で操作の前の状態が分かるように）
        static let actionDelay: Duration = .seconds(1.5)
        /// 回すほかの人（はるか）
        static let otherDrawer = "demo-haruka"

        @State private var toasts: DGToastCenter
        @State private var model: GachaModel
        private let mode: ScreenshotGachaMode
        private let server: InMemoryServer?
        private let services: DataServices
        /// 結果の演出（撮影モードでは起動引数 `-result-animation` の演出。無ければ標準）
        @Environment(ResultRevealSetting.self) private var resultReveal: ResultRevealSetting?

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let mode = ScreenshotDemo.value(after: Self.modeArgument).flatMap(ScreenshotGachaMode.init(rawValue:)) ?? .ready
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            let roomID = DemoScenario.unlockedRoomID
            let seenDraws = InMemorySeenDrawStore()
            if let server = services.inMemoryServer, let winner = ScreenshotDemo.value(after: Self.winnerArgument) {
                Self.fixWinner(winner, on: server, roomID: roomID)
            }
            let toasts = DGToastCenter()
            // 静止画の `others` は、回転中のまま進めない
            let sleep: GachaModel.Sleep
            if mode == .others {
                sleep = { @Sendable _ in try await Task.sleep(for: .seconds(3_600)) }
            } else {
                sleep = { @Sendable duration in try await Task.sleep(for: duration) }
            }
            _model = State(initialValue: GachaModel(
                roomID: roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: toasts,
                seenDraws: seenDraws,
                sleep: sleep
            ))
            _toasts = State(initialValue: toasts)
            self.mode = mode
            server = services.inMemoryServer
            self.services = services
        }

        var body: some View {
            flow
                .task {
                    await act()
                }
        }

        /// S-13 と、開け終えた後の S-14（選んだ結果の演出を流す）
        private var flow: some View {
            GachaFlowView { onOpened in
                GachaView(model: model, toasts: toasts, onOpened: onOpened)
            } result: { drawID, _ in
                ResultView(
                    model: ResultModel(
                        roomID: DemoScenario.unlockedRoomID,
                        drawID: drawID,
                        userID: model.userID,
                        repository: services.rooms,
                        functions: services.functions,
                        toasts: toasts
                    ),
                    toasts: toasts
                )
            }
            .environment(\.resultRevealStyle, resultReveal?.style ?? .standard)
        }

        /// 抽選の乱数を差し替え、`winner` の候補が当たるようにする（重みの区間の真ん中を引く。`GachaDraw.pick`）
        private static func fixWinner(_ winner: String, on server: InMemoryServer, roomID: String) {
            guard let record = server.rooms[roomID] else {
                return
            }
            let candidates = record.candidates.map { OddsInput(id: $0.key, likeCount: $0.value.likedBy.count) }
            let entries = GachaDraw.entries(
                of: candidates,
                mode: record.room.settings.likeMode,
                excluding: Set(record.room.excludedCandidateIds)
            )
            let total = entries.reduce(0) { $0 + $1.weight }
            guard let index = entries.firstIndex(where: { $0.id == winner }), total > 0 else {
                return
            }
            let before = entries.prefix(index).reduce(0) { $0 + $1.weight }
            let middle = (before + entries[index].weight / 2) / total
            server.randomIndex = { range in min(Int(middle * Double(range)), range - 1) }
        }

        /// 状態に合わせて、少し待ってから回す
        private func act() async {
            guard mode == .others || mode == .othersLive || mode == .play else {
                return
            }
            try? await Task.sleep(for: Self.actionDelay)
            if mode == .play {
                model.leverTapped()
            } else {
                _ = try? server?.drawGacha(RoomRequest(roomId: DemoScenario.unlockedRoomID), by: Self.otherDrawer)
            }
        }
    }
}

/// S-13 の撮影モードで撮る状態（`-screenshot-gacha <rawValue>`。`ScreenshotDemo.GachaScene` の説明を参照）
enum ScreenshotGachaMode: String {
    /// 回す前
    case ready
    /// ほかの人が回した回転中のまま止める
    case others
    /// ほかの人が回した演出を再生する
    case othersLive = "others-live"
    /// 自分が回して開けるまで再生する
    case play
}
