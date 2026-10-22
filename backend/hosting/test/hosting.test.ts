/**
 * Hosting（招待リンクの Universal Links とランディングページ。タスク 34・05 の §7）の設定とページの処理を確かめる。
 * - apple-app-site-association の形と、アプリの Team ID・Bundle ID（Configs/Project.xcconfig）との一致
 * - firebase.json の hosting（ヘッダー・rewrites・ignore）
 * - ランディングページ（invite.html・assets/landing.js）の招待コードの取り出しと表示、OGP
 * - ページの色が docs/spec/design/tokens.json の値と一致すること
 * Emulator で実際に配信を確かめるのは test/emulator/hosting.test.ts。
 */
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { runInNewContext } from "node:vm";

import { INVITE_LINK_PATH_PREFIX, OGP_TITLE, WEB_DOMAIN } from "../../functions/src/domain/constants";
import { formatInviteCode, parseInviteCode } from "../../functions/src/domain/inviteCode";

/** backend/ の絶対パス */
const BACKEND_DIR = join(__dirname, "..", "..");
/** リポジトリの直下 */
const REPOSITORY_DIR = join(BACKEND_DIR, "..");
/** Hosting で配信するディレクトリ */
const PUBLIC_DIR = join(BACKEND_DIR, "hosting", "public");

/** ファイルを文字列で読む */
function read(path: string): string {
  return readFileSync(path, "utf8");
}

/** Configs/Project.xcconfig の `名前 = 値` を読む */
function xcconfigValue(name: string): string {
  const text = read(join(REPOSITORY_DIR, "Configs", "Project.xcconfig"));
  const line = text.split("\n").find((candidate) => candidate.startsWith(`${name} =`));
  if (line === undefined) {
    throw new Error(`Configs/Project.xcconfig に ${name} がありません`);
  }
  return line.slice(line.indexOf("=") + 1).trim();
}

/** landing.js が globalThis.DokogachaLanding に置く関数 */
interface LandingApi {
  APP_STORE_URL: string;
  inviteCodeFromPath(pathname: string): string | null;
  formatInviteCode(code: string): string;
  render(doc: FakeDocument, pathname: string): string | null;
}

/** render が触る要素だけを持つ、擬似の要素 */
interface FakeElement {
  hidden: boolean;
  textContent: string;
  attributes: Record<string, string>;
  setAttribute(name: string, value: string): void;
}

/** render が触る document の一部だけを持つ、擬似の document */
interface FakeDocument {
  getElementById(id: string): FakeElement | null;
}

/** 擬似の要素を作る */
function fakeElement(hidden = false): FakeElement {
  return {
    hidden,
    textContent: "",
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
  };
}

/**
 * landing.js を、document の無い別の実行環境で読み込んで関数を取り出す（ブラウザと同じく、ファイルをそのまま実行する）。
 */
function loadLanding(): LandingApi {
  const sandbox: { DokogachaLanding?: LandingApi } = {};
  runInNewContext(read(join(PUBLIC_DIR, "assets", "landing.js")), sandbox);
  if (sandbox.DokogachaLanding === undefined) {
    throw new Error("landing.js が DokogachaLanding を置いていません");
  }
  return sandbox.DokogachaLanding;
}

const landing = loadLanding();

describe("apple-app-site-association", () => {
  const aasa = JSON.parse(read(join(PUBLIC_DIR, ".well-known", "apple-app-site-association"))) as {
    applinks: { details: { appIDs: string[]; components: Record<string, string>[] }[] };
  };

  it("Team ID と Bundle ID のアプリに、招待リンクのパス（/r/*）だけを渡す", () => {
    const appID = `${xcconfigValue("DEVELOPMENT_TEAM")}.${xcconfigValue("APP_BUNDLE_IDENTIFIER")}`;
    expect(appID).toBe("XU74X3434S.jp.shilokuma.Dokogacha");
    expect(aasa.applinks.details).toHaveLength(1);
    const [detail] = aasa.applinks.details;
    expect(detail?.appIDs).toEqual([appID]);
    expect(detail?.components.map((component) => component["/"])).toEqual([`${INVITE_LINK_PATH_PREFIX}*`]);
  });

  it("Associated Domains のドメインは、招待リンクのドメインと同じ", () => {
    expect(xcconfigValue("DG_WEB_DOMAIN")).toBe(WEB_DOMAIN);
    expect(read(join(REPOSITORY_DIR, "Configs", "Dokogacha.entitlements"))).toContain(
      "<string>applinks:$(DG_WEB_DOMAIN)</string>",
    );
  });
});

