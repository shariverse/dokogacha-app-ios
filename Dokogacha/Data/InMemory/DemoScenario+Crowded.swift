//
//  DemoScenario+Crowded.swift
//  Dokogacha
//
//  メンバーの多いルームのデモのデータ。`crowded-room`・`full-room` のシナリオで `InMemoryServer.demo(_:)` から入れる。
//  S-07 のルームパネルのアバターの並び（6 人＋「+N」）と、招待のボタン（満員のときは押せない）の UI テスト・撮影用。
//

import Foundation

extension DemoScenario {
    /// `crowded-room` のデモのルームの人数（7 人以上なので、ルームパネルは 6 人＋「+N」になる）
    static let crowdedMemberCount = 10

    /// シナリオのデモのルームの人数（メンバーを足さないシナリオでは nil）
    var demoRoomMemberCount: Int? {
        switch self {
        case .crowdedRoom: Self.crowdedMemberCount
        case .fullRoom: DomainConstants.Limits.maxMembers
        default: nil
        }
    }
}

extension InMemoryServer {
    /// 足すメンバーの表示名（参加順。先頭の文字がばらけるように選ぶ）
    private static let guestNames = [
        "ゆい", "けんた", "あおい", "りく", "さくら", "はると", "めい", "こうき",
        "ひなた", "ねね", "かいと", "えま", "しょう", "つむぎ", "らん", "いつき"
    ]

    /// デモのルーム（年末の旅行）にメンバーを足して `memberCount` 人にする（自分・はるか・そうた・みおの後に、1 分ずつ遅れて参加した順）。
    ///
    /// 足したメンバーは準備OKでなく、候補を投稿していない。プロフィール（`users`）も入れる（擬似のサーバーの Callable が読むため）
    /// - Parameters:
    ///   - server: 入れる擬似のサーバー（デモのルームが無ければ何もしない）
    ///   - memberCount: ルームの人数（今の人数以下なら何もしない）
    ///   - now: 今の日時
    static func addGuests(to server: InMemoryServer, upTo memberCount: Int, now: Date) {
        guard var record = server.rooms[DemoScenario.roomID] else {
            return
        }
        let guestCount = min(memberCount - record.room.memberIds.count, guestNames.count)
        guard guestCount > 0 else {
            return
        }
        let lastJoinedAt = record.members.values.map(\.joinedAt).max() ?? now
        for (offset, name) in guestNames.prefix(guestCount).enumerated() {
            let guestID = "demo-guest-\(offset + 1)"
            let color = AvatarPalette.colors[offset % AvatarPalette.colors.count]
            let joinedAt = lastJoinedAt.addingTimeInterval(Double(offset + 1) * 60)
            server.users[guestID] = UserProfile(displayName: name, avatarColor: color, adFree: false, fcmTokens: [], createdAt: joinedAt)
            record.members[guestID] = Member(
                displayName: name,
                avatarColor: color,
                role: .member,
                ready: false,
                joinedAt: joinedAt,
                lastSeenAt: joinedAt
            )
            record.room.memberIds.append(guestID)
        }
        record.room.memberCount = record.room.memberIds.count
        server.rooms[DemoScenario.roomID] = record
    }
}
