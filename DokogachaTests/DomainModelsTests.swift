//
//  DomainModelsTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// `Domain/Models` のモデルが、05 の §3 の Firestore のフィールド名・値のとおりに `Codable` になることを確かめる。
///
/// フィールド名を書き間違えると、データ層で Firestore を読んだときに黙って値が欠ける（または読めない）。
/// JSON に書き出した鍵を 05 の表の名前と突き合わせて、モデルの形を固定する。
struct DomainModelsTests {
    /// テストで使う日時（2026-10-22 12:00 UTC）
    nonisolated static let date = Date(timeIntervalSince1970: 1_792_670_400)

    /// 05 の §3 の `place` の例
    nonisolated static let place = Place(
        name: "すみだ水族館", area: "東京・墨田区", latitude: 35.7101, longitude: 139.8107, mapItemId: "I1234"
    )

    /// モデルを JSON の辞書にする（鍵と値を確かめるため）
    static func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 書き出して読み戻すと同じ値になる
    static func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    /// 05 の §3 の `rooms/{roomId}` の例（任意の値をすべて埋める）
    static func sampleRoom() -> Room {
        Room(
            name: "年末の旅行",
            ownerId: "owner",
            inviteCode: "DK729Q",
            status: .drawn,
            settings: RoomSettings(postLimit: 3, unlockRule: .deadline, deadlineAt: date, likeMode: .boost),
            forcedUnlock: false,
            memberIds: ["owner", "friend"],
            memberCount: 2,
            readyCount: 2,
            candidateCount: 3,
            adFreeSponsor: AdFreeSponsor(uid: "friend", displayName: "ハナ"),
            currentDrawId: "draw1",
            winnerCandidateId: "cand1",
            excludedCandidateIds: [],
            reroll: RerollState(
                used: true, proposedBy: "friend", proposedAt: date, votesFor: ["friend"], votesAgainst: [], status: .voting
            ),
            createdAt: date,
            drawnAt: date,
            closedAt: nil
        )
    }

