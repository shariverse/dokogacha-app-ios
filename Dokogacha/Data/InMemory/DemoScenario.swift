//
//  DemoScenario.swift
//  Dokogacha
//

import Foundation

/// 擬似のサーバーに入れるデモのデータ。UI テストは `-uiTesting -demo-scenario <rawValue>` で選ぶ。
///
/// 最小限から始め、画面のタスクと UI テスト（タスク 44）で要るものを足す。
/// どのシナリオでも、この端末のユーザー（`DemoScenario.myUserID`）はサインイン済みで始まる。
nonisolated enum DemoScenario: String, CaseIterable, Sendable {
    /// 表示名をまだ登録していない（初回起動。S-01 を出す）
    case firstLaunch = "first-launch"
    /// 表示名を登録済みで、ルームが無い
    case empty
    /// 自分が作った `open` のルームが 1 つあり、ほかのメンバーが 3 人いる。候補は無い
    case oneRoom = "one-room"
    /// `one-room` に、ほかのメンバーの候補（いいね付き）と自分の候補がある
    case roomWithCandidates = "room-with-candidates"
    /// 進行中のルームが 3 つある（ホームの撮影・プレビュー用）。`room-with-candidates` のルームに、解禁済みのルームと、
    /// ほかの人が作ったルームを足したもの
    case severalRooms = "several-rooms"
    /// 表示名を登録済みで、自分のルームは無い。ほかの人のルームが 3 つあり、招待コードで参加できるもの（`joinableInviteCode`）・
    /// 満員のもの（`fullInviteCode`）・行き先が決まったもの（`decidedInviteCode`）がある（S-05・S-06 の UI テスト・撮影用）
    case joinable
    /// 表示名をまだ登録していない（S-01 を出す）。`joinable` と同じ、ほかの人のルームが 3 つある
    /// （登録する前に招待リンクで開かれ、登録した後に S-06 が開く UI テスト用）
    case firstLaunchInvited = "first-launch-invited"
    /// 表示名を登録済みで、行き先が決まった（`drawn`）ルームが 2 つある（自分が作ったもの・はるかが作ったもの）。
    /// 終了したルームは無い（S-14 の「この行き先で決定」から思い出のきっぷが出るまでの UI テスト用。`DemoScenario+Closed.swift`）
    case drawnRooms = "drawn-rooms"
    /// `drawn-rooms` に、終了した（`closed`）ルームを 6 つ足したもの（ホームの思い出のきっぷの撮影・プレビュー用）
    case memories
    /// `room-with-candidates` に、自分の過去のアイデア（2 つのルームの 5 件）を足したもの
    /// （S-08 の「過去のアイデア」から持ち込む UI テスト・撮影用。`DemoScenario+PastIdeas.swift`）
    case pastIdeas = "past-ideas"
    /// `room-with-candidates` の、ほかのメンバー（はるか）が広告非表示を買っていて、ルームが広告なしのもの
    /// （S-07 の「◯◯さんのおかげで、このルームは広告なし」の UI テスト・撮影用。F-51。`DemoScenario+AdFree.swift`）
    case adFreeRoom = "ad-free-room"
    /// `room-with-candidates` のルームにメンバーを足して 10 人にしたもの（S-07 のアバターの 6 人＋「+N」の UI テスト・撮影用。`DemoScenario+Crowded.swift`）
    case crowdedRoom = "crowded-room"
    /// `room-with-candidates` のルームにメンバーを足して満員（20 人）にしたもの（S-07 の招待のボタンを押せない UI テスト・撮影用）
    case fullRoom = "full-room"

    /// 表示名をまだ登録していないシナリオか（自分とほかのメンバーのプロフィールを入れない）
    var isFirstLaunch: Bool {
        self == .firstLaunch || self == .firstLaunchInvited
    }

    /// 起動引数でシナリオを選ぶときの名前（`-demo-scenario <rawValue>`）
    static let argument = "-demo-scenario"
    /// 起動引数で選ばなかったとき・知らない名前のときのシナリオ
    static let fallback: Self = .empty
    /// 撮影モードで起動引数で選ばなかったときのシナリオ（App Store のホームの画面にルームを並べる）
    static let screenshotFallback: Self = .severalRooms

    /// この端末のユーザーの uid
    static let myUserID = "demo-me"
    /// デモのルームの ID
    static let roomID = "demo-room"
    /// `several-rooms` の解禁済みのルームの ID
    static let unlockedRoomID = "demo-room-unlocked"
    /// `several-rooms` のほかの人が作ったルームの ID
    static let othersRoomID = "demo-room-others"
    /// デモのルームの招待コード（`DK7-29Q`）
    static let inviteCode = "DK729Q"
    /// `joinable` の参加できるルーム（はるかが作った `open` のルーム）の ID
    static let joinableRoomID = "demo-room-joinable"
    /// `joinable` の参加できるルームの招待コード（`QW5-8RT`）
    static let joinableInviteCode = "QW58RT"
    /// `joinable` の満員（20 人）のルームの招待コード（`MX7-4EP`）
    static let fullInviteCode = "MX74EP"
    /// `joinable` の行き先が決まった（`drawn`）ルームの招待コード（`DR6-3WN`）
    static let decidedInviteCode = "DR63WN"

    /// 起動引数から選ぶ（`-demo-scenario` の次の値。無い・知らないなら `fallback`）
    static func from(arguments: [String], fallback: Self = fallback) -> Self {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
            return fallback
        }
        return Self(rawValue: arguments[index + 1]) ?? fallback
    }
}

