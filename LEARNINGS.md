# LEARNINGS — dokogacha-app-ios の知見

このリポジトリだけで通じる知見を溜める（全リポジトリ共通の知見は `~/.agents/LEARNINGS.md`）。

- 1 項目 = 1 つの箇条書き。日付（YYYY-MM-DD）を添える
- コードや git の履歴を読めば分かることは書かない。PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない

## ビルド・SDK

- Google Mobile Ads をリンクすると、Info.plist に `GADApplicationIdentifier` が無いアプリは起動直後に `GADApplicationVerifyPublisherInitializedCorrectly` の例外で落ちる（UI テストは `crashed in <external symbol>` とだけ出る）。値は `Configs/Project.xcconfig` の `DG_GAD_APPLICATION_IDENTIFIER`（2026-10-22）
- `-ObjC` を付けると、コードで `import GoogleMobileAds` していなくても SDK のすべてのオブジェクトが読み込まれ、`JSContext` などが未定義でリンクに失敗する。モジュールの `link framework` は import したときにしか効かないので、`OTHER_LDFLAGS` に `-framework JavaScriptCore` を足してある（2026-10-22）
- コードで `FirebaseOptions` を作るとき、API キーが `A` で始まる 39 文字でないと、Firebase Installations が起動直後に `com.firebase.installations` の例外で落とす（Emulator に繋ぐだけでも）。demo の値も形をそろえる。`AIza…` で始めると GitHub の秘密情報の検出に掛かりうるので避ける（2026-10-22）
- フォルダ同期グループのリソースも、xcconfig の `EXCLUDED_SOURCE_FILE_NAMES`（ファイル名）で構成ごとにアプリから外せる（pbxproj を触らずに、Release に Dev の plist を入れない）。ただし差分ビルドは前にコピーしたファイルを消さないので、確かめるときは `Build/Products/<構成>-iphonesimulator` を消してからビルドする（2026-10-22）
- `Configs/*.xcconfig` はプロジェクトの階層に付いているので、Unit・UI テストのターゲットにも効く。アプリのターゲットだけに付けたい設定（`CODE_SIGN_ENTITLEMENTS` など）は、`X = $(DG_X_$(PRODUCT_TYPE:identifier))` と `DG_X_com_apple_product_type_application = …` の形で分ける（`xcodebuild -showBuildSettings -target <ターゲット>` で確かめられる）（2026-10-22）
- firebase-ios-sdk 13 の FirebaseMessaging は、登録トークンの API（`token()`・`deleteToken()`・`fcmToken`）を非推奨にして Firebase Installations の ID で登録する方式（`register`）を勧めている（既定は従来のトークン）。05 の §3 の `users.fcmTokens` で送るので従来の API を使い、呼ぶ関数に `@available(*, deprecated)` を付けて警告を止めている（protocol を通して呼ぶので呼ぶ側にも出ない。`FirebasePushTokenProvider`）（2026-10-22）
- FCM の AppDelegate の差し替え（swizzling）は `Info.plist` の `FirebaseAppDelegateProxyEnabled = NO` で止め、APNs のトークンは `AppDelegate` から `Messaging.apnsToken` に渡している（SwiftUI の `UIApplicationDelegateAdaptor` と `UNUserNotificationCenter.delegate` を自分で持つため）。Simulator のビルドの entitlements は `Dokogacha.app-Simulated.xcent`（`Dokogacha.app.xcent` は空）で確かめる（2026-10-22）
- Emulator の Auth のユーザー一覧は `POST http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/demo-dokogacha/accounts:query`（ヘッダー `Authorization: Bearer owner`・本文 `{}`）で取れる（2026-10-22）

## テスト