describe("firebase.json の hosting", () => {
  const hosting = (
    JSON.parse(read(join(BACKEND_DIR, "firebase.json"))) as {
      hosting: {
        public: string;
        ignore: string[];
        headers: { source: string; headers: { key: string; value: string }[] }[];
        rewrites: { source: string; destination: string }[];
      };
    }
  ).hosting;

  it("apple-app-site-association を application/json で返す", () => {
    const header = hosting.headers.find((entry) => entry.source === "/.well-known/apple-app-site-association");
    expect(header?.headers).toEqual([{ key: "Content-Type", value: "application/json" }]);
  });

  it("/r/** をランディングページに向ける", () => {
    expect(hosting.rewrites).toEqual([{ source: `${INVITE_LINK_PATH_PREFIX}**`, destination: "/invite.html" }]);
    expect(existsSync(join(BACKEND_DIR, hosting.public, "invite.html"))).toBe(true);
  });

  it("ドットで始まるファイルを除外しない（.well-known を配信する）", () => {
    expect(hosting.ignore).not.toContain("**/.*");
  });
});

describe("ランディングページの招待コード", () => {
  it.each([
    ["/r/QW58RT", "QW58RT"],
    ["/r/qw58rt", "QW58RT"],
    ["/r/QW5-8RT", "QW58RT"],
    ["/r/QW58RT/", "QW58RT"],
    ["/r/%EF%BD%91%EF%BD%975-8RT", "QW58RT"],
  ])("%s から %s を取り出す", (pathname, code) => {
    expect(landing.inviteCodeFromPath(pathname)).toBe(code);
  });

  it.each([
    "/",
    "/r",
    "/r/",
    "/R/QW58RT",
    "/x/r/QW58RT",
    "/r/QW58RT/extra",
    "/r/QW58RT//",
    "/r/QW5%2F8RT",
    "/r/QW58R",
    "/r/QW58RTX",
    "/r/QW58R0",
    "/r/OW58RT",
    "/r/%E0%A4%A",
    "/r/%3Cscript%3E",
    "/r/%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E",
  ])("%s からは取り出さない", (pathname) => {
    expect(landing.inviteCodeFromPath(pathname)).toBeNull();
  });

  // Functions の parseInviteCode（アプリの InviteCode と同じ規則）と同じ結果になる
  it.each([
    "QW58RT",
    "qw5-8rt",
    " qw5 8rt ",
    "ｑｗ５ー８ｒｔ",
    "QW5\u00858RT",
    "QW5\uFEFF8RT",
    "QW5\u30008RT",
    "QW5\u22128RT",
    "QW5_8RT",
    "QW58R",
    "0O1I23",
    "ß2345",
  ])("Functions の parseInviteCode と同じに読む: %j", (input) => {
    expect(landing.inviteCodeFromPath(`${INVITE_LINK_PATH_PREFIX}${encodeURIComponent(input)}`)).toBe(
      parseInviteCode(input),
    );
  });

  it("表示の形は Functions の formatInviteCode と同じ", () => {
    expect(landing.formatInviteCode("QW58RT")).toBe(formatInviteCode("QW58RT"));
  });

  it("正しいコードはカードに表示し、App Store のリンクを入れる", () => {
    const elements: Record<string, FakeElement> = {
      "invite-code-card": fakeElement(true),
      "invite-code": fakeElement(),
      "app-store-link": fakeElement(),
    };
    const doc: FakeDocument = { getElementById: (id) => elements[id] ?? null };
    expect(landing.render(doc, "/r/qw58rt")).toBe("QW58RT");
    expect(elements["invite-code"]?.textContent).toBe("QW5-8RT");
    expect(elements["invite-code-card"]?.hidden).toBe(false);
    expect(elements["app-store-link"]?.attributes.href).toBe(landing.APP_STORE_URL);
  });

  it("正しくないコードはカードを隠し、パスの文字を表示しない", () => {
    const codeText = fakeElement();
    codeText.textContent = "前の値";
    const elements: Record<string, FakeElement> = {
      "invite-code-card": fakeElement(false),
      "invite-code": codeText,
    };
    const doc: FakeDocument = { getElementById: (id) => elements[id] ?? null };
    expect(landing.render(doc, "/r/%3Cscript%3Ealert(1)%3C%2Fscript%3E")).toBeNull();
    expect(elements["invite-code-card"]?.hidden).toBe(true);
    expect(codeText.textContent).toBe("");
  });
});