extension InMemoryServer {
    /// デモのメンバー（uid・表示名・アバターの色の位置）
    private struct DemoPerson {
        let id: String
        let name: String
        let colorIndex: Int
    }

    /// 自分とほかのメンバー（参加順）
    private static let demoPeople = [
        DemoPerson(id: DemoScenario.myUserID, name: "たくみ", colorIndex: 2),
        DemoPerson(id: "demo-haruka", name: "はるか", colorIndex: 0),
        DemoPerson(id: "demo-sota", name: "そうた", colorIndex: 1),
        DemoPerson(id: "demo-mio", name: "みお", colorIndex: 3)
    ]

    /// シナリオのデータを入れた擬似のサーバーを作る。日時は `clock` の今からの相対で決める
    static func demo(_ scenario: DemoScenario, clock: @escaping () -> Date = { Date() }) -> InMemoryServer {
        let server = InMemoryServer(clock: clock, signedInUserID: DemoScenario.myUserID)
        let now = clock()
        if !scenario.isFirstLaunch {
            for (offset, person) in demoPeople.enumerated() {
                server.users[person.id] = UserProfile(
                    displayName: person.name,
                    avatarColor: AvatarPalette.colors[person.colorIndex],
                    adFree: false,
                    fcmTokens: [],
                    createdAt: now.addingTimeInterval(-Double(offset + 1) * 86_400)
                )
            }
        }
        if [.oneRoom, .roomWithCandidates, .severalRooms, .pastIdeas, .adFreeRoom, .crowdedRoom, .fullRoom].contains(scenario) {
            server.rooms[DemoScenario.roomID] = demoRoom(now: now)
            let codeEntry = InviteCodeEntry(roomId: DemoScenario.roomID, createdAt: now.addingTimeInterval(-7_200))
            server.inviteCodes[DemoScenario.inviteCode] = codeEntry
        }
        if [.roomWithCandidates, .severalRooms, .pastIdeas, .adFreeRoom, .crowdedRoom, .fullRoom].contains(scenario) {
            server.rooms[DemoScenario.roomID]?.candidates = demoCandidates(now: now)
            server.rooms[DemoScenario.roomID]?.room.candidateCount = 3
        }
        if let memberCount = scenario.demoRoomMemberCount {
            addGuests(to: server, upTo: memberCount, now: now)
        }
        if scenario == .severalRooms {
            server.rooms[DemoScenario.unlockedRoomID] = unlockedRoom(now: now)
            server.rooms[DemoScenario.othersRoomID] = othersRoom(now: now)
            server.inviteCodes["HN48PX"] = InviteCodeEntry(
                roomId: DemoScenario.unlockedRoomID,
                createdAt: now.addingTimeInterval(-3_600)
            )
            server.inviteCodes["MR36TW"] = InviteCodeEntry(
                roomId: DemoScenario.othersRoomID,
                createdAt: now.addingTimeInterval(-86_400)
            )
        }
        if scenario == .joinable || scenario == .firstLaunchInvited {
            addJoinableRooms(to: server, now: now)
        }
        addClosingDemoRooms(scenario, to: server, now: now)
        if scenario == .pastIdeas {
            addPastIdeaDemo(to: server, now: now)
        }
        if scenario == .adFreeRoom {
            addAdFreeDemo(to: server)
        }
        return server
    }

