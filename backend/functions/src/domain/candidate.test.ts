import {
  distanceMeters,
  EARTH_RADIUS_METERS,
  findDuplicateCandidate,
  isAcceptableCandidateUrl,
  isSamePlace,
  nextColorIndex,
  type ExistingCandidate,
  type PlaceIdentity,
} from "./candidate";

// Swift 側の DokogachaTests/CandidateRulesTests.swift と同じケース。片方を変えたら両方を変える。

/** 江の島（緯度 35.3, 経度 139.48） */
const enoshima: PlaceIdentity = { name: "江の島", latitude: 35.3, longitude: 139.48, mapItemId: null };

/** 緯度だけを `deltaLatitude` 度ずらした場所 */
function shifted(place: PlaceIdentity, deltaLatitude: number, overrides: Partial<PlaceIdentity> = {}): PlaceIdentity {
  return { ...place, latitude: place.latitude + deltaLatitude, ...overrides };
}

describe("distanceMeters", () => {
  it("同じ点は 0m、緯度 1 度は約 111,195m（地球の半径 6,371km の球）", () => {
    expect(EARTH_RADIUS_METERS).toBe(6_371_000);
    expect(distanceMeters(enoshima, enoshima)).toBe(0);
    expect(distanceMeters({ latitude: 0, longitude: 0 }, { latitude: 1, longitude: 0 })).toBeCloseTo(111_194.93, 1);
  });

  it("どちらから測っても同じ", () => {
    const tokyo = { latitude: 35.681236, longitude: 139.767125 };
    expect(distanceMeters(enoshima, tokyo)).toBeCloseTo(distanceMeters(tokyo, enoshima), 6);
  });

  it("緯度 0.000899 度（約 99.96m）と 0.0009 度（約 100.08m）", () => {
    expect(distanceMeters(enoshima, shifted(enoshima, 0.000899))).toBeCloseTo(99.964, 2);
    expect(distanceMeters(enoshima, shifted(enoshima, 0.0009))).toBeCloseTo(100.075, 2);
  });
});

describe("isSamePlace（02 の F-10 の重複）", () => {
  it("場所名が同じで 100m 以内なら同じ・100m を超えたら別", () => {
    expect(isSamePlace(enoshima, shifted(enoshima, 0.000899))).toBe(true);
    expect(isSamePlace(enoshima, shifted(enoshima, 0.0009))).toBe(false);
  });

  it("場所名が違えば、近くても別（前後の空白は取り除いた後の名前で比べる）", () => {
    expect(isSamePlace(enoshima, { ...enoshima, name: "江ノ島" })).toBe(false);
    expect(isSamePlace(enoshima, { ...enoshima, name: "江の島 " })).toBe(false);
  });

  it("MapKit の識別子が同じなら、名前と距離に関係なく同じ", () => {
    expect(isSamePlace({ ...enoshima, mapItemId: "I1" }, shifted(enoshima, 1, { name: "別の名前", mapItemId: "I1" }))).toBe(
      true,
    );
  });

  it("識別子が違っても、名前が同じで 100m 以内なら同じ（「または」）", () => {
    expect(isSamePlace({ ...enoshima, mapItemId: "I1" }, { ...enoshima, mapItemId: "I2" })).toBe(true);
  });

  it("識別子が片方にしか無ければ、名前と距離で判定する", () => {
    expect(isSamePlace({ ...enoshima, mapItemId: "I1" }, shifted(enoshima, 0.0009))).toBe(false);
    expect(isSamePlace({ ...enoshima, mapItemId: "I1" }, { name: "江の島", latitude: 35.3, longitude: 139.48 })).toBe(true);
  });
});

describe("findDuplicateCandidate", () => {
  const existing: ExistingCandidate[] = [
    { id: "c3", place: enoshima, postedBy: "bob", colorIndex: 2, createdAtMs: 3000 },
    { id: "c1", place: { ...enoshima, name: "高尾山", latitude: 35.62 }, postedBy: "alice", colorIndex: 0, createdAtMs: 1000 },
    { id: "c2", place: shifted(enoshima, 0.0001), postedBy: "alice", colorIndex: 1, createdAtMs: 2000 },
    { id: "c0", place: shifted(enoshima, 0.0002), postedBy: "carol", colorIndex: 3, createdAtMs: 2000 },
  ];

  it("同じ場所が無ければ null", () => {
    expect(findDuplicateCandidate({ ...enoshima, name: "鎌倉" }, existing)).toBeNull();
    expect(findDuplicateCandidate(enoshima, [])).toBeNull();
  });

  it("同じ場所が複数あれば、いちばん古い投稿（同じ日時なら ID の順）", () => {
    expect(findDuplicateCandidate(enoshima, existing)).toBe("c0");
    expect(findDuplicateCandidate(enoshima, existing.filter((candidate) => candidate.id !== "c0"))).toBe("c2");
  });
});

describe("nextColorIndex（05 の §3 の投稿順の通し番号）", () => {
  it("最大の番号 + 1（候補が無ければ 0）。消した番号は詰めない", () => {
    expect(nextColorIndex([])).toBe(0);
    expect(nextColorIndex([0, 1, 2])).toBe(3);
    expect(nextColorIndex([0, 2])).toBe(3);
    expect(nextColorIndex([5])).toBe(6);
  });
});

describe("isAcceptableCandidateUrl", () => {
  it("http・https で始まり、空白・制御文字を含まない URL を受け付ける", () => {
    for (const url of ["https://example.com", "http://a", "HTTPS://Example.com/Path?q=1#x", "https://例え.jp/パス"]) {
      expect(isAcceptableCandidateUrl(url)).toBe(true);
    }
  });

  it("スキームが違う・スキームだけ・途中に空白や制御文字があるものは受け付けない", () => {
    for (const url of [
      "",
      "https://",
      "example.com",
      "ftp://example.com",
      "javascript:alert(1)",
      "https://a b",
      "https://a\u{3000}b",
      "https://a\u{0085}b",
      "https://a\nb",
      "https://a\u{2028}b",
      " https://a",
    ]) {
      expect(isAcceptableCandidateUrl(url)).toBe(false);
    }
  });
});
