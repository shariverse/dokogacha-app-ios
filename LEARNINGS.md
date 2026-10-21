# LEARNINGS — dokogacha-app-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない

## ビルド・SDK

- Google Mobile Ads をリンクすると、Info.plist に `GADApplicationIdentifier` が無いアプリは起動直後に `GADApplicationVerifyPublisherInitializedCorrectly` の例外で落ちる（UI テストは `crashed in <external symbol>` とだけ出る）。値は `Configs/Project.xcconfig` の `DG_GAD_APPLICATION_IDENTIFIER`（2026-10-22）
- `-ObjC` を付けると、コードで `import GoogleMobileAds` していなくても SDK のすべてのオブジェクトが読み込まれ、`JSContext` などが未定義でリンクに失敗する。モジュールの `link framework` は import したときにしか効かないので、`OTHER_LDFLAGS` に `-framework JavaScriptCore` を足してある（2026-10-22）
- コードで `FirebaseOptions` を作るとき、API キーが `A` で始まる 39 文字でないと、Firebase Installations が起動直後に `com.firebase.installations` の例外で落とす（Emulator に繋ぐだけでも）。demo の値も形をそろえる。`AIza…` で始めると GitHub の秘密情報の検出に掛かりうるので避ける（2026-10-22）
- フォルダ同期グループのリソースも、xcconfig の `EXCLUDED_SOURCE_FILE_NAMES`（ファイル名）で構成ごとにアプリから外せる（pbxproj を触らずに、Release に Dev の plist を入れない）。ただし差分ビルドは前にコピーしたファイルを消さないので、確かめるときは `Build/Products/<構成>-iphonesimulator` を消してからビルドする（2026-10-22）
- Emulator の Auth のユーザー一覧は `POST http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/demo-dokogacha/accounts:query`（ヘッダー `Authorization: Bearer owner`・本文 `{}`）で取れる（2026-10-22）

## テスト

- テストのターゲットも既定の分離が MainActor なので、`@Test(arguments: Self.xxx)` に渡す static の一覧は `nonisolated static let` にする（そのままだと `main actor-isolated static property ... cannot be accessed from outside of the actor` でビルドが落ちる。マクロが展開したファイルのエラーとして出る）（2026-10-22）

## backend（Firebase）

- Node 22 で使える版: `@firebase/rules-unit-testing` 6 は Node 24.12 以上が要るので 5 系（peer の `firebase` は 12 系）を使う。TypeScript は 6.0 系に留める（`typescript-eslint` は 6.1 未満、`ts-jest` は 7 未満まで）（2026-10-22）
- firebase-tools 15 の `emulators:exec` は、Functions があると eventarc（9299）・tasks（9499）・extensions の Emulator も自動で起動する。ずらさないと 2 つのスロットでぶつかるので、`firebase.json` にポートを書いてある（2026-10-22）
- Firebase の既定のポートのまま 100 ずらすと、hub（4400 → 4500）が、ずらし 0 の logging の既定（4500）とぶつかって `EADDRINUSE` で起動に失敗する。logging は 4600 にしてある（2026-10-22）
- `emulators:exec` に `"npx --no jest --config <設定>"` を渡すと jest に `--config` が届かず、テストが見つからずに失敗した。`./node_modules/.bin/jest` を直接呼ぶ（2026-10-22）
- 2 つのスロットで同時に Emulator を起動すると「running multiple instances of the emulator suite for project demo-dokogacha」と警告が出る（hub の locator が TMPDIR の `hub-<プロジェクト>.json` で共有されるため）。テストは環境変数で接続先を読むので実害はない（2026-10-22）
