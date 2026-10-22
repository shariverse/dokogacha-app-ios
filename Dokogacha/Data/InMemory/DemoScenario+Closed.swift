//
//  DemoScenario+Closed.swift
//  Dokogacha
//
//  行き先が決まったルーム（`drawn`）と終了したルーム（`closed`）のデモのデータ（F-44 の UI テスト・撮影・プレビュー用）。
//  `drawn-rooms`・`memories` のシナリオで `InMemoryServer.demo(_:)` から入れる。撮影モードの scene からも足す。
//

import Foundation

extension DemoScenario {
    /// `drawn-rooms`・`memories` の、自分が作った `drawn` のルーム（週末のランチ）の ID
    static let drawnRoomID = "demo-room-drawn-mine"
    /// `drawn-rooms`・`memories` の、はるかが作った `drawn` のルーム（春のお花見）の ID
    static let othersDrawnRoomID = "demo-room-drawn-others"
    /// `memories` の終了したルームの ID の前置き（後ろに 1〜6 の番号）
    static let closedRoomIDPrefix = "demo-room-closed-"
}

extension InMemoryServer {
    /// デモの人（uid・表示名・アバターの色の位置）。`DemoScenario.swift` のデモのメンバーと同じ
    private struct ClosedDemoPerson {
        let id: String
        let name: String
        let colorIndex: Int
    }

    /// デモの場所（場所名・エリア・カテゴリ）
    private struct ClosedDemoPlace {
        let name: String
        let area: String
        let category: PlaceCategory

        init(_ name: String, _ area: String, _ category: PlaceCategory) {
            self.name = name
            self.area = area
            self.category = category
        }
    }

    /// デモの候補（ID・場所・投稿した人・いいねした人）
    private struct ClosedDemoCandidate {
        let id: String
        let place: ClosedDemoPlace
        let author: ClosedDemoPerson
        let likedBy: [String]
    }

    /// 終了したルームの元（ルーム名・何日前に終了したか・当選・外れた候補）
    private struct ClosedDemoRoom {
        let name: String
        let daysAgo: Double
        let winner: ClosedDemoPlace
        let losers: [ClosedDemoPlace]
    }

    private static let closedDemoMe = ClosedDemoPerson(id: DemoScenario.myUserID, name: "たくみ", colorIndex: 2)
    private static let closedDemoHaruka = ClosedDemoPerson(id: "demo-haruka", name: "はるか", colorIndex: 0)
    private static let closedDemoSota = ClosedDemoPerson(id: "demo-sota", name: "そうた", colorIndex: 1)
    private static let closedDemoMio = ClosedDemoPerson(id: "demo-mio", name: "みお", colorIndex: 3)

    /// `memories` の終了したルーム（新しい順。6 件あるので、ホームでは 5 件と「すべて見る」になる）
    private static let closedDemoRooms = [
        ClosedDemoRoom(
            name: "夏の日帰り",
            daysAgo: 3,
            winner: ClosedDemoPlace("城ヶ島", "神奈川・三浦市", .sea),
            losers: [
                ClosedDemoPlace("江の島", "神奈川・藤沢市", .sea),
                ClosedDemoPlace("鎌倉大仏", "神奈川・鎌倉市", .shrine),
                ClosedDemoPlace("葉山の海岸", "神奈川・葉山町", .sea),
                ClosedDemoPlace("三崎港", "神奈川・三浦市", .food)
            ]
        ),
        ClosedDemoRoom(
            name: "サークルの合宿",
            daysAgo: 12,
            winner: ClosedDemoPlace("チームラボプラネッツ TOKYO", "東京・江東区", .art),
            losers: []
        ),
        ClosedDemoRoom(
            name: "ゼミの打ち上げ",
            daysAgo: 30,
            winner: ClosedDemoPlace("月島もんじゃストリート", "東京・中央区", .food),
            losers: [
                ClosedDemoPlace("浅草の天ぷら", "東京・台東区", .food),
                ClosedDemoPlace("横浜中華街", "神奈川・横浜市", .food)
            ]
        ),
        ClosedDemoRoom(
            name: "家族でおでかけ",
            daysAgo: 60,
            winner: ClosedDemoPlace("上野動物園", "東京・台東区", .park),
            losers: [
                ClosedDemoPlace("葛西臨海水族園", "東京・江戸川区", .aquarium)
            ]
        ),
        ClosedDemoRoom(
            name: "秋の紅葉狩り",
            daysAgo: 90,
            winner: ClosedDemoPlace("高尾山", "東京・八王子市", .nature),
            losers: [
                ClosedDemoPlace("昭和記念公園", "東京・立川市", .park),
                ClosedDemoPlace("御岳山", "東京・青梅市", .nature)
            ]
        ),
        ClosedDemoRoom(
            name: "冬のイルミネーション",
            daysAgo: 120,
            winner: ClosedDemoPlace("よみうりランド", "東京・稲城市", .activity),
            losers: [
                ClosedDemoPlace("丸の内", "東京・千代田区", .town)
            ]
        )
    ]

