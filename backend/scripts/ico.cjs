#!/usr/bin/env node
// PNG を並べて favicon.ico を作る（ICO の中に PNG をそのまま入れる形。Windows Vista 以降と主なブラウザが読める）。
// この Mac には ImageMagick などが無いので、ICO のヘッダーだけをここで書く。
//   node scripts/ico.cjs <出力.ico> <入力.png>...
"use strict";

const { readFileSync, writeFileSync } = require("node:fs");

/** PNG の先頭 8 バイトの署名 */
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
/** ICO のヘッダー（6 バイト）と、画像 1 枚ごとのディレクトリの項目（16 バイト）の大きさ */
const HEADER_SIZE = 6;
const ENTRY_SIZE = 16;

/**
 * PNG の IHDR から幅と高さを読む。
 * @param {Buffer} png
 * @returns {{ width: number, height: number }}
 */
function pngSize(png) {
  if (png.length < 24 || !png.subarray(0, 8).equals(PNG_SIGNATURE) || png.toString("ascii", 12, 16) !== "IHDR") {
    throw new Error("PNG ではありません");
  }
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

/**
 * PNG を入れた ICO を作る。ICO は 1 辺 256px までで、256 はディレクトリに 0 と書く。
 * @param {Buffer[]} pngs
 * @returns {Buffer}
 */
function pngsToIco(pngs) {
  if (pngs.length === 0) {
    throw new Error("PNG が 1 枚もありません");
  }
  const header = Buffer.alloc(HEADER_SIZE);
  header.writeUInt16LE(0, 0); // 予約
  header.writeUInt16LE(1, 2); // 種類（1 = アイコン）
  header.writeUInt16LE(pngs.length, 4);

  let offset = HEADER_SIZE + ENTRY_SIZE * pngs.length;
  const entries = pngs.map((png) => {
    const { width, height } = pngSize(png);
    if (width > 256 || height > 256) {
      throw new Error(`ICO に入れられるのは 1 辺 256px までです（${width}×${height}）`);
    }
    const entry = Buffer.alloc(ENTRY_SIZE);
    entry.writeUInt8(width % 256, 0);
    entry.writeUInt8(height % 256, 1);
    entry.writeUInt8(0, 2); // パレットの色の数（使わない）
    entry.writeUInt8(0, 3); // 予約
    entry.writeUInt16LE(1, 4); // カラープレーン
    entry.writeUInt16LE(32, 6); // 1 画素のビット数
    entry.writeUInt32LE(png.length, 8);
    entry.writeUInt32LE(offset, 12);
    offset += png.length;
    return entry;
  });
  return Buffer.concat([header, ...entries, ...pngs]);
}

module.exports = { pngSize, pngsToIco };

// スクリプトとして実行されたときだけ書き出す（テストから関数だけ読み込めるように）
if (require.main === module) {
  const [output, ...inputs] = process.argv.slice(2);
  if (output === undefined || inputs.length === 0) {
    process.stderr.write("使い方: node scripts/ico.cjs <出力.ico> <入力.png>...\n");
    process.exit(2);
  }
  writeFileSync(output, pngsToIco(inputs.map((input) => readFileSync(input))));
}
