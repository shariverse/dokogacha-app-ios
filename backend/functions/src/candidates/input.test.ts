import { parseAddCandidateInput, parseDeleteCandidateInput } from "./input";

/** 関数が invalid-argument の HttpsError を投げることを確かめる */
function expectInvalid(run: () => unknown): void {
  expect(run).toThrow(expect.objectContaining({ code: "invalid-argument" }) as Error);
}

/** 正しい入力（アプリの `AddCandidateRequest` を JSON にしたもの。nil の値は鍵ごと無い） */
const valid = {
  roomId: "room1",
  place: { name: "新江ノ島水族館", area: "神奈川・藤沢市", latitude: 35.3087, longitude: 139.4817 },
  category: "aquarium",
  note: "クラゲ見たい",
};

/** 正しい入力の一部を差し替える */
function withPlace(place: Record<string, unknown>): Record<string, unknown> {
  return { ...valid, place: { ...valid.place, ...place } };
}

describe("parseAddCandidateInput", () => {
  it("任意の値が無ければ null にする", () => {
    expect(parseAddCandidateInput(valid)).toEqual({
      roomId: "room1",
      place: { name: "新江ノ島水族館", area: "神奈川・藤沢市", latitude: 35.3087, longitude: 139.4817, mapItemId: null },
      category: "aquarium",
      note: "クラゲ見たい",
      url: null,
      fromPastIdeaId: null,
    });
    expect(parseAddCandidateInput({ ...valid, url: null, fromPastIdeaId: null, place: { ...valid.place, mapItemId: null } }))
      .toMatchObject({ url: null, fromPastIdeaId: null, place: { mapItemId: null } });
  });

  it("名前・エリア・ひとこと・URL の前後の空白を取り除く", () => {
    const input = parseAddCandidateInput({
      ...withPlace({ name: " 江の島 ", area: "　神奈川・藤沢市 ", mapItemId: "I6FD7682FD36BB3BE" }),
      note: "  海！ ",
      url: " https://example.com/enoshima ",
      fromPastIdeaId: "idea1",
    });
    expect(input).toMatchObject({
      place: { name: "江の島", area: "神奈川・藤沢市", mapItemId: "I6FD7682FD36BB3BE" },
      note: "海！",
      url: "https://example.com/enoshima",
      fromPastIdeaId: "idea1",
    });
  });

  it("ひとことは 0〜40 文字（空は可・41 文字は不可）", () => {
    expect(parseAddCandidateInput({ ...valid, note: "" }).note).toBe("");
    expect(parseAddCandidateInput({ ...valid, note: "  " }).note).toBe("");
    expect(parseAddCandidateInput({ ...valid, note: "あ".repeat(40) }).note).toBe("あ".repeat(40));
    expectInvalid(() => parseAddCandidateInput({ ...valid, note: "あ".repeat(41) }));
  });

  it("ひとことも名前と同じ規則（途中の改行・制御文字・UTF-16 の上限）", () => {
    for (const note of ["海\nいきたい", "海\u{0000}", `a${"\u{0301}".repeat(40 * 16)}`, undefined, null, 1]) {
      expectInvalid(() => parseAddCandidateInput({ ...valid, note }));
    }
    // 見えない文字だけのひとこと・エリアは空とみなして、空の文字列にする（0 文字は可なので受け付ける）
    expect(parseAddCandidateInput({ ...valid, note: "\u{200B} \u{200B}" }).note).toBe("");
    expect(parseAddCandidateInput(withPlace({ area: "\u{FE0F}" })).place.area).toBe("");
    expect(parseAddCandidateInput({ ...valid, note: "海\u{200B}" }).note).toBe("海\u{200B}");
  });

  it("場所名は 1〜100 文字・エリアは 0〜50 文字", () => {
    expect(parseAddCandidateInput(withPlace({ name: "あ".repeat(100), area: "" })).place).toMatchObject({
      name: "あ".repeat(100),
      area: "",
    });
    for (const place of [{ name: "" }, { name: " " }, { name: "あ".repeat(101) }, { area: "あ".repeat(51) }, { name: 1 }]) {
      expectInvalid(() => parseAddCandidateInput(withPlace(place)));
    }
  });

  it("緯度は -90〜90・経度は -180〜180 の有限の数", () => {
    expect(parseAddCandidateInput(withPlace({ latitude: -90, longitude: 180 })).place).toMatchObject({
      latitude: -90,
      longitude: 180,
    });
    for (const place of [
      { latitude: 90.0001 },
      { latitude: -90.0001 },
      { longitude: 180.0001 },
      { longitude: -180.0001 },
      { latitude: Number.NaN },
      { longitude: Number.POSITIVE_INFINITY },
      { latitude: "35.3" },
      { longitude: null },
    ]) {
      expectInvalid(() => parseAddCandidateInput(withPlace(place)));
    }
  });

  it("MapKit の識別子は空でない 256 文字以下の文字列（前後の空白・制御文字は不可）", () => {
    expect(parseAddCandidateInput(withPlace({ mapItemId: "a".repeat(256) })).place.mapItemId).toBe("a".repeat(256));
    for (const mapItemId of ["", "a".repeat(257), " I1", "I\n1", 1]) {
      expectInvalid(() => parseAddCandidateInput(withPlace({ mapItemId })));
    }
  });

  it("カテゴリは 9 種のいずれか", () => {
    expect(parseAddCandidateInput({ ...valid, category: "shrine" }).category).toBe("shrine");
    for (const category of ["", "museum", "Aquarium", undefined, 1]) {
      expectInvalid(() => parseAddCandidateInput({ ...valid, category }));
    }
  });

  it("参考 URL は http・https の 2048 文字以下。空白だけなら null", () => {
    expect(parseAddCandidateInput({ ...valid, url: "  " }).url).toBeNull();
    const longest = `https://example.com/${"a".repeat(2048 - 20)}`;
    expect(longest).toHaveLength(2048);
    expect(parseAddCandidateInput({ ...valid, url: longest }).url).toBe(longest);
    for (const url of [`${longest}a`, "example.com", "javascript:alert(1)", "https://a b", 1, `https://a${" ".repeat(3000)}`]) {
      expectInvalid(() => parseAddCandidateInput({ ...valid, url }));
    }
  });

  it("ルームの ID・持ち込み元の ID はドキュメントの ID の形", () => {
    for (const input of [
      { ...valid, roomId: "a/b" },
      { ...valid, roomId: undefined },
      { ...valid, fromPastIdeaId: "" },
      { ...valid, fromPastIdeaId: ".." },
    ]) {
      expectInvalid(() => parseAddCandidateInput(input));
    }
  });

  it("オブジェクトでない入力・場所が無い入力は受け付けない", () => {
    for (const data of [null, "room1", [], { ...valid, place: undefined }, { ...valid, place: [] }]) {
      expectInvalid(() => parseAddCandidateInput(data));
    }
  });
});

describe("parseDeleteCandidateInput", () => {
  it("ルームと候補の ID を受け取る", () => {
    expect(parseDeleteCandidateInput({ roomId: "room1", candidateId: "c1" })).toEqual({ roomId: "room1", candidateId: "c1" });
    for (const data of [{ roomId: "room1" }, { roomId: "room1", candidateId: "a/b" }, { candidateId: "c1" }, null]) {
      expectInvalid(() => parseDeleteCandidateInput(data));
    }
  });
});