    /// `drawn-rooms`・`memories` のルームを入れる（ほかのシナリオでは何もしない）
    static func addClosingDemoRooms(_ scenario: DemoScenario, to server: InMemoryServer, now: Date) {
        guard scenario == .drawnRooms || scenario == .memories else {
            return
        }
        addDrawnDemoRooms(to: server, now: now)
        if scenario == .memories {
            addClosedDemoRooms(to: server, now: now)
        }
    }

    /// 行き先が決まった（`drawn`）ルームを 2 つ入れる（`drawn-rooms`・`memories`）。
    ///
    /// - 「週末のランチ」: 自分が作ったルーム（自分・はるか・そうた）。自分が 1 時間前に回し、サンシャイン水族館が当選
    /// - 「春のお花見」: はるかが作ったルーム（はるか・自分・みお）。はるかが 2 時間前に回し、明治神宮が当選
    static func addDrawnDemoRooms(to server: InMemoryServer, now: Date) {
        server.rooms[DemoScenario.drawnRoomID] = drawnDemoRoom(
            name: "週末のランチ",
            people: [closedDemoMe, closedDemoHaruka, closedDemoSota],
            candidates: [
                ClosedDemoCandidate(
                    id: "drawn-mine-1",
                    place: ClosedDemoPlace("サンシャイン水族館", "東京・豊島区", .aquarium),
                    author: closedDemoHaruka,
                    likedBy: [closedDemoMe.id, closedDemoSota.id]
                ),
                ClosedDemoCandidate(
                    id: "drawn-mine-2",
                    place: ClosedDemoPlace("明治神宮", "東京・渋谷区", .shrine),
                    author: closedDemoSota,
                    likedBy: []
                ),
                ClosedDemoCandidate(
                    id: "drawn-mine-3",
                    place: ClosedDemoPlace("江の島", "神奈川・藤沢市", .sea),
                    author: closedDemoMe,
                    likedBy: [closedDemoHaruka.id]
                )
            ],
            winnerID: "drawn-mine-1",
            drawnAt: now.addingTimeInterval(-3_600)
        )
        server.rooms[DemoScenario.othersDrawnRoomID] = drawnDemoRoom(
            name: "春のお花見",
            people: [closedDemoHaruka, closedDemoMe, closedDemoMio],
            candidates: [
                ClosedDemoCandidate(
                    id: "drawn-others-1",
                    place: ClosedDemoPlace("新宿御苑", "東京・新宿区", .park),
                    author: closedDemoHaruka,
                    likedBy: [closedDemoMio.id]
                ),
                ClosedDemoCandidate(
                    id: "drawn-others-2",
                    place: ClosedDemoPlace("明治神宮", "東京・渋谷区", .shrine),
                    author: closedDemoMio,
                    likedBy: [closedDemoMe.id, closedDemoHaruka.id]
                )
            ],
            winnerID: "drawn-others-2",
            drawnAt: now.addingTimeInterval(-7_200)
        )
    }

