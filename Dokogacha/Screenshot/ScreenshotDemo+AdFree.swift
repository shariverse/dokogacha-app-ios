//
//  ScreenshotDemo+AdFree.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-07 ルームを、ほかのメンバー（はるか）が広告非表示を買ったデモのルームで開く（F-51「◯◯さんのおかげで、このルームは広告なし」）。
    ///
    /// `-demo-scenario` によらず、擬似のサーバーのはるかを購入者にしてから `RoomScene` と同じように開く
    /// （撮影の既定のシナリオ `several-rooms` にはデモのルームがある）。`RoomScene` の起動引数（準備OK など）もそのまま使える
    struct RoomAdFreeScene: View {
        private let room: RoomScene

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            if let server = services.inMemoryServer {
                InMemoryServer.addAdFreeDemo(to: server)
            }
            room = RoomScene(services: services)
        }

        var body: some View {
            room
        }
    }
}
