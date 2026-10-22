import { Timestamp } from "firebase-admin/firestore";

import type { CandidateDoc } from "../domain/models";
import { canReport, decideReport, REPORT_REASON_LABELS, reportDocumentId, reportMailOf, snapshotOf } from "./logic";

/** 理由つきの HttpsError を投げることを確かめる */
function expectReason(run: () => unknown, reason: string): void {
  expect(run).toThrow(expect.objectContaining({ details: { reason } }) as Error);
}

/** はるか（haruka）が投稿した、ひとこと・参考 URL のある候補 */
const candidate: CandidateDoc = {
  place: { name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.7289, longitude: 139.7197 },
  category: "aquarium",
  note: "ペンギンが空を飛ぶ水槽が見たい",
  url: "https://example.com/aquarium",
  postedBy: "haruka",
  postedByName: "はるか",
  colorIndex: 0,
  likedBy: ["takumi"],
  createdAt: Timestamp.fromMillis(0),
};

describe("canReport（02 の §3.5。Swift の CandidatePermission.canReport と同じケース）", () => {
  it.each([
    ["他人の投稿は報告できる", "haruka", "takumi", true],
    ["自分の投稿は報告できない", "takumi", "takumi", false],
    ["退出した人の投稿も報告できる", "departed", "takumi", true],
  ])("%s", (_, postedBy, uid, expected) => {
    expect(canReport(postedBy, uid)).toBe(expected);
  });
});

describe("decideReport", () => {
  it("他人の投稿で、まだ報告していなければ作る", () => {
    expect(decideReport(candidate, "takumi", false)).toEqual({ kind: "create" });
  });

  it("もう報告していれば作らない（1 人 1 候補につき 1 回）", () => {
    expect(decideReport(candidate, "takumi", true)).toEqual({ kind: "already-reported" });
  });

  it("自分の投稿は、報告済みかによらず cannot-report-own-candidate", () => {
    expectReason(() => decideReport(candidate, "haruka", false), "cannot-report-own-candidate");
    expectReason(() => decideReport(candidate, "haruka", true), "cannot-report-own-candidate");
  });
});

describe("reportDocumentId", () => {
  it("ルーム・候補・報告した人が同じなら同じ ID（SHA-256 の 16 進数 64 文字）", () => {
    const id = reportDocumentId("room1", "c1", "takumi");
    expect(id).toMatch(/^[0-9a-f]{64}$/);
    expect(reportDocumentId("room1", "c1", "takumi")).toBe(id);
  });

  it("どれかが違えば違う ID。区切りの文字を含む ID どうしでも重ならない", () => {
    const ids = [
      reportDocumentId("room1", "c1", "takumi"),
      reportDocumentId("room1", "c1", "souta"),
      reportDocumentId("room1", "c2", "takumi"),
      reportDocumentId("room2", "c1", "takumi"),
      reportDocumentId("a_b", "c", "u"),
      reportDocumentId("a", "b_c", "u"),
    ];
    expect(new Set(ids).size).toBe(ids.length);
  });
});

describe("snapshotOf", () => {
  it("場所・カテゴリ・ひとこと・参考 URL・投稿した人の uid だけを残す（表示名・いいねは持たない）", () => {
    expect(snapshotOf(candidate)).toEqual({
      placeName: "サンシャイン水族館",
      area: "東京・豊島区",
      category: "aquarium",
      note: "ペンギンが空を飛ぶ水槽が見たい",
      url: "https://example.com/aquarium",
      postedBy: "haruka",
    });
  });

  it("参考 URL が無ければ null", () => {
    const withoutURL: CandidateDoc = { ...candidate };
    delete withoutURL.url;
    expect(snapshotOf(withoutURL).url).toBeNull();
    expect(snapshotOf({ ...candidate, url: null }).url).toBeNull();
  });
});

describe("reportMailOf", () => {
  const content = {
    reportId: "r".repeat(64),
    roomId: "room1",
    roomName: "年末の旅行",
    candidateId: "c1",
    reason: "inappropriate" as const,
    candidate: snapshotOf(candidate),
    reportedAtMs: Date.UTC(2026, 9, 22, 11, 0, 0),
  };

  it("理由の表示名は 02 の §3.5 の 3 つ", () => {
    expect(REPORT_REASON_LABELS).toEqual({ inappropriate: "不適切な内容", spam: "スパム", other: "その他" });
  });

  it("宛先・件名（理由だけ）・本文（候補の内容・ルーム・理由・ID）を書く", () => {
    const mail = reportMailOf("  ops-inbox  ", content);
    expect(mail?.to).toBe("ops-inbox");
    expect(mail?.message.subject).toBe("【ドコガチャ】投稿の報告（不適切な内容）");
    const text = mail?.message.text ?? "";
    for (const line of [
      "理由: 不適切な内容",
      "報告の日時: 2026-10-22T11:00:00.000Z",
      `報告の ID: ${content.reportId}`,
      "ルーム: 年末の旅行",
      "ルームの ID: room1",
      "候補の ID: c1",
      "場所: サンシャイン水族館（東京・豊島区）",
      "カテゴリ: aquarium",
      "ひとこと: ペンギンが空を飛ぶ水槽が見たい",
      "参考URL: https://example.com/aquarium",
      "投稿した人のユーザー ID: haruka",
    ]) {
      expect(text.split("\n")).toContain(line);
    }
  });

  it("個人情報は最小限: 表示名（投稿した人・報告した人）と報告した人の uid は書かない", () => {
    const text = JSON.stringify(reportMailOf("ops-inbox", content));
    expect(text).not.toContain("はるか");
    expect(text).not.toContain("takumi");
  });

  it("ひとこと・参考 URL・エリアが無ければ「（なし）」・括弧を付けない", () => {
    const empty = { ...content, candidate: { ...content.candidate, note: "", url: null, area: "" } };
    const lines = (reportMailOf("ops-inbox", empty)?.message.text ?? "").split("\n");
    expect(lines).toEqual(expect.arrayContaining(["ひとこと: （なし）", "参考URL: （なし）", "場所: サンシャイン水族館"]));
  });

  it("宛先が空（パラメータの入れ忘れ）なら null（メールを書かない）", () => {
    expect(reportMailOf("", content)).toBeNull();
    expect(reportMailOf("   ", content)).toBeNull();
  });
});