    /// `rooms/{roomId}` の鍵が 05 の §3 の表のとおり（値が nil のフィールドは書き出さない）
    @Test
    func roomFieldNames() throws {
        let room = Self.sampleRoom()
        let json = try Self.jsonObject(room)
        #expect(Set(json.keys) == [
            "name", "ownerId", "inviteCode", "status", "settings", "forcedUnlock", "memberIds", "memberCount",
            "readyCount", "candidateCount", "adFreeSponsor", "currentDrawId", "winnerCandidateId",
            "excludedCandidateIds", "reroll", "createdAt", "drawnAt"
        ])
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(Set(settings.keys) == ["postLimit", "unlockRule", "deadlineAt", "likeMode"])
        let reroll = try #require(json["reroll"] as? [String: Any])
        #expect(Set(reroll.keys) == ["used", "proposedBy", "proposedAt", "votesFor", "votesAgainst", "status"])
        let sponsor = try #require(json["adFreeSponsor"] as? [String: Any])
        #expect(Set(sponsor.keys) == ["uid", "displayName"])
        #expect(json["status"] as? String == "drawn")
        #expect(settings["unlockRule"] as? String == "deadline")
        #expect(settings["likeMode"] as? String == "boost")
        #expect(reroll["status"] as? String == "voting")
        #expect(try Self.roundTrip(room) == room)
    }

    /// 状態・条件・モードの保存する値が 05 の §3 のとおり
    @Test
    func enumRawValues() {
        #expect(RoomStatus.allCases.map(\.rawValue) == ["open", "unlocked", "drawn", "closed"])
        #expect(UnlockRule.allCases.map(\.rawValue) == ["all", "majority", "deadline"])
        #expect(LikeMode.allCases.map(\.rawValue) == ["boost", "equal"])
        #expect(MemberRole.allCases.map(\.rawValue) == ["owner", "member"])
        #expect(RerollStatus.allCases.map(\.rawValue) == ["none", "voting", "passed", "rejected"])
        #expect(ReportReason.allCases.map(\.rawValue) == ["inappropriate", "spam", "other"])
    }

    /// ルームの作成時の引き直しは「提案されていない」で、`status` は `none` で保存する
    @Test
    func initialReroll() throws {
        let json = try Self.jsonObject(RerollState.initial)
        #expect(json["status"] as? String == "none")
        #expect(json["used"] as? Bool == false)
        #expect(json["proposedBy"] == nil)
    }

    /// `users/{uid}` と `members/{uid}` の鍵が 05 の §3 の表のとおり
    @Test
    func userAndMemberFieldNames() throws {
        let user = UserProfile(displayName: "タクミ", avatarColor: "#B8321A", adFree: false, fcmTokens: ["t"], createdAt: Self.date)
        #expect(try Set(Self.jsonObject(user).keys) == ["displayName", "avatarColor", "adFree", "fcmTokens", "createdAt"])
        #expect(try Self.roundTrip(user) == user)

        let member = Member(
            displayName: "タクミ", avatarColor: "#B8321A", role: .owner, ready: true, joinedAt: Self.date, lastSeenAt: Self.date
        )
        let memberJSON = try Self.jsonObject(member)
        #expect(Set(memberJSON.keys) == ["displayName", "avatarColor", "role", "ready", "joinedAt", "lastSeenAt"])
        #expect(memberJSON["role"] as? String == "owner")
        #expect(try Self.roundTrip(member) == member)
    }

    /// `candidates/{candidateId}` の鍵が 05 の §3 の表のとおりで、カテゴリは文字列で保存する
    @Test
    func candidateFieldNames() throws {
        let candidate = Candidate(
            place: Self.place,
            category: .aquarium,
            note: "ペンギンが近い",
            url: "https://example.com",
            postedBy: "friend",
            postedByName: "ハナ",
            colorIndex: 0,
            likedBy: ["owner"],
            fromPastIdeaId: "idea1",
            createdAt: Self.date
        )
        let json = try Self.jsonObject(candidate)
        #expect(Set(json.keys) == [
            "place", "category", "note", "url", "postedBy", "postedByName", "colorIndex", "likedBy", "fromPastIdeaId",
            "createdAt"
        ])
        #expect(json["category"] as? String == "aquarium")
        let place = try #require(json["place"] as? [String: Any])
        #expect(Set(place.keys) == ["name", "area", "latitude", "longitude", "mapItemId"])
        #expect(try Self.roundTrip(candidate) == candidate)
    }

    /// 任意のフィールドが無いドキュメントも読める（`url`・`fromPastIdeaId`・`place.mapItemId` は nil になる）
    @Test
    func candidateWithoutOptionalFields() throws {
        let json = """
        {
          "place": { "name": "高尾山", "area": "東京・八王子市", "latitude": 35.62, "longitude": 139.24 },
          "category": "nature", "note": "", "postedBy": "owner", "postedByName": "タクミ",
          "colorIndex": 2, "likedBy": [], "createdAt": 0
        }
        """
        let candidate = try JSONDecoder().decode(Candidate.self, from: Data(json.utf8))
        #expect(candidate.url == nil)
        #expect(candidate.fromPastIdeaId == nil)
        #expect(candidate.place.mapItemId == nil)
        #expect(candidate.category == .nature)
    }

    /// `draws`・`pastIdeas`・`inviteCodes`・`reports` の鍵が 05 の §3・§5 のとおり
    @Test
    func otherFieldNames() throws {
        let draw = Draw(
            candidateId: "cand1",
            probability: 0.5,
            weights: ["cand1": 2, "cand2": 2],
            drawnBy: "owner",
            drawnByName: "タクミ",
            isReroll: false,
            createdAt: Self.date
        )
        #expect(try Set(Self.jsonObject(draw).keys) == [
            "candidateId", "probability", "weights", "drawnBy", "drawnByName", "isReroll", "createdAt"
        ])
        #expect(try Self.roundTrip(draw) == draw)

        let idea = PastIdea(
            sourceRoomId: "room1",
            sourceRoomName: "夏の旅行",
            sourceClosedAt: Self.date,
            sourceWinnerName: "江ノ島",
            place: Self.place,
            category: .aquarium,
            prevLikeCount: 3
        )
        #expect(try Set(Self.jsonObject(idea).keys) == [
            "sourceRoomId", "sourceRoomName", "sourceClosedAt", "sourceWinnerName", "place", "category", "prevLikeCount"
        ])
        #expect(try Self.roundTrip(idea) == idea)

        let entry = InviteCodeEntry(roomId: "room1", createdAt: Self.date)
        #expect(try Set(Self.jsonObject(entry).keys) == ["roomId", "createdAt"])

        let report = CandidateReport(
            roomId: "room1", candidateId: "cand1", reporterId: "friend", reason: .spam, createdAt: Self.date
        )
        let reportJSON = try Self.jsonObject(report)
        #expect(Set(reportJSON.keys) == ["roomId", "candidateId", "reporterId", "reason", "createdAt"])
        #expect(reportJSON["reason"] as? String == "spam")
    }

    /// ID で包んでも中身のプロパティをそのまま読め、ID と中身の両方で比べる
    @Test
    func identifiedReadsValue() {
        let room = Identified(id: "room1", value: Self.sampleRoom())
        #expect(room.id == "room1")
        #expect(room.name == "年末の旅行")
        #expect(room.settings.postLimit == 3)
        #expect(room != Identified(id: "room2", value: Self.sampleRoom()))
    }

    /// アバターの色の保存する値は tokens.json の `color.avatar` と同じ順の `#RRGGBB`
    @Test
    func avatarPaletteMatchesTokens() throws {
        let tokens = try #require(DesignTokensTests.value("color.avatar", in: DesignTokensTests.loadTokens()) as? [String])
        #expect(AvatarPalette.colors == tokens.map { $0.uppercased() })
        #expect(AvatarPalette.colors.map { DesignTokensTests.hexString(.dgAvatar(at: AvatarPalette.index(of: $0) ?? -1)) }
            == AvatarPalette.colors)
        #expect(AvatarPalette.index(of: "#b8321a") == 0)
        #expect(AvatarPalette.index(of: "#000000") == nil)
    }

    /// アバターの色は注入した乱数で一覧から選ぶ
    @Test
    func avatarPaletteRandom() {
        #expect(AvatarPalette.random { _ in 0 } == "#B8321A")
        #expect(AvatarPalette.random { $0 - 1 } == "#5E5045")
    }
}
