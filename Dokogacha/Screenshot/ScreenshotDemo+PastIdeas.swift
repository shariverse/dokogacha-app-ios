//
//  ScreenshotDemo+PastIdeas.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-08 候補を追加の「過去のアイデア」のタブを、デモのルーム（`DemoScenario.roomID`）で開く（F-13）。
    ///
    /// `-demo-scenario` によらず、擬似のサーバーに `past-ideas` の過去のアイデアを足してから開く
    /// （「持ち込む」「追加済み」「前回惜しかった」が並ぶ）。起動引数 `-screenshot-past-ideas-empty` を付けると、
    /// 過去のアイデアを足さずに 0 件の表示を撮る。デモのルームが無いシナリオでは、ルームの値が届かず行を押せない形になる
    /// （撮影の既定のシナリオ `several-rooms` にはデモのルームがある）
    struct PastIdeasScene: View {
        /// 過去のアイデアを足さない起動引数
        static let emptyArgument = "-screenshot-past-ideas-empty"

        @State private var toasts: DGToastCenter
        private let model: AddCandidateModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバーと擬似の検索）
        init(services: DataServices) {
            if let server = services.inMemoryServer, !ProcessInfo.processInfo.arguments.contains(Self.emptyArgument) {
                InMemoryServer.addPastIdeaDemo(to: server, now: server.clock())
            }
            let toasts = DGToastCenter()
            model = AddCandidateModel(
                roomID: DemoScenario.roomID,
                userID: services.auth.currentUserID ?? DemoScenario.myUserID,
                repository: services.rooms,
                functions: services.functions,
                places: services.places,
                toasts: toasts
            )
            model.tab = .pastIdeas
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                AddCandidateView(model: model)
            }
            .dgToast(toasts)
        }
    }
}
