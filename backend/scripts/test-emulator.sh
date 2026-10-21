#!/usr/bin/env bash
# Emulator を起動して、ルールと Functions のテスト（jest.emulator.config.js）を流す。
# 環境変数 DG_EMULATOR_PORT_OFFSET（既定 0）を各ポートに足して起動するので、2 つのスロットで同時に流してもぶつからない。
#   例: DG_EMULATOR_PORT_OFFSET=100 npm run test:emulator
# テスト側は emulators:exec が渡す FIRESTORE_EMULATOR_HOST などの環境変数で、ずらしたポートに接続する。
set -euo pipefail

cd "$(dirname "$0")/.."

# Functions の Emulator は lib/ を読むので、先にビルドする
npm run build

config="$(node scripts/emulator-config.cjs)"
echo "Emulator の設定: ${config}（ポートのずらし: ${DG_EMULATOR_PORT_OFFSET:-0}）"

# Emulator だけを使うので、Google Cloud のメタデータサーバー（GCE）を探しに行かない（探すと待たされ、警告が出る）
export METADATA_SERVER_DETECTION=none

# firebase-tools は devDependencies のものを使う（--no でダウンロードしない）。
# emulators:exec に渡すテストは node_modules/.bin の jest を直接呼ぶ（npx を通すと jest に --config が届かず、テストが見つからなかった）
npx --no firebase emulators:exec \
  --config "${config}" \
  --project demo-dokogacha \
  "./node_modules/.bin/jest --config jest.emulator.config.js"
