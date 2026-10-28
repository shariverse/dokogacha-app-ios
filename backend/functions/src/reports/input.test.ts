import { parseReportCandidateInput } from "./input";

/** 関数が invalid-argument の HttpsError を投げることを確かめる */
function expectInvalid(run: () => unknown): void {
  expect(run).toThrow(expect.objectContaining({ code: "invalid-argument" }) as Error);
}

/** 正しい入力（アプリの `ReportCandidateRequest` を JSON にしたもの） */
const valid = { roomId: "room1", candidateId: "c1", reason: "spam" };

describe("parseReportCandidateInput（02 の §3.5）", () => {
  it.each(["inappropriate", "spam", "other"])("理由 %s を受け付ける", (reason) => {
    expect(parseReportCandidateInput({ ...valid, reason })).toEqual({ roomId: "room1", candidateId: "c1", reason });
  });

  it.each([undefined, null, "", "Spam", "abuse", 1, ["spam"]])("知らない理由（%p）は invalid-argument", (reason) => {
    expectInvalid(() => parseReportCandidateInput({ ...valid, reason }));
  });

  it.each([
    ["ルームの ID が無い", { ...valid, roomId: undefined }],
    ["ルームの ID がパスの区切りを含む", { ...valid, roomId: "room1/candidates" }],
    ["候補の ID が空", { ...valid, candidateId: "" }],
    ["候補の ID が文字列でない", { ...valid, candidateId: 1 }],
  ])("%s なら invalid-argument", (_, data) => {
    expectInvalid(() => parseReportCandidateInput(data));
  });

  it.each([null, "room1", ["room1"]])("入力がオブジェクトでなければ invalid-argument（%p）", (data) => {
    expectInvalid(() => parseReportCandidateInput(data));
  });
});