- テストのターゲットも既定の分離が MainActor なので、`@Test(arguments: Self.xxx)` に渡す static の一覧は `nonisolated static let` にする（そのままだと `main actor-isolated static property ... cannot be accessed from outside of the actor` でビルドが落ちる。マクロが展開したファイルのエラーとして出る）（2026-10-22）
- Unit テスト（Simulator）からは、`URL(fileURLWithPath: #filePath)` を起点にリポジトリのファイル（例: `docs/spec/design/tokens.json`）をそのまま読める。資料の正本をテストのバンドルに複製せずに突き合わせられる（`DesignTokensTests`）。実機でテストを流すとホストのパスは読めない（2026-10-22）
- Swift と TypeScript で同じ判定を持つとき、Swift の `String` の `==` は正準等価（`"が" == "か\u{3099}"` が true）、`hasPrefix` は書記素の単位（`"https://\u{0301}a".hasPrefix("https://")` が false）で比べるので、TypeScript の `===`・`startsWith`（UTF-16 のコード単位）と結果が変わる。そろえるときは `utf16.elementsEqual`・`unicodeScalars` で比べる（`CandidateRules`）（2026-10-22）
- `Color.resolve(in: EnvironmentValues()).red` などは sRGB のガンマ補正済みの値（`linearRed` が線形）。`× 255` して丸めると `Color(.sRGB, red:…)` で作った `#RRGGBB` と一致する（2026-10-22）
- `.toolbar(.hidden, for: .navigationBar)` で標準のナビゲーションバーを隠すと、iOS 26.5 では端からのスワイプで戻れなくなる。`MainNavigationView` の根元に付けた `InteractivePopGesture` がジェスチャーの delegate を差し替えている。UI テストで確かめるときは `swipeRight()` ではなく、`coordinate(withNormalizedOffset:)` の x 0.005 から `press(forDuration:thenDragTo:)` で動かす（`swipeRight()` は端から始まらない）（2026-10-22）
- `@Test(arguments:)` に `[String: AnyHashable]` の一覧は渡せない（Swift 6 では `AnyHashable` が `Sendable` でない）。`[String: String]` にするか、値の種類ごとにテストを分ける（2026-10-22）
- 文字を最大にした画面は、起動引数 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` を付けて撮影モードで起動すれば撮れる（Simulator の設定を変えずに済む）（2026-10-22）
- `TextField` を `@Observable` の Model のプロパティに直接つなぎ、Model の側で値を書き換えても（招待コードの正規化など）、iOS 26.5 の Simulator では入力欄の表示が変わらない。画面の `@State` を挟み、`onChange` で正規化した値を `@State` に入れ直すと表示も変わる（`JoinByCodeView`）（2026-10-22）
- 名前の無い `MKMapItem`（`MKMapItem(placemark:)` で作って `name = nil`）の `name` は nil ではなく「場所: 不明」を返す。名前が無い結果の扱いは `MKMapItem` からではなく、写した値（`PlaceSearchHit`）で確かめる（`SearchedPlaceTests`）（2026-10-22）

## backend（Firebase）

- Node 22 で使える版: `@firebase/rules-unit-testing` 6 は Node 24.12 以上が要るので 5 系（peer の `firebase` は 12 系）を使う。TypeScript は 6.0 系に留める（`typescript-eslint` は 6.1 未満、`ts-jest` は 7 未満まで）（2026-10-22）
- firebase-tools 15 の `emulators:exec` は、Functions があると eventarc（9299）・tasks（9499）・extensions の Emulator も自動で起動する。ずらさないと 2 つのスロットでぶつかるので、`firebase.json` にポートを書いてある（2026-10-22）
- Firebase の既定のポートのまま 100 ずらすと、hub（4400 → 4500）が、ずらし 0 の logging の既定（4500）とぶつかって `EADDRINUSE` で起動に失敗する。logging は 4600 にしてある（2026-10-22）
- `emulators:exec` に `"npx --no jest --config <設定>"` を渡すと jest に `--config` が届かず、テストが見つからずに失敗した。`./node_modules/.bin/jest` を直接呼ぶ（2026-10-22）
- 2 つのスロットで同時に Emulator を起動すると「running multiple instances of the emulator suite for project demo-dokogacha」と警告が出る（hub の locator が TMPDIR の `hub-<プロジェクト>.json` で共有されるため）。テストは環境変数で接続先を読むので実害はない（2026-10-22）
- Jest（CommonJS）で `firebase-functions/v2/https`（`HttpsError`・`onCall`）を読み込むと、firebase-admin の auth が ESM だけの `jose` を require して「Must use import to load ES Module」で落ちる（Jest は Node 22 では ESM を require できない）。`jest.shared.cjs` で `jose` だけを ts-jest で CommonJS に変換している（2026-10-22）
- firebase（JS）12 の `httpsCallable` が失敗したときの `message` は、サーバーの文言の後ろに HTTP のステータス（` [404]` など）が付く。文言は `details.reason`（`functions/src/errors.ts`）で選び、テストで `message` を完全一致で比べない（2026-10-22）
- Firebase Hosting の既定の `ignore` にある `**/.*` は `.well-known/` も配信から外す（apple-app-site-association が 404 になる）。`firebase.json` では `**/.DS_Store` に替えてある（2026-10-22）
- Emulator には FCM が無い。通知は `isEmulatorEnvironment`（`FUNCTIONS_EMULATOR` か `FIRESTORE_EMULATOR_HOST`）のとき FCM に送らず `emulatorPushOutbox` に書くので、Emulator のテストはそこを読んで宛先と文面を確かめる。トークンが `emulator-unregistered-` で始まると「登録されていない」で失敗させ、`fcmTokens` から外すのを確かめられる（`notifications/sender.ts`）（2026-10-22）
- Emulator のテストのファイルどうしは同じ Firestore を使うので、片方の `clearFirestore` がもう片方のデータを消す。`jest.emulator.config.js` は `maxWorkers: 1` で 1 ファイルずつ流す（2026-10-22）
- Mac が混んでいると（load average 50 前後）、Functions の Emulator がコードを読み込んで関数の一覧を作るのが既定の上限 10 秒を超え、「Cannot determine backend specification. Timeout after 10000」でトリガーも Callable も動かないままテストが待ちで落ちる。環境変数 `FUNCTIONS_DISCOVERY_TIMEOUT`（単位は秒）で延ばせる（`scripts/test-emulator.sh` で 60 にしてある）（2026-10-22）
- Firestore のトリガー（`onMemberWrite`）がトランザクションでルームとメンバーを読んでいる間に Emulator のデータを消す（`DELETE …/documents`・`clearFirestore`）と、409「Transaction lock timeout」（ABORTED）で失敗する。前のテストの書き込みでトリガーが遅れて動くので、消すのを間隔を空けてやり直す（`test/emulator/firestore-admin.ts` の `retryWhileLocked`）（2026-10-22）
- Emulator のテストで、前のテストの書き込みで遅れて動いたトリガー（`onRoomClosed` の過去のアイデアの登録など）が、次のテストの `clearFirestore` の後に書くことがある。トリガーが書くドキュメントを確かめるときは、ほかのテストのデータを数えないようにテストのルームの ID などで絞って読む（`test/emulator/close.test.ts` の `pastIdeas`）（2026-10-22）
