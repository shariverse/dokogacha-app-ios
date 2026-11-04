# 人間が用意するものの手順（公開までのセットアップ）

ドコガチャは、Firebase を Emulator だけで動かし、外部サービスはテスト用の値で作ってあります（Discussion #5 の Q2・Q6）。
このファイルは、TestFlight・App Store に出すまでに **人間が外部のコンソールで行う作業** と、その値を **リポジトリのどこに入れるか** を、上から順に実行できる形でまとめたものです。

- このリポジトリは public です。下の手順で扱う秘密情報（`GoogleService-Info.plist`・`.p8` の鍵・SMTP のパスワード・メールアドレス）は、**コミットせず** Secrets・git の管理外のファイル・Secret Manager に置きます
- 「コミットする」と書いた値（App Store の URL・規約とポリシーの URL など）は、公開して問題ない値です
- コマンドは、特に断りがなければリポジトリ直下で実行します。backend のコマンドは `backend/` で実行し、`firebase-tools` は `npx firebase` で使います（グローバルに入れない）
- Firebase のプロジェクトは `dokogacha-dev` の 1 つだけです。Stg（TestFlight）と Release（App Store）の両方がこのプロジェクトに繋ぎます（手順 3。prod のプロジェクトは作らない）
- Web のページ（招待リンクのランディングページ・AASA・利用規約・プライバシーポリシー・サポート）は、運営者のサイトのリポジトリ [shilokuma-inc/shilokuma-web](https://github.com/shilokuma-inc/shilokuma-web)（Cloudflare Pages）が配信します。このリポジトリには Web のページが無く、Firebase Hosting も使いません（手順 10・11。Issue #206）
- 各手順の「確かめ方」に出てくる `#数字` は、実機確認の Issue（ラベル `needs-verify`）です。確かめたら Issue を閉じます

## 目次

1. [Apple Developer の App ID と鍵](#1-apple-developer-の-app-id-と鍵)
2. [App Store Connect のアプリと課金アイテム](#2-app-store-connect-のアプリと課金アイテム)
3. [Firebase のプロジェクト（dokogacha-dev）](#3-firebase-のプロジェクトdokogacha-dev)
4. [GitHub の Secrets と変数](#4-github-の-secrets-と変数)
5. [APNs の認証キーを Firebase に登録する](#5-apns-の認証キーを-firebase-に登録する)
6. [backend のデプロイ（Firestore・Functions）](#6-backend-のデプロイfirestorefunctions)
7. [投稿の報告のメール（SMTP と Trigger Email 拡張）](#7-投稿の報告のメールsmtp-と-trigger-email-拡張)
8. [広告非表示の課金（remove_ads）](#8-広告非表示の課金remove_ads)
9. [AdMob（広告）](#9-admob広告)
10. [ドメイン（dokogacha.shilokuma.jp）と招待リンク・AASA、App Store の URL](#10-ドメインdokogachashilokumajpと招待リンクaasaapp-store-の-url)
11. [利用規約・プライバシーポリシー・サポートのページ](#11-利用規約プライバシーポリシーサポートのページ)
12. [App Store の申請（掲載情報・プライバシーの申告・審査）](#12-app-store-の申請掲載情報プライバシーの申告審査)
13. [実機での確認](#13-実機での確認)
14. [付録: 値の置き場所の一覧](#14-付録-値の置き場所の一覧)

## 全体の流れ

| 順 | 作業 | 主な場所 | ここまでで動くもの |
| --- | --- | --- | --- |
| 1〜2 | App ID の capability・鍵・App Store Connect のアプリ | Apple Developer / App Store Connect | develop の Upload で TestFlight に上がる |
| 3〜5 | Firebase（`dokogacha-dev`）・plist の Secrets・APNs | Firebase / GitHub | TestFlight（Stg）と App Store（Release）が `dokogacha-dev` に繋がる |
| 6〜7 | ルール・Functions のデプロイと報告のメール | `backend/` | サーバーが要る機能（ルーム・抽選・通知・報告）が動く |
| 8〜11 | 課金・広告・ドメイン・規約 | App Store Connect / AdMob / shilokuma-web | 購入・本番の広告・招待リンク・規約のページ |
| 12〜13 | 申請と実機確認 | App Store Connect / GitHub Actions | App Store に出せる |

---

## 1. Apple Developer の App ID と鍵

Team ID は `Configs/Project.xcconfig` の `DEVELOPMENT_TEAM`（`XU74X3434S`）、Bundle ID は `APP_BUNDLE_IDENTIFIER`（`jp.shilokuma.Dokogacha`）です。
Stg（TestFlight）は App Store Connect で本番とは別のアプリにしているので、Bundle ID が違います（`Configs/Stg.xcconfig` の `jp.shilokuma.Dokogacha.stg`。Issue #189）。手順 1・2 は、2 つの App ID のそれぞれで行います。
Debug の Bundle ID（`Configs/Debug.xcconfig` の `jp.shilokuma.Dokogacha.dev`。Issue #210）は、Xcode から実機に入れたときに自動署名が App ID を作るので、ここでは何もしません（App Store Connect のアプリ・Firebase の iOS アプリ・AASA にも登録しない）。

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) の Identifiers で `jp.shilokuma.Dokogacha`（と Stg の `jp.shilokuma.Dokogacha.stg`）を開く（無ければ App IDs で作る。Upload の `-allowProvisioningUpdates` でも作られる。Stg は `develop` の Upload、本番は `release/**` の Upload）
2. Capabilities で次の 3 つを有効にする（`Configs/Dokogacha.entitlements` と同じ）
   - Push Notifications（`aps-environment`）
   - Associated Domains（`applinks:dokogacha.shilokuma.jp`）。ドメインは App ID ではなく entitlements の値なので、capability を有効にした後にドメインを変えても、ここは変えない
   - Sign in with Apple（本番の `jp.shilokuma.Dokogacha` を Primary App ID にし、Stg の App ID はそれとグループにする）
3. Keys で鍵（`.p8`）を作る。**APNs** と **Sign in with Apple** を有効にした鍵を作り（1 つの鍵で両方を有効にしてよい）、Key ID を控える。`.p8` は 1 回しかダウンロードできないので、パスワードマネージャーなどの安全な場所に保管する（リポジトリに置かない）

**確かめ方**: 手順 4 の後の develop の Upload が、署名のエラーなく TestFlight まで通る（#22）。

## 2. App Store Connect のアプリと課金アイテム

1. [App Store Connect](https://appstoreconnect.apple.com/) の「アプリ」→「新規アプリ」で作る。値は Upload ワークフローの Job Summary に出る（アプリが無いと止まって表示する。`.github/scripts/check-app-store-app.rb`）
   - 名前「ドコガチャ」・プライマリ言語「日本語」・バンドル ID `jp.shilokuma.Dokogacha`・SKU は Bundle ID と同じ値
   - Stg（TestFlight）のアプリも別に作る: 名前は App Store 全体で重ならないもの（Job Summary の案は「Dokogacha STG」。端末のホーム画面の名前は本番と同じ「ドコガチャ」で、アイコンの「STG」の帯で見分ける）・バンドル ID `jp.shilokuma.Dokogacha.stg`・SKU は Bundle ID と同じ値。
     バンドル ID は最初の `develop` の Upload の Export で登録されて選べるようになり、ワークフローはアプリが無いので「Check app exists in App Store Connect」で止まる。作ったら Upload を再実行する。Stg のアプリは審査に出さない
   - 名前「ドコガチャ」は、ホーム画面のアイコンの下の日本語の名前（`Dokogacha/InfoPlist.xcstrings` の `ja`）とそろえた値（Discussion #147。`AppStoreMetadataTests` が `AppStore/metadata/ja.json` の `name` と突き合わせる）。App Store 全体で同じ名前のアプリが既にあると使えないので、そのときは名前を決め直し、`ja.json` と `InfoPlist.xcstrings` の両方を直す
2. 「App 情報」の **Apple ID**（数字）を控える。手順 6（`APP_STORE_APP_APPLE_ID`）と手順 10（App Store の URL）で使う
3. 「App 内課金」で **非消耗型** のアイテムを作る
   - 製品 ID `remove_ads`（`DomainConstants.RemoveAds.productID`・`backend/functions/src/domain/constants.ts` の `REMOVE_ADS_PRODUCT_ID` と同じ）
   - 価格 ¥480（06 の §4 の仮決め。`StoreKit/Dokogacha.storekit` も 480）
   - 表示名・説明は「広告を非表示」など。審査用のスクリーンショット（設定画面の購入のボタン）を添える
4. TestFlight の内部テスターにする人を、リポジトリか Organization の変数 `TESTFLIGHT_INTERNAL_TESTERS` に入れる（手順 4）

**App Store Server API のキーについて**: 今の `verifyPurchase` は、StoreKit 2 の署名付きトランザクションを Apple の根の証明書だけで確かめる（`@apple/app-store-server-library` の `SignedDataVerifier`）ので、**App Store Server API のキー（In-App Purchase のキー）は要りません**。
返金を `users.adFree` に反映する（App Store Server Notifications を受ける）・サーバーから購入の履歴を引く処理を足すときに、App Store Connect の「ユーザとアクセス → 統合 → App 内課金」で鍵を作り、Secret Manager に置きます（今回の範囲外）。

## 3. Firebase のプロジェクト（dokogacha-dev）

**`dokogacha-dev` の 1 つだけを作り、Stg（TestFlight）と Release（App Store）の両方が繋ぎます。** prod のプロジェクトは作りません。
スケジュールの関数は 3 つ（手順 6 の Cloud Scheduler のジョブ）で、Cloud Scheduler の無料の枠（請求先アカウントごとに 3 ジョブ）に収めるためです。プロジェクトを 2 つにすると 6 ジョブになり、枠を超えます。
Debug 構成は Emulator の `demo-dokogacha` に繋ぐので、`dokogacha-dev` を使いません。

アプリの構成は Stg（`DG_FIREBASE_ENVIRONMENT = dev`・`GoogleService-Info-Dev.plist`）と Release（`prod`・`GoogleService-Info-Prod.plist`）で別の plist を読む形のままにしてあり、どちらにも `dokogacha-dev` の plist を入れます（Stg は Stg の iOS アプリ、Release は本番の iOS アプリの plist。下の 5 と手順 4）。

1. [Firebase コンソール](https://console.firebase.google.com/) でプロジェクト `dokogacha-dev` を作る。**Google アナリティクスを有効にする**（`FirebaseAnalytics` のイベントを送るため）
2. 料金プランを **Blaze**（従量課金）にする。Cloud Functions（2nd gen）・Cloud Scheduler（スケジュールの関数）・Secret Manager・拡張機能に要る。予算のアラートも設定しておく
3. Firestore のデータベースを作る
   - データベース ID は `(default)`・ロケーションは **`asia-northeast1`（東京）**（Q3。Functions のリージョン `FUNCTIONS_REGION` と拡張の `DATABASE_REGION` もこれ）。ロケーションは後から変えられない
   - 本番モードで作る（ルールは手順 6 でリポジトリの `backend/firestore.rules` をデプロイする）
4. Authentication を始め、ログイン方法で次の 2 つを有効にする
   - **匿名**（F-01。起動時に `signInAnonymously`）
   - **Apple**（設定画面からの連携。F-01・S-15）。アカウントの削除（F-06）でトークンを取り消す（`revokeToken`）ため、Apple のプロバイダの「OAuth コード フローの構成」に Apple の Team ID と、手順 1 の鍵の Key ID・秘密鍵（`.p8` の中身）を入れる。iOS のアプリだけなので、Web 用の Services ID は使わない（コンソールで必須かどうかを確かめて入れる）
5. 「プロジェクトの設定」→「マイアプリ」で iOS アプリを追加する
   - バンドル ID `jp.shilokuma.Dokogacha`・App Store ID（手順 2 の Apple ID）
   - Stg のバンドル ID `jp.shilokuma.Dokogacha.stg` の iOS アプリも追加する（`dokogacha-dev` に 2 つの iOS アプリが並ぶ）。Stg の Secret（手順 4 の `_DEV`）にはこの iOS アプリの plist を、Release の Secret（`_PROD`）には本番の iOS アプリの plist を入れる
   - `GoogleService-Info.plist` をダウンロードする（コードの追加などの手順は飛ばす。SDK は SPM で導入済み）。ファイルは手順 4 で Secret にし、リポジトリに置かない
6. Crashlytics のページを開いて有効にする（dSYM は Upload のときにワークフローが上げる）

手元で Stg / Release を `dokogacha-dev` に繋ぎたいときは、ダウンロードした plist を次の名前で置きます（`.gitignore` の `GoogleService-Info*.plist` で除外済み。コミットしない）。

| 構成 | 置く場所 | 読むキー |
| --- | --- | --- |
| Stg | `Dokogacha/Resources/Firebase/GoogleService-Info-Dev.plist`（Stg の iOS アプリの plist） | xcconfig の `DG_FIREBASE_OPTIONS_FILE_NAME = GoogleService-Info-Dev` |
| Release | `Dokogacha/Resources/Firebase/GoogleService-Info-Prod.plist`（本番の iOS アプリの plist） | `DG_FIREBASE_OPTIONS_FILE_NAME = GoogleService-Info-Prod` |

**確かめ方**: TestFlight（Stg）と Release のアプリを開くと、Authentication のユーザーに匿名のユーザーが増える（#18）。

## 4. GitHub の Secrets と変数

リポジトリの Settings → Secrets and variables → Actions に登録します（Organization にあるものは不要）。

| 種類 | 名前 | 値 | 使うワークフロー |
| --- | --- | --- | --- |
| Secret | `GOOGLE_SERVICE_INFO_PLIST_DEV` | `dokogacha-dev` の Stg の iOS アプリ（`jp.shilokuma.Dokogacha.stg`）の `GoogleService-Info.plist` を `base64 -i GoogleService-Info.plist` にした文字列 | `_archive.yml`（Stg。`develop` の Upload） |
| Secret | `GOOGLE_SERVICE_INFO_PLIST_PROD` | `dokogacha-dev` の本番の iOS アプリ（`jp.shilokuma.Dokogacha`）の plist を base64 にした文字列 | `_archive.yml`（Release。`release/**` の Upload・`main` の Archive） |
| Secret | `EXPORT_OPTIONS` | `docs/ExportOptions.sample.plist` の `teamID` を書き換えた中身 | `_archive.yml` |
| Secret | `APPLE_API_KEY_BASE64`・`APPLE_API_KEY_ID`・`APPLE_API_ISSUER_ID` | App Store Connect API の鍵（App Manager 以上）を base64 にしたものと、Key ID・Issuer ID | `_archive.yml`・`app-store-*.yml` |
| 変数 | `TESTFLIGHT_INTERNAL_TESTERS` | 内部テスターのメールアドレス（カンマ区切り） | `_archive.yml` |
| 変数 | `ENABLE_DELIVERY` | 設定しない（`false` にすると Upload と掲載情報の反映を止める） | `upload.yml`・`app-store-*.yml` |

- plist の Secret が無いとき、Stg は警告を出して Firebase に繋がらないアプリを Archive し、`release/**` の Upload（Release）は止まる。読めない値を入れると Archive の前に止まる
- Archive の後に、アプリの `Info.plist` の `DGFirebaseEnvironment`（Stg は `dev`・Release は `prod`）と、入った plist が構成どおりかを確かめる（「Verify Firebase settings in the app」）
- plist があるときは、Upload のワークフローで Archive と「Verify Firebase settings in the app」の後（Export・Upload の前）に dSYM を Crashlytics に上げる（「Upload dSYMs to Crashlytics」）

**確かめ方**: `develop` への push の Upload で「`GoogleService-Info-Dev.plist` がアプリに入っています」と「dSYM を Crashlytics に上げました（GoogleService-Info-Dev）」が出る。Crashlytics の dSYM の一覧に上がる（#95）。

## 5. APNs の認証キーを Firebase に登録する

1. `dokogacha-dev` の「プロジェクトの設定」→「Cloud Messaging」→「Apple アプリの構成」の「APNs 認証キー」に、手順 1 の `.p8`・Key ID・Team ID を登録する。APNs の設定は iOS アプリごとなので、本番（`jp.shilokuma.Dokogacha`）と Stg（`jp.shilokuma.Dokogacha.stg`）の両方の iOS アプリに同じ鍵を登録する
2. 認証キーは開発用と本番用の両方の APNs に使える。アプリの APNs の環境は xcconfig の `DG_APS_ENVIRONMENT`（Debug は `development`、Stg・Release は `production`）

**確かめ方**: TestFlight のアプリで、解禁・抽選の結果・引き直しの提案の通知が届き、通知から該当の画面が開く（#81）。

## 6. backend のデプロイ（Firestore・Functions）

`backend/.firebaserc` の既定のプロジェクトは Emulator 専用の `demo-dokogacha` です。取り違えを避けるため、実プロジェクト（`dokogacha-dev`）への操作は **毎回 `--project dokogacha-dev` を付けます**（alias を `.firebaserc` に足してもよい。プロジェクト ID は秘密情報ではない）。

1. ログインと依存の用意

   ```bash
   cd backend
   npm ci
   npx firebase login
   ```

2. Functions のパラメータのファイルを `backend/functions/.env.dokogacha-dev` に作る（git の管理外。`.gitignore` の `backend/functions/.env.*`）

   ```bash
   # backend/functions/.env.dokogacha-dev
   REPORT_MAIL_TO=<報告を受け取る運営のメールアドレス>
   APP_STORE_APP_APPLE_ID=<手順 2 の Apple ID（数字）>
   ```

   | パラメータ | 定義 | 中身 |
   | --- | --- | --- |
   | `REPORT_MAIL_TO` | `functions/src/reports/functions.ts` | 投稿の報告（F-14）のメールの宛先。空だと報告は保存されるがメールを書かない（ログにエラー） |
   | `APP_STORE_APP_APPLE_ID` | `functions/src/purchase/functions.ts` | 空のあいだは Sandbox の購入だけを受け付け、**App Store（Production）の購入を受け付けない**。Release も `dokogacha-dev` に繋ぐので、必ず入れる |
   | `APP_STORE_BUNDLE_ID` | 同上 | 既定 `jp.shilokuma.Dokogacha` のままでよい（書かない）。Emulator は `.env.demo-dokogacha` で Debug の `jp.shilokuma.Dokogacha.dev` にしている |

3. ルールとインデックス、Functions をデプロイする（Functions のビルドは `predeploy` が行う）

   ```bash
   npx firebase deploy --only firestore,functions --project dokogacha-dev
   ```

   - 初回は Cloud Build・Artifact Registry・Cloud Scheduler・Eventarc などの API の有効化をたずねられる。Eventarc の権限の反映が間に合わずに失敗したら、数分おいてやり直す
   - `firebase.json` に `hosting` は無い（Web のページは shilokuma-web が配信する。手順 10）。`--only` を付けずに `deploy` すると拡張（手順 7）も入るので、付けて分ける
4. 以前の手順で `dokogacha-dev` の Hosting にデプロイしていたら、配信を止める（Issue #206 の前は Hosting で Web のページを配信していた）

   ```bash
   npx firebase hosting:disable --project dokogacha-dev
   ```

   - 確認をたずねられたら `y` で答える。既定のサイト（`dokogacha-dev.web.app`・`dokogacha-dev.firebaseapp.com`）は消せないが、無効にすれば何も配信されない（もう一度デプロイするまで）
   - Hosting の「カスタム ドメイン」に `dokogacha.shilokuma.jp` を足していたら、Firebase のコンソールで外す。Cloudflare の `dokogacha` に足した Firebase の `A`・`TXT` のレコードは、手順 10 で shilokuma-web の配信に替える
   - 確かめ方: `https://dokogacha-dev.web.app/` を開くと、以前のページではなく Firebase の「Site Not Found」が出る

**確かめ方**:

- Firestore の「インデックス」で、次の複合インデックスがすべて「有効」になる（`backend/firestore.indexes.json`。Emulator はインデックスを強制しないのでテストでは気づけない）

  | コレクション | フィールド | 使うもの |
  | --- | --- | --- |
  | `rooms` | `memberIds`（配列）・`status`・`createdAt`（降順） | ホームの進行中のルーム |
  | `rooms` | `status`・`settings.deadlineAt` | `checkDeadlines` |
  | `rooms` | `reroll.status`・`reroll.proposedAt` | `checkDeadlines`（引き直しの投票の期限） |
  | `rooms` | `status`・`drawnAt` | `autoCloseRooms` |
  | `rooms` | `memberIds`（配列）・`status`・`closedAt`（降順） | ホームの思い出のきっぷ・`autoCloseRooms` |

  単一フィールドの設定（`fieldOverrides`）で、`candidates.createdAt` のコレクショングループの昇順（`notifyNewCandidates`）と、`pastIdeas.sourceClosedAt` が作られている
- Cloud Scheduler（Google Cloud コンソール。リージョン `asia-northeast1`）に次のジョブがあり、実行後のログにエラーが無い

  | 関数 | 間隔（タイムゾーン `Asia/Tokyo`） |
  | --- | --- |
  | `checkDeadlines`（締切の解禁と、引き直しの投票の期限） | 5 分ごと |
  | `autoCloseRooms`（抽選から 7 日で終了） | 毎日 4:00 |
  | `notifyNewCandidates`（新しい候補のまとめ通知） | 毎日 20:00 |

- Functions の一覧に Callable・トリガー（`onMemberWrite`・`onRoomDrawn`・`onRoomClosed`・`onUserProfileUpdate` など）がすべて `asia-northeast1` で並ぶ

## 7. 投稿の報告のメール（SMTP と Trigger Email 拡張）

`reportCandidate` は報告を `reports` に保存し、運営向けのメールを `mail` コレクションに書きます。メールは Trigger Email 拡張（`firebase/firestore-send-email@0.2.10`）が SMTP で送ります（Q7）。拡張の設定はリポジトリにあります（`backend/firebase.json` の `extensions`・`backend/extensions/firestore-send-email.env`）。

1. SMTP の事業者を決め、送信用のアカウントを用意する（送り主のアドレス・接続先・パスワード）
2. SMTP のパスワードを、`dokogacha-dev` の Secret Manager に `firestore-send-email-SMTP_PASSWORD` という名前で置く（拡張の設定はこの名前の `latest` を参照する）

   `firebase functions:secrets:set` は使わない（firebase-tools 15 は大文字・アンダースコアでない名前を `FIRESTORE_SEND_EMAIL_SMTP_PASSWORD` に替えるか聞き、替えると拡張の設定の参照と食い違って拡張がパスワードを読めない）。gcloud で作る（シェルの履歴にパスワードを残さないよう、プロンプトで読む）:

   ```bash
   read -rs SMTP_PASSWORD && printf '%s' "$SMTP_PASSWORD" | gcloud secrets create firestore-send-email-SMTP_PASSWORD --data-file=- --replication-policy=automatic --project dokogacha-dev; unset SMTP_PASSWORD
   ```

   作らずに手順 4 の `firebase deploy --only extensions` を対話のモードで実行しても、Secret が無ければ作るか聞かれる（その場合も名前を替えない）

3. プロジェクトごとの拡張のパラメータを `backend/extensions/firestore-send-email.env.dokogacha-dev` に書く（git の管理外。`.gitignore` の `backend/extensions/*.env.*`）

   ```bash
   SMTP_CONNECTION_URI=smtps://<ユーザー名>@<ホスト>:465
   DEFAULT_FROM=<送り主のアドレス>
   ```

   パスワードは URI に入れない（手順 2 の Secret から読む）。`DATABASE_REGION`（asia-northeast1）などの共通の値は `firestore-send-email.env` にある
4. 拡張をデプロイする。マニフェスト（`firebase.json` の `extensions`）がリポジトリにあるので、`ext:install` はせずに `deploy` で入れる。拡張の関数のロケーションなどをたずねられたら `asia-northeast1` を選ぶ

   ```bash
   npx firebase deploy --only extensions --project dokogacha-dev
   ```

5. 手順 6 の `REPORT_MAIL_TO` が入っていることを確かめる（拡張ではなく Functions のパラメータ）
6. 事業者を決めたら、shilokuma-web のドコガチャのプライバシーポリシーの「投稿の報告のメール」に、事業者名とポリシーへのリンクを足す（手順 11）

**確かめ方**: TestFlight のアプリで、ほかの人の候補を報告すると（S-10 の「この投稿を報告」）、`REPORT_MAIL_TO` にメールが届く。`mail` のドキュメントの `delivery.state` が `SUCCESS` になる。

## 8. 広告非表示の課金（remove_ads）

1. 手順 2 で `remove_ads`（非消耗型・¥480）を作り、審査に出せる状態にする（最初の課金アイテムはアプリのバージョンと一緒に審査に出す）
2. 手順 6 の `APP_STORE_APP_APPLE_ID` を `dokogacha-dev` のパラメータに入れて Functions をデプロイし直す
3. 手元の Xcode で購入を試すときは、Product → Scheme → Edit Scheme → Run → Options の **StoreKit Configuration** に `StoreKit/Dokogacha.storekit` を選ぶ（共有スキーム `Dokogacha.xcodeproj/xcshareddata/xcschemes/Dokogacha.xcscheme` が変わる。コミットすると全員の Run に効き、Archive には効かない。`project.pbxproj` は変わらない）。
   このときの購入は環境が `Xcode` で、Emulator の Functions だけが受け付ける（`purchase/logic.ts` の `verificationEnvironments`）
4. 返金・取り消しを `adFree` に反映する処理は無い（App Store Server Notifications を受ける処理が別に要る。手順 2 の「App Store Server API のキーについて」）

**確かめ方**: TestFlight の Sandbox のアカウントで購入・復元でき、参加中のルームに「◯◯さんのおかげで、このルームは広告なし」が出る（#98・#101）。

## 9. AdMob（広告）

今は Google のテスト用の ID です（`Configs/Project.xcconfig`。Q6）。AdMob は、運営者のサイト `shilokuma.jp` と同じアカウントを使います。

1. `shilokuma.jp` と同じ [AdMob](https://admob.google.com/) のアカウントで iOS のアプリを追加し（App Store に公開した後なら App Store から選ぶ）、**App ID** を控える
2. 広告ユニットを **バナー**（アンカー型アダプティブバナーとして使う）で作り、**広告ユニット ID** を控える
3. 本番の値を xcconfig に書く。`Project.xcconfig` の値を、構成ごとの xcconfig で上書きする

   ```
   // Configs/Release.xcconfig（App Store 用）
   DG_GAD_APPLICATION_IDENTIFIER = ca-app-pub-<パブリッシャー ID>~<アプリの番号>
   DG_BANNER_AD_UNIT_ID = ca-app-pub-<パブリッシャー ID>/<広告ユニットの番号>
   ```

   - 値は Info.plist の `GADApplicationIdentifier`・`DGBannerAdUnitID` に入る。アプリの中に入って配られる値で、秘密情報ではない（`Project.xcconfig` のコメントの「コミットしない」は、ループが本番の値を書かないという意味）。コミットするかどうかはチームで決める（コミットしないなら、CI で書き出す仕組みが別に要る）
   - Stg（TestFlight）はテスト用の ID のままにするのを勧める。本番の ID にするなら、テスターの端末を AdMob のテスト端末に登録して、自分の広告を押さないようにする
4. app-ads.txt は、既存の `https://shilokuma.jp/app-ads.txt` をそのまま使う
   - App Store の開発者の Web サイト（**マーケティング URL**。App Store の「デベロッパWebサイト」）を `https://shilokuma.jp/` にする。AdMob はこの URL のドメインの app-ads.txt を読む。
     値は `AppStore/metadata/shared.json` の `marketingUrl` で、Actions の `Metadata/App Store` で反映する（手順 12）
   - AdMob の管理画面の publisher ID と、`https://shilokuma.jp/app-ads.txt` の行の publisher ID が同じことを確かめる（値はこの手順書にもコードにも書かない）
   - 招待リンクのホスト `dokogacha.shilokuma.jp` には app-ads.txt を置かない。マーケティング URL が `shilokuma.jp` なので AdMob は `dokogacha.shilokuma.jp` を読まず、置くと同じ内容を 2 か所で直すことになる
5. EEA・英国に配信する場合は、AdMob の「プライバシーとメッセージ」で同意のメッセージ（UMP）を作り、アプリに UMP の処理を足す（今回の範囲外。05 の §8）

**確かめ方**: Release のアプリで本番の広告が出て、ATT を拒否すると非パーソナライズ広告になる（#90）。AdMob の app-ads.txt の状態が「確認済み」になる。

## 10. ドメイン（dokogacha.shilokuma.jp）と招待リンク・AASA、App Store の URL

ドメインは、運営者が持つ `shilokuma.jp` のドコガチャ専用のサブドメイン `dokogacha.shilokuma.jp` です（06 の §4）。
招待リンク `/r/{招待コード}`（Universal Links と、アプリが無い端末で開くランディングページ）と `/.well-known/apple-app-site-association`（AASA）を、
運営者のサイトのリポジトリ [shilokuma-inc/shilokuma-web](https://github.com/shilokuma-inc/shilokuma-web) の Cloudflare Pages で配信します。
利用規約・プライバシーポリシー・サポートは、このドメインではなく `shilokuma.jp` に置きます（手順 11）。このリポジトリには Web のページが無く、Firebase Hosting も使いません（Issue #206）。

1. shilokuma-web で `dokogacha.shilokuma.jp` を配信する（カスタムドメイン・Cloudflare の DNS・AASA の `Content-Type`・`/r/*` の振り分けは、shilokuma-web 側で設定する）
   - 以前の手順（Firebase Hosting）で、Cloudflare の `dokogacha` に Firebase の `A`・`TXT` のレコードを足していたら、shilokuma-web の配信に替えるときに消す（同じ名前に別の配信先のレコードが残ると、Cloudflare Pages がカスタムドメインを有効にできない）
   - 足す・消すのは `dokogacha` のレコードだけ。ほかのレコード（ルートの `shilokuma.jp` など）とそのプロキシの設定は変えない
2. AASA は、下の中身をそのまま置く。**この JSON を shilokuma-web に置く中身の正にします**（`UniversalLinksConfigTests` が、アプリの Team ID・本番と Stg の Bundle ID・招待リンクのパスと突き合わせる）。
   AASA を変えるときは、先にここを直してテストを通してから、shilokuma-web の AASA を同じ中身にする

   ```json
   {
     "applinks": {
       "details": [
         {
           "appIDs": ["XU74X3434S.jp.shilokuma.Dokogacha", "XU74X3434S.jp.shilokuma.Dokogacha.stg"],
           "components": [
             {
               "/": "/r/*",
               "comment": "招待リンク（https://dokogacha.shilokuma.jp/r/{招待コード}）。アプリが入っていれば S-06 参加確認を開く"
             }
           ]
         }
       ]
     }
   }
   ```

   - `appIDs` は本番（`Configs/Project.xcconfig` の `DEVELOPMENT_TEAM`・`APP_BUNDLE_IDENTIFIER`）を先に、Stg（`Configs/Stg.xcconfig`）を後に並べる。Debug（`.dev`）は実機では Emulator に繋がらないので並べない
   - 拡張子の無いパスで、`200`・`Content-Type: application/json`・転送なしで返す（Apple の CDN は転送を追わない）
3. 手順 2 の Apple ID で、App Store の URL（仮の `id0000000000`）を差し替える。このリポジトリの `DomainConstants.Web.appStoreURL`（行き先きっぷの共有の画像にも出る）と、shilokuma-web の招待ページ（`landing.js` の `APP_STORE_URL` と、HTML の App Store のリンク）の両方を同じ値にする
4. ドメインを `dokogacha.shilokuma.jp` から変えるときは、`Configs/Project.xcconfig` の `DG_WEB_DOMAIN`（entitlements の `applinks:` はこの値を使う）・`DomainConstants.Web.domain`・`backend/functions/src/domain/constants.ts` の `WEB_DOMAIN` を同時に変える（`DomainConstantsTests`・`UniversalLinksConfigTests` が突き合わせる）。
   shilokuma-web の配信先・招待ページの `og:url` も変える。テスト・コメント・資料にもドメインを書いているので、`git grep -n '<古いドメイン>'` で残りが無いことを確かめる

### shilokuma-web とそろえる値

AASA・招待ページ・規約とポリシーの正本は shilokuma-web にあり、アプリと同じ値を持つ箇所があります。
**片方を変えたら、もう片方も同じ値に変えます。** このリポジトリのテストは shilokuma-web を読まないので、食い違っても CI は通ります（AASA だけは、この手順書の中身とアプリの設定をテストが突き合わせる）。

| 値 | このリポジトリ | shilokuma-web |
| --- | --- | --- |
| AASA の `appIDs`（Team ID・本番と Stg の Bundle ID） | `Configs/Project.xcconfig`・`Configs/Stg.xcconfig`（この手順書の 10 の AASA） | AASA |
| 招待リンクのパス `/r/*` | `DomainConstants.Web.inviteLinkPathPrefix`（この手順書の 10 の AASA） | AASA の `components`・招待ページの振り分け |
| 招待コードの規則（使う文字・6 文字・区切り・入力の正規化） | `Dokogacha/Domain/Logic/InviteCode.swift`・`InviteLink.swift`（Functions の `inviteCode.ts`） | 招待ページの `landing.js` |
| App Store の URL | `DomainConstants.Web.appStoreURL` | 招待ページ（`landing.js` の `APP_STORE_URL`・HTML のリンク） |
| 規約・ポリシー・サポートの URL | `DomainConstants.Web` の `termsURL`・`privacyPolicyURL`・`supportURL`、`AppStore/metadata/shared.json` | ページの置き場所（手順 11） |
| 収集するデータ | `Dokogacha/PrivacyInfo.xcprivacy`・App Store Connect の「App のプライバシー」（手順 12） | プライバシーポリシー |
| アプリアイコンの絵 | `docs/design/app-icon/` の `light.svg`（README の「アプリアイコン」） | 招待ページの favicon・apple-touch-icon・OGP 画像 |

### Universal Links をほかのアプリと干渉させない決まり

`shilokuma.jp` には、同じ運営者のほかのアプリもあります。Universal Links と AASA はホスト名ごとに働くので、次を守れば干渉しません。

- アプリごとに専用のサブドメインを使う（ドコガチャは `dokogacha.shilokuma.jp`。ほかのアプリとホストを分け合わない）
- ルートの `shilokuma.jp` やワイルドカードの `*.shilokuma.jp` を applinks（Associated Domains）に使わない（ほかのアプリのホストまで、このアプリの対象になる）
- AASA の `components` は、そのアプリのパス（ドコガチャは `/r/*`）だけにする

**確かめ方**:

- `curl -sI https://dokogacha.shilokuma.jp/.well-known/apple-app-site-association` が `200` と `content-type: application/json` を返し、転送しない（`location` が無い）。中身が手順 2 の JSON と同じ（`appIDs` が `XU74X3434S.jp.shilokuma.Dokogacha` と `XU74X3434S.jp.shilokuma.Dokogacha.stg` で、Stg の TestFlight のアプリでも招待リンクで開く）
- Apple の CDN が読んだ AASA は `curl -s https://app-site-association.cdn-apple.com/a/v1/dokogacha.shilokuma.jp` で見られる（反映まで時間がかかる）
- `https://dokogacha.shilokuma.jp/r/<招待コード>` がランディングページ（招待コードと「App Store でダウンロード」）を出し、アプリが入った iPhone ではアプリの S-06 が開く（#71）

## 11. 利用規約・プライバシーポリシー・サポートのページ

利用規約とプライバシーポリシーは、運営者のほかのアプリと同じく shilokuma-web の `/terms/<アプリ名>/`・`/privacy/<アプリ名>/` に置きます。サポートは運営者のサイトの `/about/` を使い、ドコガチャ専用のページは作りません。
文面の正本は shilokuma-web にあり、このリポジトリには置きません（以前 `backend/hosting/public/` にあった AI の下書きは shilokuma-web に移した。Issue #206）。

| ページ | URL | 開くところ |
| --- | --- | --- |
| 利用規約 | `https://shilokuma.jp/terms/dokogacha/` | 設定（S-15）の「利用規約」 |
| プライバシーポリシー | `https://shilokuma.jp/privacy/dokogacha/` | 設定（S-15）の「プライバシーポリシー」・App Store の「プライバシーポリシー URL」 |
| サポート | `https://shilokuma.jp/about/` | App Store の「サポート URL」（審査で開かれる） |

URL は末尾のスラッシュまで含めて、`DomainConstants.Web` と `AppStore/metadata/shared.json` に書いてあります（`WebPagesTests`・`AppStoreMetadataTests` が突き合わせる）。ページの場所を変えるときは、shilokuma-web とこの 2 か所を一緒に変えます。

文面は AI の下書きを元にしています（Q8。法的な正しさは保証しない）。人間が shilokuma-web で確認して直します。

1. 目印（`【運営者名】`・`【施行日】`・`【管轄裁判所】`）が残っていれば埋める
2. 法的な確認をする: 規約の免責と消費者契約法・払い戻し・規約の変更（民法 548 条の 4）、ポリシーの外国にある第三者への提供（個人情報保護法 28 条）・電気通信事業法の外部送信規律
3. 実装と照らして確かめる: Sign in with Apple で受け取る情報（名前・メールは要求しない）、報告・Analytics・Crashlytics の保存期間、`Dokogacha/PrivacyInfo.xcprivacy` と App Store Connect の「App のプライバシー」（手順 12）との一致
4. **位置情報の書き方を決める**: 下書きは「本サービスは、端末の位置情報を取得しません」と書いている。アプリは Core Location を使わないが、`PrivacyInfo.xcprivacy` と App Store の申告は AdMob に合わせて **おおよその位置（CoarseLocation。第三者広告）** を収集するとしている（広告の配信事業者が IP アドレスから地域を推定する。判断ログ #119）。
   食い違って見えないよう、たとえば「広告の配信事業者が、IP アドレスからおおよその地域を推定することがあります」を「広告データ」の説明か位置情報の段落に足すかを決める
5. SMTP の事業者名とポリシーへのリンクを「投稿の報告のメール」に足す（手順 7）
6. サポート（`/about/`）に、問い合わせの窓口があることを確かめる（App Store の審査で開かれる）

**確かめ方**: `https://shilokuma.jp/terms/dokogacha/`・`https://shilokuma.jp/privacy/dokogacha/`・`https://shilokuma.jp/about/` が転送なしで `200` を返し、直した文面が出る。アプリの設定画面の「利用規約」「プライバシーポリシー」がそれぞれのページを開く。

## 12. App Store の申請（掲載情報・プライバシーの申告・審査）

掲載情報の元は `AppStore/` にあり、手動実行のワークフローで App Store Connect に反映します（README の「App Store の掲載情報」）。

1. App Store Connect の「App 情報」に、名前「ドコガチャ」・サブタイトル「友達旅行・おでかけの行き先ガチャ」・プライバシーポリシーの URL `https://shilokuma.jp/privacy/dokogacha/` を入れる（「App 情報」の項目なのでワークフローは書き込まない。`upload_metadata.py --check` が形だけ確かめる）
   - 名前はホーム画面の日本語の名前「ドコガチャ」とそろえる（手順 2 の 1）。アプリを先に別の名前（「Dokogacha」など）で作っていたときは、「App 情報」の「ローカライズ可能な情報」で言語を「日本語」にして「名前」を「ドコガチャ」に変え、保存する。名前は審査に出す前（「提出準備中」の間）なら変えられ、出した後に変えるときは新しいバージョンと一緒に審査に出す。App Store 全体で重複している名前は保存できない
   - アプリに英語のローカライズ（`en.lproj`。英語の端末のホーム画面の名前「Dokogacha」のため）が入っているので、App Store の「言語」の欄に「英語」も出る見込み。アプリの文言は日本語だけで、英語の掲載情報は出さない（`AppStore/languages.json` は `ja` だけ）
2. 説明文・キーワード・プロモーションテキストを見直す（`AppStore/metadata/ja.json`）
   - プロモーションテキストの「いいねした候補は少しだけ出やすくなります」は、ルームの「いいねの効き方」が共感ブーストのときだけ正しい。控えめすぎるので文面を見直す
   - キーワードからサブタイトル・名前と重なる語を外す（App Store は名前・サブタイトルの語も検索に使う）
   - 直したら Actions の `Metadata/App Store` を dry-run → 本番の順に流す
3. **App のプライバシーの申告は、Xcode の Privacy Report を正にする**。`PrivacyInfo.xcprivacy` はアプリの分だけで、SDK（Firebase・Google Mobile Ads）の申告は各 SDK の manifest にあるため
   - Xcode で Release を Archive し（Product → Archive）、Organizer でアーカイブを右クリック →「Generate Privacy Report」で PDF を作る
   - PDF の収集データ（種類・ユーザーへの紐付け・トラッキング・目的）を App Store Connect の「App のプライバシー」に入れる。目安は下の表（PR #119。`PrivacyInfo.xcprivacy`）で、食い違ったら Privacy Report に従い、`PrivacyInfo.xcprivacy` と shilokuma-web のプライバシーポリシー（手順 11）も直す

   | 種類 | 紐付け | トラッキング | 目的 |
   | --- | --- | --- | --- |
   | ユーザー ID・名前・その他のユーザーコンテンツ・購入履歴 | ○ | × | アプリの機能 |
   | デバイス ID | ○ | ○ | アプリの機能・分析・第三者広告（IDFA は ATT で許可した人だけ） |
   | 広告データ | ○ | × | 第三者広告 |
   | 製品の操作 | ○ | × | 分析・第三者広告 |
   | おおよその位置 | ○ | × | 第三者広告（AdMob。アプリは Core Location を使わない） |
   | クラッシュデータ | × | × | アプリの機能 |
   | その他の診断データ | × | × | アプリの機能・分析 |
   | パフォーマンスデータ | × | × | 分析・第三者広告 |

4. 年齢区分の質問に答える（ユーザーが投稿する内容がある・報告と削除の仕組みがある・広告がある）
5. 審査メモに書く: 匿名で始まりログインは要らない／ガチャは課金の無い抽選（ルームの候補から行き先を決める）／投稿の報告は候補の詳細（S-10）の「この投稿を報告」、アカウントの削除は設定（S-15）の「アカウントを削除」にある
6. スクリーンショット: `release/**` ブランチで Actions の `Screenshots/App Store` を手動実行する（6.9 inch を撮り、6.3 inch は縮めて作る。iPhone Duo は Xcode 27.1 のランナー。iPad 13 inch は iPad Pro 13-inch の Simulator）。撮る画面は `AppStore/screenshots.json` の 5 つ
7. プロダクトページのヘッダーと検索結果の画像: `AppStore/creative/src/creative.html` の `TODO:`（色と文言）を書き換え、6.9 inch のスクリーンショットから `Tools/render_creative_assets.sh build/screenshots/APP_IPHONE_67` で書き出してコミットし、`Creative assets/App Store` を流す（`TODO:` が残っていると反映が止まる）
8. ビルドを選んで審査に出す（`remove_ads` も一緒に）

## 13. 実機での確認

Simulator で確かめられないことは、実機確認の Issue（ラベル `needs-verify`）にあります。上の手順が終わったら、TestFlight（Stg）と、審査の前に Release で確かめて閉じます（どちらも `dokogacha-dev` に繋ぐ）。
Stg と Release は App Store Connect で別のアプリ（Bundle ID が違う）なので、同じ端末に並べて入れられます。ただし両方を入れた端末で招待リンク（#71）がどちらで開くかは Apple の資料に書かれていないので、招待リンクは片方だけを入れた端末で確かめます。

| Issue | 確かめること | 前提の手順 |
| --- | --- | --- |
| #18 | Stg・Release で `dokogacha-dev` に繋がり匿名認証できる | 3・4 |
| #22 | `develop` の Upload が Stg で TestFlight まで通る | 1・2・4 |
| #95 | Analytics のイベント・Crashlytics・dSYM | 3・4 |
| #81 | プッシュ通知の受信・許可のダイアログ・通知から開く | 5・6 |
| #71 | 招待リンク（Universal Links）で S-06 が開く | 10 |
| #98・#101 | 購入（Sandbox）・復元・Sign in with Apple の連携と切り替え | 3・8 |
| #105 | アカウントの削除・Apple ID の切り替え | 3・6 |
| #90 | ATT の時機・バナー・非パーソナライズ広告 | 9 |
| #56・#59・#73 | 場所の検索・マップで開く・きっぷの共有 | なし |
| #68 | ガチャの触覚・ほかの人が回したときの演出 | 6 |
| #114・#117 | オフラインの表示・VoiceOver・文字最大 | なし |

## 14. 付録: 値の置き場所の一覧

| 値 | 置き場所 | コミット |
| --- | --- | --- |
| Firebase の plist（Stg / Release。どちらも `dokogacha-dev` の iOS アプリ） | Secret `GOOGLE_SERVICE_INFO_PLIST_DEV` / `_PROD`（手元は `Dokogacha/Resources/Firebase/GoogleService-Info-Dev.plist` / `-Prod.plist`） | しない |
| APNs・Sign in with Apple の鍵（`.p8`） | Firebase の Cloud Messaging と Apple のプロバイダの設定 | しない |
| App Store Connect API の鍵 | Secret `APPLE_API_KEY_BASE64`・`APPLE_API_KEY_ID`・`APPLE_API_ISSUER_ID` | しない |
| 報告の宛先 | `backend/functions/.env.dokogacha-dev` の `REPORT_MAIL_TO` | しない |
| App Store の Apple ID（サーバーの検証） | `backend/functions/.env.dokogacha-dev` の `APP_STORE_APP_APPLE_ID` | しない（ファイルごと管理外） |
| SMTP の接続先・送り主 | `backend/extensions/firestore-send-email.env.dokogacha-dev` の `SMTP_CONNECTION_URI`・`DEFAULT_FROM` | しない |
| SMTP のパスワード | Secret Manager の `firestore-send-email-SMTP_PASSWORD` | しない |
| App Store の URL | `DomainConstants.Web.appStoreURL` と、shilokuma-web の招待ページ（手順 10） | する（shilokuma-web はそちらのリポジトリに） |
| AdMob の App ID・広告ユニット ID | `Configs/Release.xcconfig`（`Stg.xcconfig`）の `DG_GAD_APPLICATION_IDENTIFIER`・`DG_BANNER_AD_UNIT_ID` | チームで決める（手順 9） |
| `app-ads.txt` | 既存の `https://shilokuma.jp/app-ads.txt`（shilokuma-web。同じ AdMob のアカウントのアプリで共有。手順 9） | このリポジトリにはしない |
| マーケティング URL（AdMob が読む開発者の Web サイト） | `AppStore/metadata/shared.json` の `marketingUrl`（`https://shilokuma.jp/`） | する |
| AASA | shilokuma-web（中身の正はこの手順書の 10） | このリポジトリにはしない |
| 規約・ポリシー・サポートの URL | `DomainConstants.Web`・`AppStore/metadata/shared.json` の `supportUrl`・`privacyPolicyUrl`（手順 11） | する |
| 規約・ポリシーの文面（運営者名・施行日・管轄裁判所） | shilokuma-web の `/terms/dokogacha/`・`/privacy/dokogacha/`（手順 11） | このリポジトリにはしない |
| 内部テスター | 変数 `TESTFLIGHT_INTERNAL_TESTERS` | しない |
