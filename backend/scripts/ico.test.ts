import { pngSize, pngsToIco } from "./ico.cjs";

/** IHDR までだけを持つ、幅と高さを指定した PNG の先頭（ICO はヘッダーしか読まないので、画素の無いもので確かめる） */
function fakePng(width: number, height: number, extra = 0): Buffer {
  const png = Buffer.alloc(33 + extra);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png, 0);
  png.writeUInt32BE(13, 8);
  png.write("IHDR", 12, "ascii");
  png.writeUInt32BE(width, 16);
  png.writeUInt32BE(height, 20);
  return png;
}

describe("pngSize", () => {
  it("IHDR の幅と高さを読む", () => {
    expect(pngSize(fakePng(32, 16))).toEqual({ width: 32, height: 16 });
  });

  it("PNG でないものは投げる", () => {
    expect(() => pngSize(Buffer.from("GIF89a but not a png at all"))).toThrow("PNG ではありません");
  });
});

describe("pngsToIco", () => {
  it("ヘッダー・ディレクトリ・PNG の本体を順に並べる", () => {
    const small = fakePng(16, 16);
    const large = fakePng(32, 32, 7);
    const ico = pngsToIco([small, large]);

    // ヘッダー: 予約 0・種類 1（アイコン）・枚数
    expect([ico.readUInt16LE(0), ico.readUInt16LE(2), ico.readUInt16LE(4)]).toEqual([0, 1, 2]);
    // ディレクトリ: 幅・高さ・プレーン・ビット数・大きさ・本体の位置
    const entry = (index: number) => {
      const at = 6 + 16 * index;
      return {
        width: ico.readUInt8(at),
        height: ico.readUInt8(at + 1),
        planes: ico.readUInt16LE(at + 4),
        bits: ico.readUInt16LE(at + 6),
        size: ico.readUInt32LE(at + 8),
        offset: ico.readUInt32LE(at + 12),
      };
    };
    expect(entry(0)).toEqual({ width: 16, height: 16, planes: 1, bits: 32, size: small.length, offset: 38 });
    expect(entry(1)).toEqual({ width: 32, height: 32, planes: 1, bits: 32, size: large.length, offset: 38 + small.length });
    expect(ico.subarray(38, 38 + small.length).equals(small)).toBe(true);
    expect(ico.subarray(38 + small.length).equals(large)).toBe(true);
  });

  it("256px はディレクトリに 0 と書く", () => {
    const ico = pngsToIco([fakePng(256, 256)]);
    expect([ico.readUInt8(6), ico.readUInt8(7)]).toEqual([0, 0]);
  });

  it("257px 以上と、空の一覧は投げる", () => {
    expect(() => pngsToIco([fakePng(512, 512)])).toThrow("256px まで");
    expect(() => pngsToIco([])).toThrow("PNG が 1 枚もありません");
  });
});
