import {
  formatInviteCode,
  generateInviteCode,
  INVITE_CODE_ALPHABET,
  INVITE_CODE_IGNORED_SEPARATORS,
  INVITE_CODE_IGNORED_WHITESPACES,
  inviteCodeInputText,
  isValidInviteCode,
  normalizeInviteCode,
  parseInviteCode,
} from "./inviteCode";

// 06 の §2「招待コード: 6文字、使用文字に 0 O 1 I を含まない、表示は ABC-123」。
// Swift 側の DokogachaTests/InviteCodeTests.swift と同じケース。片方を変えたら両方を変える。

describe("文字集合", () => {
  it("英大文字と数字の 32 文字で、0 O 1 I を含まない", () => {
    expect(INVITE_CODE_ALPHABET).toBe("ABCDEFGHJKLMNPQRSTUVWXYZ23456789");
    expect(INVITE_CODE_ALPHABET).toHaveLength(32);
    expect(new Set(INVITE_CODE_ALPHABET).size).toBe(32);
    for (const confusing of ["0", "O", "1", "I"]) {
      expect(INVITE_CODE_ALPHABET).not.toContain(confusing);
    }
  });
});

describe("generateInviteCode", () => {
  it("注入した乱数のとおりに、文字集合から 6 文字を選ぶ", () => {
    expect(generateInviteCode(() => 0)).toBe("AAAAAA");
    expect(generateInviteCode((max) => max - 1)).toBe("999999");
    let next = 0;
    expect(generateInviteCode(() => next++)).toBe("ABCDEF");
  });

  it("乱数で作ったコードは、どれも 6 文字で、0 O 1 I を含まない", () => {
    for (let i = 0; i < 1000; i += 1) {
      const code = generateInviteCode();
      expect(code).toHaveLength(6);
      expect(code).not.toMatch(/[0O1I]/u);
      expect(parseInviteCode(code)).toBe(code);
    }
  });

  it("乱数で作ると、文字集合のすべての文字が出る", () => {
    const used = new Set<string>();
    for (let i = 0; i < 1000; i += 1) {
      for (const character of generateInviteCode()) {
        used.add(character);
      }
    }
    expect(used).toEqual(new Set(INVITE_CODE_ALPHABET));
  });

  it.each([-1, 32, 1.5, Number.NaN])("乱数が範囲の外（%p）なら失敗する", (value) => {
    expect(() => generateInviteCode(() => value)).toThrow(RangeError);
  });
});

describe("表示", () => {
  it("3 文字ずつハイフンで区切る（02 の §2.4 の例 ABC-123・03 の S-04 の例 DK7-29Q）", () => {
    expect(formatInviteCode("ABC123")).toBe("ABC-123");
    expect(formatInviteCode("DK729Q")).toBe("DK7-29Q");
  });
});

describe("入力の正規化と検証", () => {
  it.each([
    ["DK729Q", "DK729Q"],
    ["dk729q", "DK729Q"],
    ["DK7-29Q", "DK729Q"],
    [" dk7 29q ", "DK729Q"],
    ["ＤＫ７－２９Ｑ", "DK729Q"],
    ["dk7ー29q", "DK729Q"],
    ["DK7　29Q", "DK729Q"],
    ["DK7\u{0085}29Q", "DK729Q"],
    ["\u{FEFF}DK729Q", "DK729Q"],
    ["DK7\r\n29Q", "DK729Q"],
  ])("%j は正規化すると %j として読める", (input, expected) => {
    expect(normalizeInviteCode(input)).toBe(expected);
    expect(parseInviteCode(input)).toBe(expected);
  });

  it.each(["", "DK729", "DK729QA", "DK729O", "DK7290", "DK7291", "DK729I", "DK7_29Q", "ABC123"])(
    "%j は招待コードとして読めない",
    (input) => {
      expect(parseInviteCode(input)).toBeNull();
      expect(isValidInviteCode(normalizeInviteCode(input))).toBe(false);
    },
  );

  it("取り除く文字の一覧は Swift 側と同じ（空白 26 文字・区切り 9 文字）", () => {
    expect(INVITE_CODE_IGNORED_WHITESPACES.map((point) => point.toString(16))).toEqual([
      "9", "a", "b", "c", "d", "20", "85", "a0", "1680", "2000", "2001", "2002", "2003", "2004",
      "2005", "2006", "2007", "2008", "2009", "200a", "2028", "2029", "202f", "205f", "3000", "feff",
    ]);
    expect(INVITE_CODE_IGNORED_SEPARATORS.map((point) => point.toString(16))).toEqual([
      "2d", "2010", "2011", "2012", "2013", "2014", "2015", "2212", "30fc",
    ]);
  });

  it("一覧のどの文字も、コードの間に入れると取り除かれる", () => {
    for (const point of [...INVITE_CODE_IGNORED_WHITESPACES, ...INVITE_CODE_IGNORED_SEPARATORS]) {
      expect(parseInviteCode(`DK7${String.fromCodePoint(point)}29Q`)).toBe("DK729Q");
    }
  });

  it("入力欄は、大文字にしてハイフンを自動で入れ、6 文字までに切る（S-05）", () => {
    expect(inviteCodeInputText("")).toBe("");
    expect(inviteCodeInputText("dk7")).toBe("DK7");
    expect(inviteCodeInputText("dk72")).toBe("DK7-2");
    expect(inviteCodeInputText("DK7-")).toBe("DK7");
    expect(inviteCodeInputText("dk7-29q")).toBe("DK7-29Q");
    expect(inviteCodeInputText("dk729q88")).toBe("DK7-29Q");
  });
});
