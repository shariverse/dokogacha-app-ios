//
//  DemoScenario+PastIdeas.swift
//  Dokogacha
//
//  自分の過去のアイデア（F-13）のデモのデータ。`past-ideas` のシナリオで `InMemoryServer.demo(_:)` から入れる。撮影モードの scene からも足す。
//

import Foundation

extension DemoScenario {
    /// `past-ideas` の過去のアイデアの、元のルーム（夏の日帰り）の ID
    static let pastSummerRoomID = "demo-room-past-summer"
    /// `past-ideas` の過去のアイデアの、元のルーム（ゼミの打ち上げ）の ID
    static let pastSeminarRoomID = "demo-room-past-seminar"
}

extension InMemoryServer {
    /// デモの過去のアイデア 1 件の元（元の候補の ID・場所・カテゴリ・前回のいいね数）
    private struct DemoPastIdea {
        let candidateID: String
        let place: Place
        let category: PlaceCategory
        let likes: Int
    }

    /// デモの過去のアイデアの元のルーム（ルーム名・何日前に終了したか・当選・外れた候補）
    private struct DemoPastRoom {
        let roomID: String
        let name: String
        let daysAgo: Double
        let winnerName: String
        let ideas: [DemoPastIdea]
    }

    /// `past-ideas` の過去のアイデア。デモのルーム（年末の旅行）の候補と同じ場所を混ぜ、行の状態がそろうようにする:
    /// - 鎌倉大仏（前回 3 いいね）: 「持ち込む」と「前回惜しかった」
    /// - 江の島: 自分が年末の旅行に投稿済みなので「追加済み」
    /// - サンシャイン水族館（前回 4 いいね）: はるかが年末の旅行に投稿済みなので、「持ち込む」で重複の確認
    private static let demoPastRooms = [
        DemoPastRoom(
            roomID: DemoScenario.pastSummerRoomID,
            name: "夏の日帰り",
            daysAgo: 3,
            winnerName: "城ヶ島",
            ideas: [
                DemoPastIdea(
                    candidateID: "c2",
                    place: Place(name: "鎌倉大仏", area: "神奈川・鎌倉市", latitude: 35.316_7, longitude: 139.535_8, mapItemId: nil),
                    category: .shrine,
                    likes: 3
                ),
                DemoPastIdea(
                    candidateID: "c3",
                    place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.2994, longitude: 139.4800, mapItemId: nil),
                    category: .sea,
                    likes: 1
                ),
                DemoPastIdea(
                    candidateID: "c4",
                    place: Place(name: "葉山の海岸", area: "神奈川・葉山町", latitude: 35.271_9, longitude: 139.578_6, mapItemId: nil),
                    category: .sea,
                    likes: 0
                )
            ]
        ),
        DemoPastRoom(
            roomID: DemoScenario.pastSeminarRoomID,
            name: "ゼミの打ち上げ",
            daysAgo: 30,
            winnerName: "月島もんじゃストリート",
            ideas: [
                DemoPastIdea(
                    candidateID: "c2",
                    place: Place(name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.728_9, longitude: 139.719_7, mapItemId: nil),
                    category: .aquarium,
                    likes: 4
                ),
                DemoPastIdea(
                    candidateID: "c3",
                    place: Place(name: "横浜中華街", area: "神奈川・横浜市", latitude: 35.442_5, longitude: 139.646_7, mapItemId: nil),
                    category: .food,
                    likes: 2
                )
            ]
        )
    ]

    /// 自分の過去のアイデアを入れる（`past-ideas`）。ID は backend と同じ「元のルーム_元の候補」（`RoomClosing.pastIdeaID`）
    static func addPastIdeaDemo(to server: InMemoryServer, now: Date) {
        var ideas = server.pastIdeas[DemoScenario.myUserID] ?? [:]
        for room in demoPastRooms {
            let closedAt = now.addingTimeInterval(-room.daysAgo * 86_400)
            for idea in room.ideas {
                ideas[RoomClosing.pastIdeaID(roomID: room.roomID, candidateID: idea.candidateID)] = PastIdea(
                    sourceRoomId: room.roomID,
                    sourceRoomName: room.name,
                    sourceClosedAt: closedAt,
                    sourceWinnerName: room.winnerName,
                    place: idea.place,
                    category: idea.category,
                    prevLikeCount: idea.likes
                )
            }
        }
        server.pastIdeas[DemoScenario.myUserID] = ideas
    }
}