    /// `joinable` のルーム（どれも自分はメンバーでない）を入れる。
    ///
    /// - 「夏の花火大会」: はるかが作った `open` のルーム（はるか・そうた・みお。候補 2 件）。参加できる
    /// - 「社員旅行」: そうたが作った満員のルーム（そうたとゲスト 19 人の 20 人）
    /// - 「去年の忘年会」: みおが作った `drawn` のルーム（みお・はるか）
    private static func addJoinableRooms(to server: InMemoryServer, now: Date) {
        let haruka = demoPeople[1]
        let sota = demoPeople[2]
        let mio = demoPeople[3]
        let guests = (1..<DomainConstants.Limits.maxMembers).map { index in
            DemoPerson(id: "demo-guest-\(index)", name: "ゲスト\(index)", colorIndex: index % AvatarPalette.colors.count)
        }
        var joinable = othersRoom(name: "夏の花火大会", code: DemoScenario.joinableInviteCode, people: [haruka, sota, mio], now: now)
        joinable.candidates = demoCandidates(now: now).filter { $0.value.postedBy != DemoScenario.myUserID }
        joinable.room.candidateCount = joinable.candidates.count
        var decided = othersRoom(name: "去年の忘年会", code: DemoScenario.decidedInviteCode, people: [mio, haruka], now: now)
        decided.room.status = .drawn
        let rooms = [
            (DemoScenario.joinableRoomID, joinable),
            ("demo-room-full", othersRoom(name: "社員旅行", code: DemoScenario.fullInviteCode, people: [sota] + guests, now: now)),
            ("demo-room-decided", decided)
        ]
        for (roomID, record) in rooms {
            server.rooms[roomID] = record
            server.inviteCodes[record.room.inviteCode] = InviteCodeEntry(roomId: roomID, createdAt: record.room.createdAt)
        }
    }

    /// ほかの人（`people` の先頭）が作った `open` のルーム。メンバーは `people`（参加順）で、候補は無い
    private static func othersRoom(name: String, code: String, people: [DemoPerson], now: Date) -> RoomRecord {
        var record = demoRoom(now: now)
        let createdAt = now.addingTimeInterval(-86_400)
        record.room.name = name
        record.room.inviteCode = code
        record.room.ownerId = people.first?.id ?? DemoScenario.myUserID
        record.room.memberIds = people.map(\.id)
        record.room.memberCount = people.count
        record.room.createdAt = createdAt
        record.members = [:]
        for (offset, person) in people.enumerated() {
            let joinedAt = createdAt.addingTimeInterval(Double(offset) * 60)
            record.members[person.id] = Member(
                displayName: person.name,
                avatarColor: AvatarPalette.colors[person.colorIndex],
                role: offset == 0 ? .owner : .member,
                ready: false,
                joinedAt: joinedAt,
                lastSeenAt: joinedAt
            )
        }
        return record
    }

    /// `several-rooms` の解禁済みのルーム（自分・はるか・そうたの全員が準備OK。候補 3 件）。いちばん新しい
    private static func unlockedRoom(now: Date) -> RoomRecord {
        var record = demoRoom(now: now)
        let createdAt = now.addingTimeInterval(-3_600)
        let people = Array(demoPeople.prefix(3))
        record.room.name = "週末のランチ"
        record.room.inviteCode = "HN48PX"
        record.room.status = .unlocked
        record.room.memberIds = people.map(\.id)
        record.room.memberCount = people.count
        record.room.readyCount = people.count
        record.room.candidateCount = 3
        record.room.createdAt = createdAt
        record.members = record.members.filter { people.map(\.id).contains($0.key) }
        for userID in record.members.keys {
            record.members[userID]?.ready = true
        }
        record.candidates = demoCandidates(now: now)
        return record
    }