    /// 終了した（`closed`）ルームを 6 つ入れ、当選しなかった候補をメンバーの過去のアイデアに登録する（`memories`）
    static func addClosedDemoRooms(to server: InMemoryServer, now: Date) {
        for (index, source) in closedDemoRooms.enumerated() {
            let roomID = "\(DemoScenario.closedRoomIDPrefix)\(index + 1)"
            let closedAt = now.addingTimeInterval(-source.daysAgo * 86_400)
            let people = [closedDemoMe, closedDemoHaruka, closedDemoSota]
            let places = [source.winner] + source.losers
            var record = drawnDemoRoom(
                name: source.name,
                people: people,
                candidates: places.enumerated().map { offset, place in
                    let author = people[offset % people.count]
                    let likers = people.filter { $0.id != author.id }.prefix(offset == 0 ? 2 : offset % 2).map(\.id)
                    return ClosedDemoCandidate(id: "\(roomID)-c\(offset + 1)", place: place, author: author, likedBy: Array(likers))
                },
                winnerID: "\(roomID)-c1",
                drawnAt: closedAt.addingTimeInterval(-86_400)
            )
            record.room.status = .closed
            record.room.closedAt = closedAt
            server.rooms[roomID] = record
            server.registerPastIdeas(roomID: roomID)
        }
    }

    /// 行き先が決まったルーム（先頭の人が作成者。全員が準備OK。`winnerID` が当選し、先頭の人が回した抽選の記録がある）
    private static func drawnDemoRoom(
        name: String,
        people: [ClosedDemoPerson],
        candidates: [ClosedDemoCandidate],
        winnerID: String,
        drawnAt: Date
    ) -> RoomRecord {
        let createdAt = drawnAt.addingTimeInterval(-86_400)
        let drawID = "\(winnerID)-draw"
        var record = RoomRecord(room: Room(
            name: name,
            ownerId: people.first?.id ?? DemoScenario.myUserID,
            inviteCode: "",
            status: .drawn,
            settings: RoomSettings(postLimit: DomainConstants.Limits.defaultPostLimit, unlockRule: .all, deadlineAt: nil, likeMode: .boost),
            forcedUnlock: false,
            memberIds: people.map(\.id),
            memberCount: people.count,
            readyCount: people.count,
            candidateCount: candidates.count,
            adFreeSponsor: nil,
            currentDrawId: drawID,
            winnerCandidateId: winnerID,
            excludedCandidateIds: [],
            reroll: .initial,
            createdAt: createdAt,
            drawnAt: drawnAt,
            closedAt: nil
        ))
        record.members = demoMembers(people, createdAt: createdAt, seenAt: drawnAt)
        for (offset, candidate) in candidates.enumerated() {
            record.candidates[candidate.id] = Candidate(
                place: Place(name: candidate.place.name, area: candidate.place.area, latitude: 35.68, longitude: 139.76, mapItemId: nil),
                category: candidate.place.category,
                note: "",
                url: nil,
                postedBy: candidate.author.id,
                postedByName: candidate.author.name,
                colorIndex: offset,
                likedBy: candidate.likedBy,
                fromPastIdeaId: nil,
                createdAt: createdAt.addingTimeInterval(Double(offset) * 600)
            )
        }
        record.draws[drawID] = demoDraw(of: record, winnerID: winnerID, drawer: people.first ?? closedDemoMe, at: drawnAt)
        return record
    }

    /// 先頭の人が回した抽選の記録（重みと当選確率はルームの候補から出す。`drawGacha` と同じ式）
    private static func demoDraw(of record: RoomRecord, winnerID: String, drawer: ClosedDemoPerson, at drawnAt: Date) -> Draw {
        let inputs = record.candidates.map { OddsInput(id: $0.key, likeCount: $0.value.likedBy.count) }
        let entries = GachaDraw.entries(of: inputs, mode: .boost, excluding: [])
        return Draw(
            candidateId: winnerID,
            probability: Probability.odds(of: inputs, mode: .boost)[winnerID]?.probability ?? 0,
            weights: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.weight) }),
            drawnBy: drawer.id,
            drawnByName: drawer.name,
            isReroll: false,
            createdAt: drawnAt
        )
    }

    /// メンバー（先頭の人が作成者。全員が準備OK）
    private static func demoMembers(_ people: [ClosedDemoPerson], createdAt: Date, seenAt: Date) -> [String: Member] {
        var members: [String: Member] = [:]
        for (offset, person) in people.enumerated() {
            let joinedAt = createdAt.addingTimeInterval(Double(offset) * 60)
            members[person.id] = Member(
                displayName: person.name,
                avatarColor: AvatarPalette.colors[person.colorIndex],
                role: offset == 0 ? .owner : .member,
                ready: true,
                joinedAt: joinedAt,
                lastSeenAt: seenAt
            )
        }
        return members
    }
}
