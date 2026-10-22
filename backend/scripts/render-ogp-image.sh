#!/usr/bin/env bash
# 招待リンクの固定の OGP 画像（hosting/public/assets/ogp.png。1200×630）を、hosting/ogp/ogp.html から書き出す。
# Google Chrome のヘッドレスで実寸で撮る（Mac で手動で実行する。CI では動かさない）。書き出したら差分を見てコミットする。
#   bash scripts/render-ogp-image.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SOURCE="hosting/ogp/ogp.html"
OUTPUT="hosting/public/assets/ogp.png"

if [ ! -x "${CHROME}" ]; then
  echo "Google Chrome が見つかりません（CHROME で場所を指定できます）: ${CHROME}" >&2
  exit 1
fi

# フォントはリポジトリの Dokogacha/Resources/Fonts を file:// で読むので、ファイルどうしの読み込みを許す
"${CHROME}" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --allow-file-access-from-files --virtual-time-budget=3000 \
  --window-size=1200,630 --screenshot="${PWD}/${OUTPUT}" \
  "file://${PWD}/${SOURCE}" >/dev/null 2>&1

echo "書き出しました: ${OUTPUT}"
