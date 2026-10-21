# LEARNINGS — dokogacha-app-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない

## ビルド・SDK

- Google Mobile Ads をリンクすると、Info.plist に `GADApplicationIdentifier` が無いアプリは起動直後に `GADApplicationVerifyPublisherInitializedCorrectly` の例外で落ちる（UI テストは `crashed in <external symbol>` とだけ出る）。値は `Configs/Project.xcconfig` の `DG_GAD_APPLICATION_IDENTIFIER`（2026-10-22）
- `-ObjC` を付けると、コードで `import GoogleMobileAds` していなくても SDK のすべてのオブジェクトが読み込まれ、`JSContext` などが未定義でリンクに失敗する。モジュールの `link framework` は import したときにしか効かないので、`OTHER_LDFLAGS` に `-framework JavaScriptCore` を足してある（2026-10-22）

## テスト

- テストのターゲットも既定の分離が MainActor なので、`@Test(arguments: Self.xxx)` に渡す static の一覧は `nonisolated static let` にする（そのままだと `main actor-isolated static property ... cannot be accessed from outside of the actor` でビルドが落ちる。マクロが展開したファイルのエラーとして出る）（2026-10-22）