    /// `several-rooms` の、はるかが作ったルーム（自分・はるか・みお。候補なし）。いちばん古い
    private static func othersRoom(now: Date) -> RoomRecord {
        var record = demoRoom(now: now)
        let createdAt = now.addingTimeInterval(-86_400)
        let haruka = demoPeople[1]
        let people = [haruka, demoPeople[0], demoPeople[3]]
        record.room.name = "春のお花見"
        record.room.inviteCode = "MR36TW"
        record.room.ownerId = haruka.id
        record.room.memberIds = people.map(\.id)
        record.room.memberCount = people.count
        record.room.readyCount = 1
        record.room.createdAt = createdAt
        record.members = [:]
        for (offset, person) in people.enumerated() {
            let joinedAt = createdAt.addingTimeInterval(Double(offset) * 60)
            record.members[person.id] = Member(
                displayName: person.name,
                avatarColor: AvatarPalette.colors[person.colorIndex],
                role: offset == 0 ? .owner : .member,
                ready: offset == 0,
                joinedAt: joinedAt,
                lastSeenAt: joinedAt
            )
        }
        return record
    }

    /// 自分が作った `open` のルーム（全員OKで解禁・投稿数 3・共感ブースト）
    private static func demoRoom(now: Date) -> RoomRecord {
        let createdAt = now.addingTimeInterval(-7_200)
        var record = RoomRecord(room: Room(
            name: "年末の旅行",
            ownerId: DemoScenario.myUserID,
            inviteCode: DemoScenario.inviteCode,
            status: .open,
            settings: RoomSettings(postLimit: DomainConstants.Limits.defaultPostLimit, unlockRule: .all, deadlineAt: nil, likeMode: .boost),
            forcedUnlock: false,
            memberIds: demoPeople.map(\.id),
            memberCount: demoPeople.count,
            readyCount: 0,
            candidateCount: 0,
            adFreeSponsor: nil,
            currentDrawId: nil,
            winnerCandidateId: nil,
            excludedCandidateIds: [],
            reroll: .initial,
            createdAt: createdAt,
            drawnAt: nil,
            closedAt: nil
        ))
        for (offset, person) in demoPeople.enumerated() {
            let joinedAt = createdAt.addingTimeInterval(Double(offset) * 60)
            record.members[person.id] = Member(
                displayName: person.name,
                avatarColor: AvatarPalette.colors[person.colorIndex],
                role: offset == 0 ? .owner : .member,
                ready: false,
                joinedAt: joinedAt,
                lastSeenAt: joinedAt
            )
        }
        return record
    }

    /// 候補 3 件（はるかの水族館・そうたの寺社・自分の海）
    private static func demoCandidates(now: Date) -> [String: Candidate] {
        [
            "demo-candidate-1": Candidate(
                place: Place(name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.728_9, longitude: 139.719_7, mapItemId: nil),
                category: .aquarium,
                note: "ペンギンが空を飛ぶ水槽が見たい",
                // 参考 URL のある候補（S-10 の参考 URL の行と、報告した人の画面で隠れること（F-14）を確かめる・撮る）
                url: "https://sunshinecity.jp/aquarium/",
                postedBy: "demo-haruka",
                postedByName: "はるか",
                colorIndex: 0,
                likedBy: [DemoScenario.myUserID, "demo-sota"],
                fromPastIdeaId: nil,
                createdAt: now.addingTimeInterval(-3_600)
            ),
            "demo-candidate-2": Candidate(
                place: Place(name: "明治神宮", area: "東京・渋谷区", latitude: 35.6764, longitude: 139.6993, mapItemId: nil),
                category: .shrine,
                note: "",
                url: nil,
                postedBy: "demo-sota",
                postedByName: "そうた",
                colorIndex: 1,
                likedBy: [],
                fromPastIdeaId: nil,
                createdAt: now.addingTimeInterval(-1_800)
            ),
            "demo-candidate-3": Candidate(
                place: Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.2994, longitude: 139.4800, mapItemId: nil),
                category: .sea,
                note: "しらす丼を食べたい",
                url: nil,
                postedBy: DemoScenario.myUserID,
                postedByName: "たくみ",
                colorIndex: 2,
                likedBy: ["demo-haruka"],
                fromPastIdeaId: nil,
                createdAt: now.addingTimeInterval(-300)
            )
        ]
    }
}
