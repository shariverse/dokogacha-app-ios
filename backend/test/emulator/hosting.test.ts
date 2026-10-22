/**
 * Hosting の Emulator で、Universal Links の apple-app-site-association とランディングページが
 * firebase.json の設定どおりに配信されることを確かめる（タスク 34）。
 */
import { requireEnv } from "./env";

/** Emulator Hub の /emulators が返す、起動中の Emulator の一覧 */
type RunningEmulators = Record<string, { host: string; port: number }>;

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
});
