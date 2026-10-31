# ドコガチャ（Dokogacha）

友人グループ（最大 20 人）が「行きたい場所」をルームに持ち寄り、いいねで出やすさを少しだけ動かし、準備OKがそろったらガチャ（サーバー側の抽選）で行き先を 1 つに決める iPhone アプリです。

- Bundle ID `jp.shilokuma.Dokogacha`・iOS 17.0 以上・iPhone のみ・縦向き・ライトモード
- 企画・仕様・デザインは [docs/spec/](docs/spec/README.md)（優先順位は `02_requirements.md` ＞ `03_screens.md` ＞ `design/prototype/`）
- 公開までに人間が用意するもの（Firebase・Apple・AdMob・ドメイン・規約・申請）は [docs/setup-human.md](docs/setup-human.md)

## Status

| ブランチ | Build | Archive | Upload | Backend |
| --- | --- | --- | --- | --- |
| `main` | [![Build](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/build.yml?query=branch%3Amain) | [![Archive](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/archive.yml/badge.svg?branch=main)](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/archive.yml?query=branch%3Amain) | | [![Backend](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/backend.yml/badge.svg?branch=main)](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/backend.yml?query=branch%3Amain) |
| `develop` | [![Build](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/build.yml/badge.svg?branch=develop)](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/build.yml?query=branch%3Adevelop) | | [![Upload](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/upload.yml/badge.svg?branch=develop)](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/upload.yml?query=branch%3Adevelop) | [![Backend](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/backend.yml/badge.svg?branch=develop)](https://github.com/shariverse/dokogacha-app-ios/actions/workflows/backend.yml?query=branch%3Adevelop) |

## 画面

| ID | 画面 | コード（`Dokogacha/Features/`） |
| --- | --- | --- |
| S-01 | オンボーディング（表示名の入力） | `Onboarding/` |
| S-02 | ホーム（進行中のルーム・思い出のきっぷ） | `Home/` |
| S-03 | ルーム作成 | `CreateRoom/` |
| S-04 | 招待（招待リンク・コード・前回のメンバーを招待） | `Invite/` |
| S-05・S-06 | 招待コードで参加・参加確認 | `JoinRoom/` |
| S-07 | ルーム（候補・いいね・準備OK・解禁） | `Room/` |
| S-08・S-09 | 候補を追加（場所を探す・過去のアイデア）・投稿の確認 | `AddCandidate/` |
| S-10 | 候補の詳細（マップで開く・削除・報告） | `CandidateDetail/` |
| S-11 | メンバー一覧 | `Members/` |
| S-12 | ルーム設定（作成者のみ） | `RoomSettings/` |
| S-13・S-14 | ガチャ・結果（行き先きっぷ・引き直し・決定） | `Gacha/` |
| S-15 | 設定（表示名・Apple の連携・広告非表示・アカウントの削除・ライセンス） | `Settings/` |

起動の流れ・画面の積み方・通知と招待リンクから開く処理は `Root/`、画面をまたぐ部品は `Shared/` にあります。

## 構成

```
.
├── Dokogacha/                 # アプリ本体（SwiftUI）
│   ├── App/                   # 入口（DokoGachaApp・AppDelegate）・起動引数（LaunchContext）・通知・広告・課金・招待リンクの振り分け
│   ├── Features/<画面>/       # 画面ごとの XxxView と XxxModel（@Observable）
│   ├── DesignSystem/          # Tokens/（tokens.json の色・フォント・寸法）と Components/（DGButton などの部品。Preview 付き）
│   ├── Domain/                # Models/（Firestore のデータの値の型）・Logic/（出やすさ・解禁・招待コードなどの純粋関数）・DomainConstants（仮決めの値）
│   ├── Data/                  # AuthService・RoomRepository・FunctionsClient などの protocol と実装
│   │   ├── Firebase/          #   Firebase の実装と初期化（構成ごとの接続先・Emulator の接続先 FirebaseEmulator.swift）
│   │   ├── InMemory/          #   メモリ上の擬似のサーバー（UI テスト・撮影モード・Preview。デモのデータ DemoScenario）
│   │   ├── GoogleMobileAds/   #   バナー広告
│   │   └── StoreKit/          #   広告非表示の購入（StoreKit 2）
│   ├── Screenshot/            # 撮影モード（ScreenshotDemo）
│   ├── Resources/             # フォント（OFL）・ライセンス・Localizable.xcstrings・Firebase の plist の置き場所（git 管理外）
│   ├── Info.plist             # 構成で変える値は xcconfig の変数を $(…) で参照する
│   └── PrivacyInfo.xcprivacy  # プライバシーマニフェスト
├── DokogachaTests/            # Unit テスト（Swift Testing）
├── DokogachaUITests/          # UI テスト（XCTest。擬似のサーバーで動かす）
├── Dokogacha.xcodeproj        # 共有スキーム Dokogacha。フォルダ同期グループなので、ファイルの追加で pbxproj は変わらない
├── Configs/                   # xcconfig（Project 共通・Debug・Stg・Release）と Dokogacha.entitlements
├── StoreKit/Dokogacha.storekit # ローカルで購入を試す StoreKit Configuration（remove_ads）
├── backend/                   # Firebase（下の「backend」）
├── AppStore/                  # App Store の掲載情報（言語・撮る画面・説明文・クリエイティブアセット）
├── Tools/                     # スクリーンショットの撮影と App Store Connect への反映
├── docs/                      # spec/（企画・仕様・デザイン）・setup-human.md・ExportOptions.sample.plist
├── scripts/                   # ralph-loop の中継（ralph-*.sh・askhub-manual.sh）。rename.sh はテンプレートの名残で使わない
└── .github/                   # ワークフロー・Issue / PR のテンプレート・App Store Connect のスクリプト
```

### backend

```
backend/
├── firebase.json              # Firestore・Functions・Hosting・拡張（Trigger Email）・Emulator のポート
├── .firebaserc                # 既定のプロジェクトは Emulator 専用の demo-dokogacha
├── firestore.rules            # セキュリティルール（05 の §4）
├── firestore.indexes.json     # 複合インデックス
├── functions/                 # Cloud Functions（TypeScript・Node 22・2nd gen・asia-northeast1）
│   └── src/                   # index.ts で包み、処理は rooms/・candidates/・unlock/・draw/・reroll/・close/ などの service.ts・logic.ts・input.ts
├── extensions/                # Trigger Email 拡張の共通の設定（プロジェクトごとの値は git 管理外）
├── hosting/public/            # 招待リンクのランディングページ（/r/{code}）・AASA・利用規約・プライバシーポリシー・サポート・favicon・apple-touch-icon
├── hosting/test/              # Hosting のページの Jest
├── test/emulator/             # ルールと Functions の Emulator のテスト
└── scripts/                   # Emulator のポートをずらす設定の書き出し（emulator-config.cjs）とテストの起動（test-emulator.sh）・OGP 画像と favicon の書き出し
```

- `backend/` は npm workspaces（`functions/` を含む）で、`package-lock.json` は 1 つだけです。`firebase-tools` は devDependencies にあり、`npx firebase` で使います（グローバルに入れない）
- アプリと同じ判定（出やすさ・解禁・抽選・招待コード・名前の検証）を TypeScript でも持ち、同じケースを Swift Testing と Jest の両方で確かめています

## 開発環境

- Xcode 26.6（CI の `_build.yml`・`_archive.yml` の `xcode-version` と同じ）
- Swift 6（言語モード 6・Strict Concurrency complete・既定の分離は MainActor）・SwiftUI・Swift Testing・XCTest
- SwiftLint 0.65.1（Build Tool Plugin。[SwiftLintPlugins](https://github.com/SimplyDanny/SwiftLintPlugins) 経由）
- SPM: firebase-ios-sdk 13（Auth・Firestore・Functions・Messaging・Analytics・Crashlytics）・Google Mobile Ads 13
- backend: Node 22・Java 21（Firestore の Emulator に要る）

## ビルド

ビルド構成は 3 つで、構成ごとの値は `Configs/<構成>.xcconfig` にあります。

| 構成 | 使いどころ | Firebase の接続先（`DG_FIREBASE_ENVIRONMENT`） | 読む設定 | アプリアイコン（`DG_APP_ICON_NAME`） |
| --- | --- | --- | --- | --- |
| Debug | 開発・テスト | `emulator`（`demo-dokogacha`） | plist を読まず、コードで作った `FirebaseOptions`。接続先は `Dokogacha/Data/Firebase/FirebaseEmulator.swift`（`localhost`・auth 9099・firestore 8080・functions 5001） | `AppIcon-Debug`（下端に墨色の帯の「DEV」） |
| Stg | TestFlight（`develop` の Upload） | `dev` | `Dokogacha/Resources/Firebase/GoogleService-Info-Dev.plist` | `AppIcon-Stg`（下端に黄色の帯の「STG」） |
| Release | App Store（`release/**` の Upload・`main` の Archive） | `prod` | `Dokogacha/Resources/Firebase/GoogleService-Info-Prod.plist` | `AppIcon`（目印なし。App Store に出すもの） |

- plist はコミットしません（public リポジトリ）。CI が Secrets から書き出し、手元では各自 Firebase のコンソールから落として上の名前で置きます（手順は [docs/setup-human.md](docs/setup-human.md) の 3・4）
- plist が無い・読めないときも落ちずに起動し、「サーバーに接続できません」の状態になります。構成に合わない plist は `EXCLUDED_SOURCE_FILE_NAMES` でアプリに入りません
- Unit テストのホストと、起動引数 `-uiTesting`（UI テスト）・`-screenshot-demo`（撮影モード）では Firebase を初期化せず、メモリ上の擬似のサーバー（`Dokogacha/Data/InMemory/`）で動きます
- 署名・バージョンは `Configs/Project.xcconfig`（`DEVELOPMENT_TEAM`・`APP_BUNDLE_IDENTIFIER`・`MARKETING_VERSION`）。ビルド番号は Upload のときに Xcode が App Store Connect の最新を見て増やします

## テスト

```bash
# Simulator は名前ではなく UDID で指定する（xcrun simctl list devices available）。DerivedData はリポジトリの外に置く
xcodebuild test -project Dokogacha.xcodeproj -scheme Dokogacha \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath <DerivedData> \
  -skipPackagePluginValidation -skipMacroValidation -parallel-testing-enabled NO
# Unit テストだけ: -only-testing:DokogachaTests を足す

# SwiftLint（CI と同じ。SPM が解決したバイナリを使う）
"$(find <DerivedData>/SourcePackages/artifacts -type f -name swiftlint -path '*macos*' | head -1)" lint --strict
```

- `-skipPackagePluginValidation -skipMacroValidation` を付けないと、Xcode の画面で信頼していない DerivedData では SwiftLint のプラグインで止まります
- UI テストは擬似のサーバーで動き、デモのデータを `-uiTesting -demo-scenario <名前>` で選びます（`DemoScenario`）。ほかのメンバーの参加・準備OKが要る通しのシナリオは `-ui-auto-members` を足します

backend（`backend/` で実行）:

```bash
cd backend
npm ci                  # 依存を lock ファイルどおりに入れる（functions/ の分も）
npm run typecheck       # tsc --noEmit
npm run lint            # ESLint（警告も失敗）
npm test                # Jest（Functions のロジック・Hosting のページ・scripts/。Emulator を使わない）
npm run test:emulator   # Emulator を起動して、ルールと Functions のテストを流す（Functions をビルドしてから）
npm run build           # Functions を functions/lib/ にビルドする
```

- Emulator のポートは `firebase.json`（auth 9099・firestore 8080（WebSocket 9150）・functions 5001・hosting 5002・hub 4400・logging 4600・eventarc 9299・tasks 9499。UI は無効）
- **ポートのずらし**: 環境変数 `DG_EMULATOR_PORT_OFFSET`（既定 0）を付けると、各ポートに足して起動します（例: `DG_EMULATOR_PORT_OFFSET=100 npm run test:emulator`）。2 つの作業場所で同時に流すときにずらします。ずらした設定は git 管理外の `backend/firebase.emulators.local.json` に書き出されます

## Emulator でアプリを動かす

Debug のアプリは Emulator（ずらし 0 のポート）に繋ぎます。

```bash
cd backend
npm run build   # Functions の Emulator は functions/lib/ を読む
npx --no firebase emulators:start --only auth,firestore,functions --project demo-dokogacha
```

起動したら、Xcode で Debug のアプリを Simulator で動かします。Emulator にはデータが残らない（終了すると消える）ので、ルームは毎回作り直します。

- Auth のユーザーは `curl -s -X POST -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' -d '{}' http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/demo-dokogacha/accounts:query` で見られます
- Emulator には FCM が無いので、通知は送らずに Firestore の `emulatorPushOutbox` に書きます
- 招待リンクのランディングページ・規約のページは `npx --no firebase emulators:start --only hosting --project demo-dokogacha` で `http://localhost:5002/r/ABC234` などを開けます

## 撮影モード

撮影モードは、App Store と PR のスクリーンショットのために、目的の画面を擬似のサーバーのデモのデータで開く起動のしかたです（[Dokogacha/Screenshot/](Dokogacha/Screenshot/ScreenshotDemo.swift)）。Firebase・通知・ATT・広告は使いません。

```bash
xcrun simctl install <UDID> <DerivedData>/Build/Products/Debug-iphonesimulator/Dokogacha.app
xcrun simctl launch <UDID> jp.shilokuma.Dokogacha -screenshot-demo -screenshot-scene room -demo-scenario room-with-candidates
xcrun simctl io <UDID> screenshot room.png
```

| 起動引数 | 効く画面（scene） | 中身 |
| --- | --- | --- |
| `-screenshot-demo` | すべて | 撮影モードにする |
| `-screenshot-scene <名前>` | すべて | 開く画面。`ScreenshotDemo.Scene` の case（`home`・`onboarding`・`createRoom`・`invite`・`settings`・`room`・`candidateDetail`・`addCandidate`・`members`・`roomSettings`・`gacha`・`result`・`resultMember`・`homeMemories`・`pastIdeas`・`inviteLastMembers`・`roomInvite`・`roomAdFree`・`settingsAppleLinked`・`settingsAdFree`・`settingsDeleteAccount`・`licenses`）。無ければホーム |
| `-demo-scenario <名前>` | すべて | デモのデータ（`DemoScenario`）。撮影モードの既定は `several-rooms` |
| `-screenshot-ad-placeholder` | 広告のある画面 | バナー広告の場所に固定の枠を出す（App Store の撮影では付けない） |
| `-network-offline` | すべて | オフラインのことにする（「オフラインです」の帯） |
| `-open-url <URL>`・`-open-notification <JSON>` | すべて | 招待リンク・通知から開いたことにする（UI テストと共通） |
| `-screenshot-display-name <名前>` | `onboarding` | 入力欄に名前を入れておく |
| `-screenshot-room-name <名前>`・`-screenshot-unlock-rule <値>` | `createRoom` | ルーム名と解禁の条件を入れておく |
| `-screenshot-like <候補の ID>`・`-screenshot-ready <uid,…>`・`-screenshot-force-unlocked`・`-screenshot-confirm-force-unlock` | `room` | いいね・準備OK・強制解禁・その確認のダイアログ |
| `-screenshot-candidate <ID>`・`-screenshot-not-owner`・`-screenshot-confirm-delete`・`-screenshot-report-reasons`・`-screenshot-reported` | `candidateDetail` | 開く候補・他人のルーム・削除の確認・報告の理由・報告した後 |
| `-screenshot-query <語>` | `addCandidate` | 検索しておく語（既定は「水族館」） |
| `-screenshot-search-area <エリア>` | `addCandidate` | 選んでおくエリア（`SearchArea` の rawValue。`kanto`・`hokkaido` など。既定は全国） |
| `-screenshot-past-ideas-empty` | `pastIdeas` | 過去のアイデアが無い状態 |
| `-screenshot-not-owner`・`-screenshot-ready <uid,…>`・`-screenshot-unlocked`・`-screenshot-post-limit <数>` | `members`・`roomSettings`・`roomInvite` | 作成者以外・準備OK・強制解禁した後・投稿数を変えた状態（`roomInvite` は S-07 の上に招待のシートを出す） |
| `-screenshot-gacha <状態>` | `gacha` | `ready`（既定）・`dispensed`・`others`・`others-live`・`play` |
| `-screenshot-result <状態>`・`-screenshot-reroll <状態>`・`-screenshot-result-animate` | `result` | 当選（`normal`・`rare`）・引き直し（`voting`・`passed`・`used`）・きっぷを動かす |
| `-screenshot-result-closed` | `resultMember` | 終了したルームの閲覧のみ |
| `-screenshot-memories-only` | `homeMemories` | 進行中のルームを足さない |
| `-screenshot-invite-last-members` | `inviteLastMembers` | 「前回のメンバーを招待」を押した状態 |

- 文字を最大にした画面は `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` を足します
- 画面を足すときは、`ScreenshotDemo.Scene` に case を足し（`enum Scene: String {` の形と 1 行 1 case を保つ。`Tools/app_store_config.py` が読む）、`Dokogacha/App/DokoGachaApp.swift` の `rootView` で開く画面を返します。App Store に載せるときは `AppStore/screenshots.json` の `scenes` にも足します

## CI（GitHub Actions）

| ワークフロー | 動くとき | すること |
| --- | --- | --- |
| `build.yml`（→ `_build.yml`） | すべてのブランチの push・PR の作成など（`**/*.md`・`docs/**`・`backend/**` だけの変更では動かない） | SwiftLint（`--strict`）・ビルド・Unit テスト・UI テスト（作業ブランチの push では Unit テストだけ） |
| `backend.yml` | `backend/**` の変更の push・Fork からの PR | `npm ci`・型検査・lint・Jest・Emulator のテスト（ubuntu） |
| `upload.yml`（→ `_archive.yml`） | `develop`・`release/**` の push・手動実行 | Archive → IPA → App Store Connect（`develop` は Stg、`release/**` は Release）・dSYM を Crashlytics に |
| `archive.yml`（→ `_archive.yml`） | `main` の push・手動実行 | Release で Archive → IPA（アップロードしない） |
| `verify-app-store-metadata.yml` | `AppStore/**`・`Tools/**`・撮影モードなどを変えた PR | 掲載情報の文字数・撮影の設定・撮影モードの scene の対応 |
| `app-store-screenshots.yml`・`app-store-metadata.yml`・`app-store-creative-assets.yml` | 手動実行 | App Store のスクリーンショット・説明文・クリエイティブアセットの反映 |
| `close-goal-discussion.yml` | `develop` 宛ての PR が閉じたとき | ralph-loop の epic の最終 PR がマージされたら、ゴールの Discussion を閉じる（ralph-kit が置く） |

- PR での Build: 同じリポジトリのブランチは push で動いているので、PR では作成時など（`synchronize` 以外）にだけ UI テスト込みで動きます。`epic/**` 宛ての PR（ralph-loop の子 PR）では動かず、`epic/**` から `develop` などへの PR は更新のたびに UI テスト込みで動きます
- **Fork からの PR** は push で動かないので、更新を含むすべてのイベントで UI テストまで動きます。Secrets は渡りませんが、Build（Debug）は plist を使わないので通ります。Archive・Upload は Fork の PR では動きません
- Upload に要る Secrets（`EXPORT_OPTIONS`・`APPLE_API_KEY_*`・`GOOGLE_SERVICE_INFO_PLIST_DEV` / `_PROD`）と変数（`TESTFLIGHT_INTERNAL_TESTERS`・`ENABLE_DELIVERY`）は [docs/setup-human.md](docs/setup-human.md) の 4 にあります
- App Store Connect にアプリが無いと、Upload はアップロードの前に「新規アプリ」に入れる値を Job Summary に出して止まります（`.github/scripts/check-app-store-app.rb`）

## App Store の掲載情報

`AppStore/` の JSON を元にして、手動実行のワークフローで App Store Connect に反映します。反映先は「編集できる状態のバージョン」だけです。

- 言語は日本語だけ（`AppStore/languages.json`。02 の §10 で多言語は対象外）
- スクリーンショット: `AppStore/screenshots.json` の 5 つ（ルーム・ガチャ・行き先きっぷ・過去のアイデア・招待）を、`release/**` ブランチで `Screenshots/App Store` を手動実行して撮ります。6.9 inch を撮り、6.3 inch は縮めて作り、iPhone Duo は Xcode 27.1 のランナーで撮ります。手元では `Tools/capture_screenshots.sh APP_IPHONE_67 ja`（出力は `build/screenshots/`）
- 説明文など: `AppStore/metadata/ja.json`・`shared.json`（URL は `DomainConstants.Web` と同じ。`AppStoreMetadataTests` が突き合わせる）を `Metadata/App Store` で反映します（既定は dry-run）
- プロダクトページのヘッダーと検索結果: `AppStore/creative/src/creative.html` から `Tools/render_creative_assets.sh` で書き出し、`Creative assets/App Store` で反映します（`TODO:` が残っていると止まる）
- 「App のプライバシー」の申告は Xcode の Privacy Report を正にします（[docs/setup-human.md](docs/setup-human.md) の 12）

## アプリアイコン

元データは `docs/design/app-icon/` の SVG（外観ごとに `light.svg`・`dark.svg`・`tinted.svg`）で、`Tools/render_app_icon.sh` で `Dokogacha/Assets.xcassets/AppIcon.appiconset/` の 3 枚（1024×1024）と `Contents.json` に書き出します。
同じ実行で、下端に構成の目印の帯（「DEV」「STG」。書体は Mochiy Pop One）を重ねた `AppIcon-Debug`・`AppIcon-Stg` のアイコンセットも書き出します（帯は `Tools/render_icon_badge.swift` で描く）。
どの構成でどのアイコンセットを使うかは `Configs/<構成>.xcconfig` の `DG_APP_ICON_NAME` で、`AppIconConfigurationTests` が xcconfig・アイコンセット・`AppStore/app.json` を突き合わせます。

```bash
Tools/render_app_icon.sh             # 採用した案からアイコンセットを書き出す
Tools/render_app_icon.sh candidates  # 案を作り直すとき: docs/design/app-icon/candidates/<案>/ の SVG を PNG に書き出す
```

- ライト（`AppIcon.png`）は背景あり・アルファなし・角丸なし（角丸は OS が付ける）。アルファが残る・塗られていない画素があると書き出しが止まります
- ダーク（`AppIcon-Dark.png`）は背景を透過にし（OS が暗い背景を敷く）、ティント（`AppIcon-Tinted.png`）は背景を透過にしたグレースケールです（OS が明るさに応じて色を乗せる）
- 書き出しは macOS の NSImage（`Tools/render_svg.swift`）なので、SVG は図形だけで描きます（`<text>`・フィルター・CSS は描けないことがある）。色は `docs/spec/design/tokens.json` の値だけを使います（ティントだけは、トークンの色をその明るさの灰色に置き換えた `#FFFFFF`・`#CACACA`（`accent.secondary`）・`#222222`（`ink`）を使う）
- `AppStore/app.json` の `appIcon` が `AppIcon.png` を指しているので、App Store のクリエイティブアセットも同じ絵になります
- 書き出しの作業ファイル・候補を `Dokogacha/` に置かないでください（フォルダ同期でアプリに入ります）
- Hosting の favicon（`backend/hosting/public/favicon.ico`。16・32・48px の PNG を入れた ICO）と apple-touch-icon（`apple-touch-icon.png`。180px・透過なし）も、同じ `light.svg` から `backend/` で `bash scripts/render-favicons.sh` で書き出します（ICO は `scripts/ico.cjs` で作る）。アイコンを変えたら書き出し直してください

## PR 本文のスクリーンショット

UI の見た目が変わる変更では、Before / After を Markdown の表で並べ、`gh pr create` / `gh pr edit` の `--attach` で添付します（gh v2.99.0 以上。リポジトリ・ブランチに画像を置かない）。

```bash
# body.md の表に ![Before](./before.png) と ![After](./after.png) を書いておく
gh pr create --title "..." --body-file body.md --assignee @me \
  --attach ./before.png --attach ./after.png

# 本文の画像を幅 300 の <img> に置き換える（本文を取得できたときだけ更新する）
body=$(gh pr view <番号> --json body -q .body) &&
  printf '%s\n' "$body" \
  | perl -pe 's{!\[([^\]]*)\]\((https://github\.com/user-attachments/assets/[^)\s]+)\)}{<img src="$2" alt="$1" width="300">}g' \
  | gh pr edit <番号> --body-file -
```

アップロードした画像は消せません。個人情報やトークンが写っていないか確かめてから添付します。

## 実装で決めたこと（資料との違い）

資料（`docs/spec/`）に無いこと・資料どうしが食い違うことは、実装のときに決めて判断ログ（Issue #11）に 1 行ずつ残しています。資料は書き換えていないので、資料と実装が違う主なところを挙げます。詳しくは判断ログと各 PR の「資料どうしの食い違い」を見てください。

- **書き込みの経路**: 05 の §4 のルールの骨子は `users.displayName` の直接の更新を許すが、整合性のため Callable `saveProfile` だけで書く（色はサーバーがランダムに決める）。参加の前の確認（S-06）に、05 に無い Callable `previewRoom` を足した
- **解禁の判定し直し**: 05 の §5 は `joinRoom`・`leaveRoom` の中で判定し直すとしているが、数え直しを 1 か所にするためトリガー `onMemberWrite` に集める。`forceUnlock` は 02 の F-32 に従い `open` のときだけ
- **データの項目**: `rooms.drawnAt`・`closedAt` は任意（抽選・終了の前は無い）。`reports` に報告の時点の候補の内容 `candidate` を足した（05 の §5 にも追記）。いいねの二度押し（何も変えない書き込み）はルールで通す
- **UI テスト**: 06 の §2 は「Emulator に接続」だが、メモリ上の擬似のサーバーで流す（CI の macOS で Emulator を並べると重いため）。Emulator は backend のテストだけ
- **仮決めの値**: Remote Config を使わず、Swift（`DomainConstants`）と TypeScript（`functions/src/domain/constants.ts`）の定数にまとめた
- **見た目**: 04 とプロトタイプが違うところは 04 に従った（無効のボタンの色・余白・文字の太さ・スタンプの線など）。04 の幅のある値は tokens.json の値
- **画面**: S-14 は 03 の §3 に従ってヘッダーを残した。バナーの高さは 03 の目安 50pt ではなく、Google Mobile Ads 13 のアンカー型アダプティブバナー（約 115pt）。プロトタイプの強制解禁のトーストは出さない
- **レア当選**: プロトタイプは丸めた % で比べるが、02 の §6.3 どおり丸める前の確率で比べる
- **フォルダ**: 05 の §2 の `Features/Room/` の下に置くとした候補の詳細・メンバー・ルーム設定は、`Features/CandidateDetail/`・`Members/`・`RoomSettings/` に分けた
- **経過時間**: 06 の §2 は Swift と TypeScript の両方に載せているが、サーバーで使わないので Swift だけ
- **ホーム画面のアプリ名**（Discussion #147）: `Dokogacha/InfoPlist.xcstrings` で `CFBundleDisplayName` を日本語「ドコガチャ」・英語「Dokogacha」にした（`PRODUCT_NAME`・Bundle ID は変えていない）。
  開発言語が日本語なので、足したローカライズは `en`。pbxproj を編集しないため、`knownRegions` は `ja`・`Base` のまま（足さなくても `en.lproj` はアプリに入る）。
  `en` が入ったので、英語の端末ではアプリの言語が英語として扱われ、システムが出す部品（日時の選択・地図の表記・共有シートなど）と締切の曜日が英語になる。アプリの文言は日本語のまま。
  日本語・英語のどちらでもない端末（フランス語など）も `en` が選ばれ、ホーム画面は「Dokogacha」になる。`Info.plist` には `CFBundleDisplayName` を書いていない（無くても言語ごとの値が出る。どの言語の値も無いときは `PRODUCT_NAME`）

## License

[MIT License](LICENSE)