describe("ランディングページの HTML", () => {
  const html = read(join(PUBLIC_DIR, "invite.html"));

  /** `<meta property|name="…" content="…">` の content を読む */
  function meta(name: string): string | undefined {
    const pattern = new RegExp(`<meta (?:property|name)="${name.replace(/[.:]/g, "\\$&")}" content="([^"]*)">`);
    return pattern.exec(html)?.[1];
  }

  it("固定の OGP（タイトル・画像）を持つ", () => {
    expect(meta("og:title")).toBe(OGP_TITLE);
    expect(html).toContain(`<title>${OGP_TITLE}</title>`);
    expect(meta("og:image")).toBe(`https://${WEB_DOMAIN}/assets/ogp.png`);
    expect(meta("og:url")).toBe(`https://${WEB_DOMAIN}/`);
    expect(meta("twitter:card")).toBe("summary_large_image");
    expect(existsSync(join(PUBLIC_DIR, "assets", "ogp.png"))).toBe(true);
  });

  it("App Store のボタンのリンク先は、landing.js の定数と同じ（JS が動かなくても開ける）", () => {
    expect(html).toContain(`<a id="app-store-link" class="app-store" href="${landing.APP_STORE_URL}">`);
  });

  it("外部の JS・CSS を読まない", () => {
    const sources = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map((match) => match[1] ?? "");
    const assets = sources.filter((source) => /\.(?:js|css)$/.test(source));
    expect(assets).toEqual(["/assets/landing.css", "/assets/landing.js"]);
  });

  it("招待コードは検索エンジンに載せない", () => {
    expect(meta("robots")).toBe("noindex");
  });
});

describe("ページの色", () => {
  const tokens = JSON.parse(read(join(REPOSITORY_DIR, "docs", "spec", "design", "tokens.json"))) as {
    color: Record<string, unknown>;
  };

  /** tokens.json の color を `bg-base`・`capsule-0` の形の鍵の一覧にする */
  function flatten(node: unknown, prefix: string, into: Map<string, string>): Map<string, string> {
    if (typeof node === "string") {
      into.set(prefix, node.toUpperCase());
    } else if (Array.isArray(node)) {
      node.forEach((child, index) => flatten(child, `${prefix}-${String(index)}`, into));
    } else if (typeof node === "object" && node !== null) {
      for (const [key, child] of Object.entries(node)) {
        flatten(child, prefix === "" ? key : `${prefix}-${key}`, into);
      }
    }
    return into;
  }

  const colors = flatten(tokens.color, "", new Map());

  it.each(["hosting/public/assets/landing.css", "hosting/ogp/ogp.html"])("%s の色の変数は tokens.json の値", (file) => {
    const text = read(join(BACKEND_DIR, file));
    const variables = [...text.matchAll(/--color-([A-Za-z0-9-]+):\s*(#[0-9A-Fa-f]{6});/g)];
    expect(variables.length).toBeGreaterThan(0);
    for (const [, name, value] of variables) {
      expect([name, value?.toUpperCase()]).toEqual([name, colors.get(name ?? "")]);
    }
    // 変数の定義のほかに、色の値を直接書かない
    const hexCount = [...text.matchAll(/#[0-9A-Fa-f]{6}\b/g)].length;
    expect(hexCount).toBe(variables.length);
  });
});
