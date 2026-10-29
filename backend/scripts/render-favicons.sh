#!/usr/bin/env bash
# Hosting の favicon（hosting/public/favicon.ico。16・32・48px）と apple-touch-icon（hosting/public/apple-touch-icon.png。180px・透過なし）を、
# アプリアイコンの元データ（リポジトリの docs/design/app-icon/light.svg）から書き出す。
# SVG の書き出しはアプリアイコンと同じ Tools/render_svg.swift（macOS の NSImage）を使うので、Mac で手動で実行する（CI では動かさない）。
# 書き出したら差分を見てコミットする。
#   bash scripts/render-favicons.sh
set -euo pipefail

cd "$(dirname "$0")/.."

REPOSITORY_DIR="$(cd .. && pwd)"
SOURCE="${REPOSITORY_DIR}/docs/design/app-icon/light.svg"
PUBLIC_DIR="hosting/public"
FAVICON_SIZES=(16 32 48)
APPLE_TOUCH_ICON_SIZE=180

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
xcrun swiftc -O "${REPOSITORY_DIR}/Tools/render_svg.swift" -o "${WORK}/render_svg"

# どちらも背景ありの絵（ライト）なので、透過なしで書き出す（iOS は apple-touch-icon の透けたところを黒にする）
favicons=()
for size in "${FAVICON_SIZES[@]}"; do
  "${WORK}/render_svg" --opaque "${SOURCE}" "${WORK}/favicon-${size}.png" "${size}"
  favicons+=("${WORK}/favicon-${size}.png")
done
node scripts/ico.cjs "${PUBLIC_DIR}/favicon.ico" "${favicons[@]}"
"${WORK}/render_svg" --opaque "${SOURCE}" "${PUBLIC_DIR}/apple-touch-icon.png" "${APPLE_TOUCH_ICON_SIZE}"

echo "書き出しました: ${PUBLIC_DIR}/favicon.ico・${PUBLIC_DIR}/apple-touch-icon.png"
