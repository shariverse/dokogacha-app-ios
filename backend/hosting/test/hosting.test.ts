/**
 * Hosting（招待リンクの Universal Links とランディングページ。タスク 34・05 の §7。利用規約とプライバシーポリシー。タスク 35）の設定とページの処理を確かめる。
 * - apple-app-site-association の形と、アプリの Team ID・Bundle ID（Configs/Project.xcconfig）との一致
 * - firebase.json の hosting（ヘッダー・rewrites・cleanUrls・ignore）
 * - ランディングページ（invite.html・assets/landing.js）の招待コードの取り出しと表示、OGP
 * - 利用規約（terms.html）・プライバシーポリシー（privacy.html）の問い合わせ先・人間が埋める目印・載せる項目
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
        cleanUrls: boolean;
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

  it("拡張子なしの URL（/terms・/privacy）で HTML を開く", () => {
    expect(hosting.cleanUrls).toBe(true);
    for (const page of ["terms.html", "privacy.html"]) {
      expect(existsSync(join(BACKEND_DIR, hosting.public, page))).toBe(true);
    }
  });

  it("すべてのパスに CSP・nosniff・Referrer-Policy を付ける", () => {
    const header = hosting.headers.find((entry) => entry.source === "**");
    expect(header?.headers).toEqual([
      {
        key: "Content-Security-Policy",
        value: "default-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      },
      { key: "X-Content-Type-Options", value: "nosniff" },
      { key: "Referrer-Policy", value: "no-referrer" },
    ]);
  });

  it("どのページも、CSP（default-src 'self'）で止まるインラインのスクリプト・スタイルを使わない", () => {
    for (const page of ["index.html", "invite.html", "terms.html", "privacy.html"]) {
      const html = read(join(BACKEND_DIR, hosting.public, page));
      // 自分のオリジンのファイルを読む <script src> だけを許す（中身のある <script> は CSP で動かない）
      expect([page, html.match(/<script(?![^>]*\ssrc=)[^>]*>/g)]).toEqual([page, null]);
      expect([page, html.match(/<style[\s>]/g)]).toEqual([page, null]);
      expect([page, html.match(/\sstyle="/g)]).toEqual([page, null]);
      expect([page, html.match(/\son[a-z]+="/g)]).toEqual([page, null]);
    }
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

describe("利用規約・プライバシーポリシーの HTML", () => {
  /** 問い合わせ先（ゴールの Q8 の回答のフォーム。公開してよい問い合わせ先） */
  const CONTACT_FORM_URL =
    "https://docs.google.com/forms/d/e/1FAIpQLSc4DiUAcjKlrchuefXxehD-BgCEhGVomX6NOwtijWiE0yJAlQ/viewform";

  const pages = {
    terms: read(join(PUBLIC_DIR, "terms.html")),
    privacy: read(join(PUBLIC_DIR, "privacy.html")),
  };
  const pageEntries = Object.entries(pages);

  /** HTML のコメントを除いた、ページに出る部分 */
  function visible(html: string): string {
    return html.replace(/<!--[\s\S]*?-->/g, "");
  }

  /** `href="…"` の一覧 */
  function hrefs(html: string): string[] {
    return [...html.matchAll(/href="([^"]+)"/g)].map((match) => match[1] ?? "");
  }

  it.each(pageEntries)("%s は問い合わせ先のフォームへのリンクを持つ", (_, html) => {
    expect(hrefs(visible(html))).toContain(CONTACT_FORM_URL);
  });

  it.each(pageEntries)("%s は運営者名と施行日を、人間が埋める目印にしている", (_, html) => {
    expect(visible(html)).toContain("【運営者名】");
    expect(visible(html)).toContain("【施行日】");
  });

  it.each(pageEntries)("%s は下書きであることを、ページには出さず HTML のコメントにだけ書く", (_, html) => {
    const comments = [...html.matchAll(/<!--([\s\S]*?)-->/g)].map((match) => match[1] ?? "").join("\n");
    expect(comments).toContain("下書き");
    expect(comments).toContain("人間が確認して直す");
    expect(visible(html)).not.toContain("下書き");
  });

  it.each(pageEntries)("%s はメールアドレス・電話番号を書かない", (_, html) => {
    expect(html).not.toMatch(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/);
    expect(html).not.toMatch(/\b0\d{1,4}-\d{1,4}-\d{3,4}\b/);
    expect(html).not.toContain("mailto:");
    expect(html).not.toContain("tel:");
  });

  it.each(pageEntries)("%s はランディングと同じ CSS だけを読み、スクリプトを読まない", (_, html) => {
    const assets = [...html.matchAll(/(?:src|href)="([^"]+)"/g)]
      .map((match) => match[1] ?? "")
      .filter((source) => !source.startsWith("https://") && !source.startsWith("/terms") && !source.startsWith("/privacy"));
    expect(assets).toEqual(["/assets/landing.css"]);
    expect(html).not.toContain("<script");
  });

  it.each(pageEntries)("%s の外部へのリンクは、すべて https で rel に noopener noreferrer を付ける", (_, html) => {
    const anchors = [...html.matchAll(/<a\s[^>]*href="(https?:[^"]+)"[^>]*>/g)];
    expect(anchors.length).toBeGreaterThan(0);
    for (const [anchor, url] of anchors) {
      expect([url, url?.startsWith("https://")]).toEqual([url, true]);
      expect([url, anchor.includes('rel="noopener noreferrer"')]).toEqual([url, true]);
    }
  });

  it("利用規約とプライバシーポリシーは互いにリンクする", () => {
    expect(hrefs(pages.terms)).toContain("/privacy");
    expect(hrefs(pages.privacy)).toContain("/terms");
  });

  it("利用規約は、不適切な投稿の禁止と、報告を受けた運営の確認・削除を書く（06 の §5・F-14）", () => {
    const text = visible(pages.terms);
    expect(text).toContain("不適切な投稿の禁止");
    expect(text).toContain("この投稿を報告");
    expect(text).toMatch(/報告を受けた投稿の内容を確認し[^。]*削除することがあります/);
  });

  it.each([
    ["アカウントの削除（F-06）", "アカウントを削除"],
    ["有料の機能（F-51）", "広告を非表示にする"],
    ["購入の復元（F-51）", "購入を復元"],
    ["返金の窓口（Apple）", "Apple に申請"],
    ["免責", "第11条（免責）"],
    ["規約の変更", "本規約の変更"],
    ["準拠法", "日本の法律"],
  ])("利用規約は %s を書く", (_, phrase) => {
    expect(visible(pages.terms)).toContain(phrase);
  });

  it.each([
    "ユーザー ID",
    "表示名",
    "投稿内容",
    "ひとこと",
    "参考 URL",
    "通知トークン",
    "広告データ",
    "IDFA",
    "App Tracking Transparency",
    "診断データ",
    "利用状況",
    "Crashlytics",
    "Google Analytics for Firebase",
  ])("プライバシーポリシーは収集するデータ「%s」を書く", (phrase) => {
    expect(visible(pages.privacy)).toContain(phrase);
  });

  it("プライバシーポリシーは、アカウントの削除で消えるものと、ルームに残る記録（ユーザー ID・表示名）を分けて書く（02 の F-05・F-06）", () => {
    const section = visible(pages.privacy).match(/<section[^>]*aria-labelledby="privacy-6"[\s\S]*?<\/section>/)?.[0] ?? "";
    // 消えるもの: users/{uid}（表示名・通知トークン・購入の情報）・pastIdeas・Auth のユーザー
    expect(section).toMatch(/アカウントと、アカウントに結び付く情報（表示名・通知トークン・購入の情報・過去のアイデア）を削除します/);
    // 外れるもの: members・memberIds・adFreeSponsor・候補の likedBy（deleteAccount が退出と同じ処理で外す）
    expect(section).toMatch(/ルームのメンバーの一覧と、「広告を非表示にする」を購入した利用者の表示からも外れ、付けたいいねは取り消されます/);
    // 残るもの: 候補の postedBy・postedByName（プロフィールの同期で書き換わるので、ルームから外れたときの名前）
    expect(section).toMatch(/投稿した候補には、ユーザー ID と、ルームから退出したとき（アカウントを削除したときを含みます）の表示名が残ります/);
    // 残るもの: draws の drawnBy・drawnByName（回したときの名前のまま。onUserProfileUpdate は書き換えない）
    expect(section).toMatch(/ガチャを回した記録には、ユーザー ID と、ガチャを回したときの表示名が残ります/);
    // 残るもの: ルームの ownerId・reroll.proposedBy・notificationLog の invited-{uid}-…（表示名は持たない）
    expect(section).toMatch(/作成したルームの作成者、引き直しの提案、前回のメンバーへの招待を送った記録には、ユーザー ID だけが残ります/);
    expect(section).toContain("「退出したメンバー」の投稿");
    // 「そのときの表示名」のように、いつの名前かを書き分けない書き方に戻さない
    expect(section).not.toContain("そのときの表示名");
    // 削除するものの括弧の中に、ルームに残るユーザー ID を入れない
    expect(section).not.toMatch(/（[^）]*ユーザー ID[^）]*）を削除します/);
  });

  it("プライバシーポリシーは、第三者の提供先に AdMob と Firebase（Google）を挙げ、各社のポリシーにリンクする", () => {
    const text = visible(pages.privacy);
    expect(text).toContain("<h3>Firebase（Google LLC）</h3>");
    expect(text).toContain("<h3>AdMob（Google LLC）</h3>");
    expect(hrefs(text)).toEqual(
      expect.arrayContaining([
        "https://firebase.google.com/support/privacy",
        "https://policies.google.com/privacy",
        "https://policies.google.com/technologies/ads",
      ]),
    );
  });

  it("プライバシーポリシーは、外部のサービスの節に、報告のメールを運営者に送ること（F-14）と、報告した利用者を含めないことを書く", () => {
    const section = visible(pages.privacy).match(/<section[^>]*aria-labelledby="privacy-4"[\s\S]*?<\/section>/)?.[0] ?? "";
    expect(section).toContain("<h3>投稿の報告のメール</h3>");
    expect(section).toMatch(/投稿が報告されたときは、報告の内容（[^）]*ひとこと[^）]*参考 URL[^）]*理由[^）]*）をメールで運営者に送ります/);
    expect(section).toContain("報告した利用者のユーザー ID と表示名は、メールに含めません");
    expect(section).toContain("メールの送信サービス");
  });

  it.each([
    ["保存期間・削除（F-06）", "アカウントを削除"],
    ["未成年", "未成年の方"],
    ["改定", "このポリシーの変更"],
    ["位置情報を取らない（02 の §9）", "位置情報を取得しません"],
  ])("プライバシーポリシーは %s を書く", (_, phrase) => {
    expect(visible(pages.privacy)).toContain(phrase);
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

  it("landing.css で使う色の変数は、すべて :root で tokens.json の値に定義している", () => {
    const text = read(join(PUBLIC_DIR, "assets", "landing.css"));
    const defined = new Set([...text.matchAll(/--color-([A-Za-z0-9-]+):/g)].map((match) => match[1]));
    const used = [...text.matchAll(/var\(--color-([A-Za-z0-9-]+)\)/g)].map((match) => match[1]);
    expect(used.length).toBeGreaterThan(0);
    expect(used.filter((name) => !defined.has(name))).toEqual([]);
  });

  it.each(["terms.html", "privacy.html"])("%s は色の値を直接書かない（landing.css の変数を使う）", (page) => {
    expect(read(join(PUBLIC_DIR, page))).not.toMatch(/#[0-9A-Fa-f]{3,8}\b|rgba?\(/);
  });
});
