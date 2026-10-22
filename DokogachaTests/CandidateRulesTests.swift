//
//  CandidateRulesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 候補の重複・採番・入力の判定を確かめる。
///
/// TypeScript 側の `backend/functions/src/domain/candidate.test.ts`・`candidates/input.test.ts` と同じケースを持つ。片方を変えたら両方を変える。
struct CandidateRulesTests {
    /// 江の島（緯度 35.3, 経度 139.48）
    nonisolated static let enoshima = Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: nil)

    /// 候補を投稿・削除できるのは `open`・`unlocked` だけ（02 の §2.1。backend の `CANDIDATE_EDITABLE_STATUSES` と同じ）
    @Test
    func editableStatusesAreOpenAndUnlocked() {
        #expect(CandidateRules.editableStatuses == [.open, .unlocked])
    }

    /// 緯度だけを `deltaLatitude` 度ずらした場所
    static func shifted(_ place: Place, _ deltaLatitude: Double, name: String? = nil, mapItemId: String? = nil) -> Place {
        Place(
            name: name ?? place.name,
            area: place.area,
            latitude: place.latitude + deltaLatitude,
            longitude: place.longitude,
            mapItemId: mapItemId ?? place.mapItemId
        )
    }

    /// 経度だけを `deltaLongitude` 度ずらした場所（距離の式の経度の項を確かめる）
    static func shiftedEast(_ place: Place, _ deltaLongitude: Double) -> Place {
        Place(
            name: place.name,
            area: place.area,
            latitude: place.latitude,
            longitude: place.longitude + deltaLongitude,
            mapItemId: place.mapItemId
        )
    }

    /// 識別子を付けた場所
    static func withID(_ place: Place, _ mapItemId: String?) -> Place {
        Place(name: place.name, area: place.area, latitude: place.latitude, longitude: place.longitude, mapItemId: mapItemId)
    }

    // MARK: 距離（candidate.test.ts の distanceMeters）

    /// 同じ点は 0m、緯度 1 度は約 111,195m（地球の半径 6,371km の球）
    @Test
    func distanceOfOneDegreeLatitude() {
        #expect(CandidateRules.earthRadiusMeters == 6_371_000)
        #expect(CandidateRules.distanceMeters(Self.enoshima, Self.enoshima) == 0)
        let origin = Place(name: "", area: "", latitude: 0, longitude: 0)
        let north = Place(name: "", area: "", latitude: 1, longitude: 0)
        #expect(abs(CandidateRules.distanceMeters(origin, north) - 111_194.93) < 0.05)
    }

    /// どちらから測っても同じ
    @Test
    func distanceIsSymmetric() {
        let tokyo = Place(name: "東京駅", area: "", latitude: 35.681236, longitude: 139.767125)
        #expect(abs(CandidateRules.distanceMeters(Self.enoshima, tokyo) - CandidateRules.distanceMeters(tokyo, Self.enoshima)) < 1e-6)
    }

    /// 緯度 0.000899 度（約 99.96m）と 0.0009 度（約 100.08m）
    @Test
    func distanceAroundHundredMeters() {
        #expect(abs(CandidateRules.distanceMeters(Self.enoshima, Self.shifted(Self.enoshima, 0.000899)) - 99.964) < 0.005)
        #expect(abs(CandidateRules.distanceMeters(Self.enoshima, Self.shifted(Self.enoshima, 0.0009)) - 100.075) < 0.005)
    }

    /// 北緯 35.3 度で経度 0.0011 度（約 99.83m）と 0.00111 度（約 100.73m）
    @Test
    func distanceAlongLongitude() {
        #expect(abs(CandidateRules.distanceMeters(Self.enoshima, Self.shiftedEast(Self.enoshima, 0.0011)) - 99.825) < 0.005)
        #expect(abs(CandidateRules.distanceMeters(Self.enoshima, Self.shiftedEast(Self.enoshima, 0.00111)) - 100.733) < 0.005)
    }

    /// 江の島から東京駅までは約 49.73km（球面の余弦定理で検算した値）
    @Test
    func distanceFromEnoshimaToTokyoStation() {
        let tokyo = Place(name: "東京駅", area: "", latitude: 35.681236, longitude: 139.767125)
        #expect(abs(CandidateRules.distanceMeters(Self.enoshima, tokyo) - 49_727.08) < 0.05)
    }

    // MARK: 100m 以内か（candidate.test.ts の isWithinDuplicateDistance）

    /// 99.999m と 100m は以内・100.001m は超（100m ちょうどは以内）
    @Test(arguments: [(99.999, true), (100, true), (100.001, false)])
    func duplicateDistanceBoundary(meters: Double, expected: Bool) {
        #expect(CandidateRules.isWithinDuplicateDistance(meters) == expected)
    }

    // MARK: 同じ場所か（candidate.test.ts の isSamePlace）

    /// 場所名が同じで 100m 以内なら同じ・100m を超えたら別
    @Test
    func sameNameWithinHundredMeters() {
        #expect(CandidateRules.isSamePlace(Self.enoshima, Self.shifted(Self.enoshima, 0.000899)))
        #expect(!CandidateRules.isSamePlace(Self.enoshima, Self.shifted(Self.enoshima, 0.0009)))
    }

    /// 経度だけずらしても、100m 以内なら同じ・100m を超えたら別（北緯 35.3 度）
    @Test
    func sameNameWithinHundredMetersAlongLongitude() {
        #expect(CandidateRules.isSamePlace(Self.enoshima, Self.shiftedEast(Self.enoshima, 0.0011)))
        #expect(!CandidateRules.isSamePlace(Self.enoshima, Self.shiftedEast(Self.enoshima, 0.00111)))
    }

    /// 場所名が違えば、近くても別（前後の空白は取り除いた後の名前で比べる）
    @Test(arguments: ["江ノ島", "江の島 "])
    func differentNameIsDifferentPlace(name: String) {
        #expect(!CandidateRules.isSamePlace(Self.enoshima, Self.shifted(Self.enoshima, 0, name: name)))
    }

    /// 名前は正準等価ではなく UTF-16 の並びで比べる（TypeScript の `===` と同じ）
    @Test
    func comparesNamesByCodeUnits() {
        let composed = Self.shifted(Self.enoshima, 0, name: "が")
        let decomposed = Self.shifted(Self.enoshima, 0, name: "か\u{3099}")
        #expect(composed.name == decomposed.name)
        #expect(!CandidateRules.isSamePlace(composed, decomposed))
    }

    /// MapKit の識別子が同じなら、名前と距離に関係なく同じ
    @Test
    func sameMapItemIDIsSamePlace() {
        #expect(CandidateRules.isSamePlace(Self.withID(Self.enoshima, "I1"), Self.shifted(Self.enoshima, 1, name: "別の名前", mapItemId: "I1")))
    }

    /// 識別子が違っても、名前が同じで 100m 以内なら同じ（「または」）
    @Test
    func differentMapItemIDButSameNameNearby() {
        #expect(CandidateRules.isSamePlace(Self.withID(Self.enoshima, "I1"), Self.withID(Self.enoshima, "I2")))
    }

    /// 識別子が片方にしか無ければ、名前と距離で判定する
    @Test
    func mapItemIDOnOneSideFallsBackToNameAndDistance() {
        #expect(!CandidateRules.isSamePlace(Self.withID(Self.enoshima, "I1"), Self.shifted(Self.enoshima, 0.0009)))
        #expect(CandidateRules.isSamePlace(Self.withID(Self.enoshima, "I1"), Self.enoshima))
    }

    // MARK: 重複の候補（candidate.test.ts の findDuplicateCandidate）

    static func candidate(_ id: String, _ place: Place, createdAtMs: Int64) -> Identified<Candidate> {
        Identified(id: id, value: Candidate(
            place: place,
            category: .sea,
            note: "",
            url: nil,
            postedBy: "u",
            postedByName: "u",
            colorIndex: 0,
            likedBy: [],
            fromPastIdeaId: nil,
            createdAt: CallableTime.date(fromMilliseconds: createdAtMs)
        ))
    }

    static let existing: [Identified<Candidate>] = [
        candidate("c3", enoshima, createdAtMs: 3_000),
        candidate("c1", shifted(enoshima, 0.32, name: "高尾山"), createdAtMs: 1_000),
        candidate("c2", shifted(enoshima, 0.0001), createdAtMs: 2_000),
        candidate("c0", shifted(enoshima, 0.0002), createdAtMs: 2_000)
    ]

    /// 同じ場所が無ければ nil
    @Test
    func noDuplicate() {
        #expect(CandidateRules.duplicate(of: Self.shifted(Self.enoshima, 0, name: "鎌倉"), in: Self.existing) == nil)
        #expect(CandidateRules.duplicate(of: Self.enoshima, in: []) == nil)
    }

    /// 同じ場所が複数あれば、いちばん古い投稿（同じ日時なら ID の順）
    @Test
    func oldestDuplicateWins() {
        #expect(CandidateRules.duplicate(of: Self.enoshima, in: Self.existing) == "c0")
        #expect(CandidateRules.duplicate(of: Self.enoshima, in: Self.existing.filter { $0.id != "c0" }) == "c2")
    }

    // MARK: 採番（candidate.test.ts の nextColorIndex）

    /// 最大の番号 + 1（候補が無ければ 0）。消した番号は詰めない
    @Test(arguments: [([Int](), 0), ([0, 1, 2], 3), ([0, 2], 3), ([5], 6)])
    func nextColorIndex(existing: [Int], expected: Int) {
        #expect(CandidateRules.nextColorIndex(existing) == expected)
    }

    // MARK: 参考 URL（candidate.test.ts の isAcceptableCandidateUrl・input.test.ts）

    /// http・https で始まり、空白・制御文字を含まない URL を受け付ける
    @Test(arguments: ["https://example.com", "http://a", "HTTPS://Example.com/Path?q=1#x", "https://例え.jp/パス"])
    func acceptsURL(url: String) {
        #expect(CandidateRules.isAcceptableURL(url))
    }

    /// スキームが違う・スキームだけ・途中に空白や制御文字があるものは受け付けない
    @Test(arguments: [
        "", "https://", "example.com", "ftp://example.com", "javascript:alert(1)", "https://a b", "https://a\u{3000}b",
        "https://a\u{0085}b", "https://a\nb", "https://a\u{2028}b", " https://a"
    ])
    func rejectsURL(url: String) {
        #expect(!CandidateRules.isAcceptableURL(url))
    }

    /// `https://` の直後の結合文字でも、先頭はスカラー値で比べる（TypeScript の `startsWith` と同じ）
    @Test
    func schemeIsComparedByScalars() {
        #expect(CandidateRules.isAcceptableURL("https://\u{0301}a"))
    }

    /// 前後の空白を取り除き、2048 文字以下だけを受け付ける。空白だけ・無しは `.none`
    @Test
    func validatesURLInput() {
        #expect(CandidateRules.validatedURL(nil) == .none)
        #expect(CandidateRules.validatedURL("  ") == .none)
        #expect(CandidateRules.validatedURL(" https://example.com/enoshima ") == .valid("https://example.com/enoshima"))
        let longest = "https://example.com/" + String(repeating: "a", count: 2_048 - 20)
        #expect(longest.utf16.count == 2_048)
        #expect(CandidateRules.validatedURL(longest) == .valid(longest))
        #expect(CandidateRules.validatedURL(longest + "a") == .invalid)
        #expect(CandidateRules.validatedURL("https://a" + String(repeating: " ", count: 3_000)) == .invalid)
    }

    // MARK: ひとこと・場所（input.test.ts）

    /// ひとことは 0〜40 文字（空は可・41 文字は不可）。見えない文字だけなら空にする
    @Test
    func validatesNote() {
        #expect(CandidateRules.validatedNote("")?.isEmpty == true)
        #expect(CandidateRules.validatedNote("  海！ ") == "海！")
        #expect(CandidateRules.validatedNote(String(repeating: "あ", count: 40)) == String(repeating: "あ", count: 40))
        #expect(CandidateRules.validatedNote(String(repeating: "あ", count: 41)) == nil)
        #expect(CandidateRules.validatedNote("\u{200B} \u{200B}")?.isEmpty == true)
        #expect(CandidateRules.validatedNote("海\u{200B}") == "海\u{200B}")
    }

    /// ひとことも名前と同じ規則（途中の改行・制御文字・UTF-16 の上限）
    @Test(arguments: ["海\nいきたい", "海\u{0000}", "a" + String(repeating: "\u{0301}", count: 40 * 16)])
    func rejectsNoteLikeName(note: String) {
        #expect(CandidateRules.validatedNote(note) == nil)
    }

    /// 場所名・エリアの前後の空白を取り除く。見えない文字だけのエリアは空にする
    @Test
    func trimsPlace() {
        let place = Place(name: " 江の島 ", area: "　神奈川・藤沢市 ", latitude: 35.3, longitude: 139.48, mapItemId: "I6FD7682FD36BB3BE")
        #expect(CandidateRules.validatedPlace(place)
            == Place(name: "江の島", area: "神奈川・藤沢市", latitude: 35.3, longitude: 139.48, mapItemId: "I6FD7682FD36BB3BE"))
        let invisibleArea = Place(name: "江の島", area: "\u{FE0F}", latitude: 35.3, longitude: 139.48)
        #expect(CandidateRules.validatedPlace(invisibleArea)?.area.isEmpty == true)
        let edges = Place(
            name: String(repeating: "あ", count: 100),
            area: "",
            latitude: -90,
            longitude: 180,
            mapItemId: String(repeating: "a", count: 256)
        )
        #expect(CandidateRules.validatedPlace(edges) == edges)
    }

    nonisolated static let invalidPlaces: [Place] = [
        Place(name: "", area: "", latitude: 35.3, longitude: 139.48),
        Place(name: " ", area: "", latitude: 35.3, longitude: 139.48),
        Place(name: String(repeating: "あ", count: 101), area: "", latitude: 35.3, longitude: 139.48),
        Place(name: "江の島", area: String(repeating: "あ", count: 51), latitude: 35.3, longitude: 139.48),
        Place(name: "江の島", area: "", latitude: 90.0001, longitude: 139.48),
        Place(name: "江の島", area: "", latitude: -90.0001, longitude: 139.48),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: 180.0001),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: -180.0001),
        Place(name: "江の島", area: "", latitude: .nan, longitude: 139.48),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: .infinity),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: 139.48, mapItemId: ""),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: 139.48, mapItemId: String(repeating: "a", count: 257)),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: 139.48, mapItemId: " I1"),
        Place(name: "江の島", area: "", latitude: 35.3, longitude: 139.48, mapItemId: "I\n1")
    ]

    /// 場所名は 1〜100 文字・エリアは 0〜50 文字・緯度経度は範囲の有限の数・識別子は空でない 256 文字以下
    @Test(arguments: invalidPlaces)
    func rejectsInvalidPlace(place: Place) {
        #expect(CandidateRules.validatedPlace(place) == nil)
    }
}
