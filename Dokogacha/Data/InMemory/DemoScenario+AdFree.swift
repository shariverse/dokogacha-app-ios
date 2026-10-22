//
//  DemoScenario+AdFree.swift
//  Dokogacha
//
//  広告非表示の購入者がいるルーム（F-51）のデモのデータ。`ad-free-room` のシナリオで `InMemoryServer.demo(_:)` から入れる。
//  撮影モードの scene（`roomAdFree`）からも足す。
//

import Foundation

extension DemoScenario {
    /// 広告非表示を買ったデモのメンバー（はるか）の uid
    static let adFreeSponsorUserID = "demo-haruka"
}

extension InMemoryServer {
    /// デモのルーム（年末の旅行）のメンバーのはるかを広告非表示の購入者にする（`users.adFree` と、ルームの `adFreeSponsor`）。
    ///
    /// はるかは自分（たくみ）の次に参加したメンバーで、ルームの購入者は最初に参加した購入者なので、はるかになる。
    /// デモのルームが無いシナリオでは、ユーザーだけを購入済みにする
    static func addAdFreeDemo(to server: InMemoryServer) {
        let sponsorID = DemoScenario.adFreeSponsorUserID
        server.users[sponsorID]?.adFree = true
        guard let member = server.rooms[DemoScenario.roomID]?.members[sponsorID] else {
            return
        }
        server.rooms[DemoScenario.roomID]?.room.adFreeSponsor = AdFreeSponsor(uid: sponsorID, displayName: member.displayName)
    }
}
