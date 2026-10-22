/**
 * Hosting の Emulator で、Universal Links の apple-app-site-association とランディングページ（タスク 34）、
 * 利用規約・プライバシーポリシー（タスク 35）が、firebase.json の設定（cleanUrls・rewrites・ヘッダー）どおりに配信されることを確かめる。
 */
import { requireEnv } from "./env";

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

/** firebase.json の hosting の `**` で、すべての応答に付けるヘッダー */
const SECURITY_HEADERS: Record<string, string> = {
  "content-security-policy": "default-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
};

/** 応答のヘッダーのうち、SECURITY_HEADERS の名前のものだけを取り出す */
function securityHeaders(response: Response): Record<string, string | null> {
  return Object.fromEntries(Object.keys(SECURITY_HEADERS).map((name) => [name, response.headers.get(name)]));
}

describe("Hosting", () => {
  let origin: string;

  beforeAll(async () => {
    const hub = requireEnv("FIREBASE_EMULATOR_HUB");
    const running = (await (await fetch(`http://${hub}/emulators`)).json()) as RunningEmulators;
    const hosting = running.hosting;
    if (hosting === undefined) {
      throw new Error("Hosting の Emulator が起動していません");
    }
    origin = `http://${hosting.host}:${String(hosting.port)}`;
  });

  it("apple-app-site-association を application/json で返す", async () => {
    const response = await fetch(`${origin}/.well-known/apple-app-site-association`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toMatch(/^application\/json/);
    const body = (await response.json()) as { applinks: { details: { appIDs: string[] }[] } };
    expect(body.applinks.details[0]?.appIDs).toEqual(["XU74X3434S.jp.shilokuma.Dokogacha"]);
  });

  it.each(["/r/QW58RT", "/r/qw5-8rt/", "/r/not-a-code"])("%s はランディングページを返す", async (path) => {
    const response = await fetch(`${origin}${path}`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toMatch(/^text\/html/);
    const html = await response.text();
    expect(html).toContain('<script src="/assets/landing.js" defer></script>');
    expect(html).toContain("ドコガチャに招待されました");
  });

  it.each(["/assets/landing.js", "/assets/landing.css", "/assets/ogp.png"])("%s を配信する", async (path) => {
    const response = await fetch(`${origin}${path}`);
    expect(response.status).toBe(200);
  });

  it.each([
    ["/terms", "<h1 class=\"doc-title\">利用規約</h1>"],
    ["/privacy", "<h1 class=\"doc-title\">プライバシーポリシー</h1>"],
  ])("%s は HTML のページを返す", async (path, heading) => {
    const response = await fetch(`${origin}${path}`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toMatch(/^text\/html/);
    expect(await response.text()).toContain(heading);
  });

  it.each([
    ["/terms.html", "/terms"],
    ["/privacy.html", "/privacy"],
  ])("%s は拡張子なしの %s に転送する", async (path, location) => {
    const response = await fetch(`${origin}${path}`, { redirect: "manual" });
    expect(response.status).toBe(301);
    expect(response.headers.get("location")).toBe(location);
  });

  it.each(["/", "/terms", "/privacy", "/r/QW58RT", "/assets/landing.css", "/assets/landing.js"])(
    "%s に CSP・nosniff・Referrer-Policy を付ける",
    async (path) => {
      const response = await fetch(`${origin}${path}`);
      expect(response.status).toBe(200);
      expect(securityHeaders(response)).toEqual(SECURITY_HEADERS);
    },
  );

  // すべてのパスのヘッダーを足しても、AASA の要件（application/json・転送しない）が崩れないことだけを確かめる。
  // CSP などが付くかは Emulator と本番の Hosting で同じとは限らない（`**` がドットで始まるディレクトリに当たるか）ので確かめない
  it("apple-app-site-association は、すべてのパスのヘッダーを足しても application/json のまま転送しない", async () => {
    const response = await fetch(`${origin}/.well-known/apple-app-site-association`, { redirect: "manual" });
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toMatch(/^application\/json/);
  });
});
