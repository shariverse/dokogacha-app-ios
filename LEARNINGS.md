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
- Google Mobile Ads 13 には `currentOrientationAnchoredAdaptiveBanner` が無く、アンカー型アダプティブバナーの大きさは `largeAnchoredAdaptiveBanner(width:)`（高さ 50〜150。iPhone 17 Pro の幅 370 で約 115）で取る。`BannerView` を `UIViewRepresentable` で置くと、SwiftUI は広告の素材の intrinsicContentSize で並べるので、枠からはみ出して下のボタンに重なる。`sizeThatFits(_:uiView:context:)` で提案された大きさを返し、`.clipped()` する（`GoogleBannerAdView`）（2026-10-22）
- Simulator でも Google のテスト用の広告ユニット ID なら、テスト広告（「Test mode」）が読み込まれる。撮影モードは本物の広告を写さない（既定は広告の場所を取らない。App Store の撮影用。PR の撮影で場所を見せるときは起動引数 `-screenshot-ad-placeholder` を足すと固定の枠 `DGAdPlaceholder` が出る（2026-10-23））ので、本物の見た目を確かめるときは `AdMode.make` の撮影モードの分岐を一時的に外してビルドする（コミットしない）（2026-10-22）
- Crashlytics・Analytics の収集の設定は、コードで渡した値（`setCrashlyticsCollectionEnabled`・`setAnalyticsCollectionEnabled`）が端末に残り、Info.plist の `FirebaseCrashlyticsCollectionEnabled`・`FIREBASE_ANALYTICS_COLLECTION_ENABLED` より優先される（plist は初回の既定だけ）。同じ端末に Stg と Debug を入れ替えても取り違えないよう、起動ごとに渡し直している（`FirebaseTelemetry`）。xcconfig の変数で入れた plist の値は文字列の `YES`・`NO` になり、Crashlytics は文字列も `boolValue` で読む（2026-10-22）
- Crashlytics の `upload-symbols`（universal binary）と `run` は、SPM が取ってきた `SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/` にある。CI の Archive は `-derivedDataPath "$RUNNER_TEMP/DerivedData"` を付け、そこの `SourcePackages/checkouts/…` から取って（2026-10-23。既定の `~/Library/Developer/Xcode/DerivedData` を `find` すると、ランナーに残った別のものを拾いうる）、Archive の後に `--google-service-plist <plist> --platform ios <xcarchive>/dSYMs` で上げている（`_archive.yml`。Run Script のビルドフェーズは pbxproj を変えるので使わない）（2026-10-22）
- Sign in with Apple は、SwiftUI の `@Environment(\.authorizationController)`（iOS 16.4 から。`AuthorizationController.performRequest` の async）で要求すると、`ASAuthorizationControllerDelegate`・`PresentationContextProviding` を自分で持たずに済み、Swift 6 の既定の分離（MainActor）のまま書ける（`SystemAppleAuthorizer`）。やめたときは `ASAuthorizationError.canceled` が投げられる（2026-10-22）
- Firebase Auth で匿名のユーザーに Apple を `link(with:)` して、その Apple ID が既に別のユーザーに使われていると `credentialAlreadyInUse`（17025）になる。Apple の ID トークンは 1 回しか使えないので、サインインし直すときはエラーの `userInfo[AuthErrors.userInfoUpdatedCredentialKey]` の資格情報を使う（`FirebaseAuthService.pendingAppleCredential`）（2026-10-22）
- Sign in with Apple に連携したアカウントを削除するときは、Apple の認証をし直して `authorizationCode` を受け取り、サーバーで消す**前に** `Auth.auth().revokeToken(withAuthorizationCode:)` を呼ぶ（審査 5.1.1(v)。消した後は ID トークンが取れない）。SDK 13 の `revokeToken` は `currentUser` が nil だと完了を呼ばない（`_currentUser?.` で何もしない）ので、先に確かめる。サーバーで消された Auth のユーザーは `currentUser.reload()` が `userNotFound`（17011）で失敗するので、削除の応答が届かなかったときの確かめに使える（2026-10-23）
- SPM の checkouts（`SourcePackages/checkouts/…`）のファイルは読み取り専用（`r--r--r--`）なので、ライセンスの全文などを `cp` で `Dokogacha/` に持ってくると、そのままでは書き換えられない（`chmod 644` してから直す）（2026-10-22）
- `xcode-select` が Xcode 27 を指す Mac では、develop は `DGDashedLine.swift` の `Shape` への準拠が `#ConformanceIsolation` のエラーになってビルドできない（前提は Xcode 26.6）。`DEVELOPER_DIR` に Xcode 26.6 の `Contents/Developer` を渡す。
  Xcode 27 の `simctl` で Simulator を起動した後、Xcode 26.6 の `xcodebuild` から Simulator が 1 台も見えなくなった（`-destination id=…` が `Unable to find a device`。`simctl list` には出る）。
  ビルドは `-destination 'generic/platform=iOS Simulator'`（x86_64 も作るので初回は遅い）で行い、できた `Build/Products/*.xctestrun` を Xcode 27 の `xcodebuild test-without-building -xctestrun … -destination id=…` で流すと Unit・UI テストとも通った（2026-11-01）
- `Localizable.xcstrings` に文字列を足すのは Xcode の画面のビルドだけで、`xcodebuild` は足さない。コマンドで足すときは、`xcodebuild build` の後に `xcrun xcstringstool sync Dokogacha/Resources/Localizable.xcstrings --stringsdata "$DD"/Build/Intermediates.noindex/Dokogacha.build/Debug-iphonesimulator/Dokogacha.build/Objects-normal/arm64/*.stringsdata` を流す（`--stringsdata` は 1 回だけ書いて後ろにファイルを並べる）。カタログに無い文字列もキーの日本語がそのまま出るので、足し忘れても表示は変わらない（2026-10-23）
- Xcode 27.1 では `DGDashedLine` の `DashedLineShape`（`Shape` への準拠）が「crosses into main actor-isolated code」（#ConformanceIsolation）のエラーになり、ビルドできない。既定の Xcode（`xcode-select -p`）が 27 の Mac では、`xcode-select` を変えずに `DEVELOPER_DIR` に Xcode 26.6 の `Contents/Developer` を渡して `xcodebuild` を流す（2026-10-31）

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
- UI テストで削除キー（`XCUIKeyboardKey.delete`）を `typeText` でまとめて打つと、Mac が混んでいる（load average 150 以上）とき、入力のたびに画面が値を直す入力欄（招待コードの `JoinByCodeView`）でキーが抜けて文字が残った（「ZQW-58R」など）。1 文字ずつ打って値が変わるのを待つ（`DokogachaUITests/UITestHelpers.swift` の `clearText`・`typeTextByCharacter`）。ほかのメンバーの参加・準備OK・引き直しの賛成が要る通しの UI テストは、起動引数 `-ui-auto-members` で擬似のサーバーに返させる（`InMemoryAutoMembers`）（2026-10-22）
- `xcodebuild test` に `-only-testing:DokogachaTests` と `-only-testing:DokogachaUITests/<クラス>/<メソッド>` を一緒に渡すと、Unit は流れたのに UI テストは「Executed 0 tests」で終わった（終了コードは 0）。UI テストを 1 件だけ流すときは別の `xcodebuild` で渡し、`Executed 1 test` を確かめる（2026-10-23）
- Simulator の回線は UI テストから切れないので、オフラインの表示は起動引数 `-network-offline`（`-uiTesting`・撮影モードのときだけ効く）で確かめる。`NWPathMonitor` を使わず固定の状態を流すので、オンラインに戻る流れは Unit テスト（`NetworkOfflineTests`・`LaunchRouteOfflineTests`）で確かめる（2026-10-23）
- シートの中の `NavigationStack`（S-05・S-06）は別の `UINavigationController` なので、端からのスワイプで戻るにはシートの中の根元にも `InteractivePopGesture` を付ける。送っている途中に止める印（`NavigationLock`）もスタックごとに持つ（2026-10-23）
- 根元のビューに `.safeAreaInset(edge: .top)` でバナーを付けても、`NavigationStack` に積んだ画面（ヘッダーを自前で置く S-07 など）は上を空けず、ヘッダーがバナーの下に隠れた（iOS 26.5 の Simulator）。画面の上に帯を出すときは `VStack` で縦に並べる（`OfflineBannerModifier`）（2026-10-23）
- 撮影モードで画面を続けて撮るとき、Mac が混んでいる（load average 400 以上）と起動に 10 秒以上かかり、起動画面だけが写る（どの scene でも同じ大きさの PNG になる）。撮ったファイルの大きさがそろっていたら、待ち時間を延ばして撮り直す（2026-10-23）
- VoiceOver で読ませたくない「押せない状態」を、無効の `DGButton` で描くと「淡色表示、ボタン」と読まれる。ボタンの形の状態の表示は `DGButtonShapedStatus`（`Button` ではない）を使う。UI テストでは `app.staticTexts[...]` で探す（2026-10-23）

## 場所検索（MapKit）

- `MKPlacemark.locality` は、同じ市区町村でも形がそろわない（Mac の MapKit で確かめた形）。政令指定都市は「中区, 横浜市」「横浜市」（区は `subLocality`）「札幌市中央区」、郡の町村は「足柄下郡箱根町」「箱根町」「足柄下郡」（町は `subLocality`）。
  英語の端末では同じ検索の結果に「Kanagawa」「Hakone, Ashigarashimo-Gun」のような英語の値が混ざる（全部ではない）。市区町村で絞るときは `PlaceLocality` で吸収し、日本語でなければ座標で決める（2026-10-31）
- `MKLocalSearch` の住所の検索（`resultTypes = .address`、語は「東京都豊島区」）の `response.boundingRegion` は、市区町村のおおよその広さになる（豊島区で 0.03×0.08 度、浜松市で 0.66×0.57 度）。都道府県の語では本土の外まで広がる（鹿児島県は奄美群島の南の北緯 26.9 度から、島根県は北緯 37.3 度まで、東京都は東経 140.4 度まで）ので、都道府県の範囲には使わず `Prefecture.all` に本土を囲む矩形を持っている（2026-10-31）
- Mac のコマンドラインの Swift で `MKLocalSearch` を試すとき、`DispatchSemaphore` でメインスレッドを待たせると結果が返らず止まる。`Task { @MainActor in … ; exit(0) }` の後に `RunLoop.main.run()` で回す（2026-10-31）

## backend（Firebase）

- Node 22 で使える版: `@firebase/rules-unit-testing` 6 は Node 24.12 以上が要るので 5 系（peer の `firebase` は 12 系）を使う。TypeScript は 6.0 系に留める（`typescript-eslint` は 6.1 未満、`ts-jest` は 7 未満まで）（2026-10-22）
- firebase-tools 15 の `emulators:exec` は、Functions があると eventarc（9299）・tasks（9499）・extensions の Emulator も自動で起動する。ずらさないと 2 つのスロットでぶつかるので、`firebase.json` にポートを書いてある（2026-10-22）
- Firebase の既定のポートのまま 100 ずらすと、hub（4400 → 4500）が、ずらし 0 の logging の既定（4500）とぶつかって `EADDRINUSE` で起動に失敗する。logging は 4600 にしてある（2026-10-22）
- `emulators:exec` に `"npx --no jest --config <設定>"` を渡すと jest に `--config` が届かず、テストが見つからずに失敗した。`./node_modules/.bin/jest` を直接呼ぶ（2026-10-22）
- 2 つのスロットで同時に Emulator を起動すると「running multiple instances of the emulator suite for project demo-dokogacha」と警告が出る（hub の locator が TMPDIR の `hub-<プロジェクト>.json` で共有されるため）。テストは環境変数で接続先を読むので実害はない（2026-10-22）
- Jest（CommonJS）で `firebase-functions/v2/https`（`HttpsError`・`onCall`）を読み込むと、firebase-admin の auth が ESM だけの `jose` を require して「Must use import to load ES Module」で落ちる（Jest は Node 22 では ESM を require できない）。`jest.shared.cjs` で `jose` だけを ts-jest で CommonJS に変換している（2026-10-22）
- firebase（JS）12 の `httpsCallable` が失敗したときの `message` は、サーバーの文言の後ろに HTTP のステータス（` [404]` など）が付く。文言は `details.reason`（`functions/src/errors.ts`）で選び、テストで `message` を完全一致で比べない（2026-10-22）
- Firebase Hosting の既定の `ignore` にある `**/.*` は `.well-known/` も配信から外す（apple-app-site-association が 404 になる）。`firebase.json` では `**/.DS_Store` に替えてある（2026-10-22）
- Firebase Hosting の Emulator では、`headers` の `"source": "**"` がドットで始まるディレクトリ（`/.well-known/…`）に当たらず、すべてのパスに付けたセキュリティのヘッダー（CSP など）は apple-app-site-association に付かなかった。本番の Hosting で同じかは確かめていないので、テストは CSP の有無ではなく AASA の要件（`application/json`・転送しない）だけを確かめる。付けたいときは `/.well-known/**` を別に書く（2026-10-22）
- headless の Chrome（`--headless=new`）で `--window-size=390,…` にすると、ページは広い幅で組まれて右が切れたスクリーンショットになった（520 なら切れない）。Hosting のページは幅 520 で撮る（2026-10-22）
- Emulator には FCM が無い。通知は `isEmulatorEnvironment`（`FUNCTIONS_EMULATOR` か `FIRESTORE_EMULATOR_HOST`）のとき FCM に送らず `emulatorPushOutbox` に書くので、Emulator のテストはそこを読んで宛先と文面を確かめる。トークンが `emulator-unregistered-` で始まると「登録されていない」で失敗させ、`fcmTokens` から外すのを確かめられる（`notifications/sender.ts`）（2026-10-22）
- Emulator のテストのファイルどうしは同じ Firestore を使うので、片方の `clearFirestore` がもう片方のデータを消す。`jest.emulator.config.js` は `maxWorkers: 1` で 1 ファイルずつ流す（2026-10-22）
- Mac が混んでいると（load average 50 前後）、Functions の Emulator がコードを読み込んで関数の一覧を作るのが既定の上限 10 秒を超え、「Cannot determine backend specification. Timeout after 10000」でトリガーも Callable も動かないままテストが待ちで落ちる。環境変数 `FUNCTIONS_DISCOVERY_TIMEOUT`（単位は秒）で延ばせる（`scripts/test-emulator.sh` で 60 にしてある）（2026-10-22）
- Firestore のトリガー（`onMemberWrite`）がトランザクションでルームとメンバーを読んでいる間に Emulator のデータを消す（`DELETE …/documents`・`clearFirestore`）と、409「Transaction lock timeout」（ABORTED）で失敗する。前のテストの書き込みでトリガーが遅れて動くので、消すのを間隔を空けてやり直す（`test/emulator/firestore-admin.ts` の `retryWhileLocked`）（2026-10-22）
- Emulator のテストで、前のテストの書き込みで遅れて動いたトリガー（`onRoomClosed` の過去のアイデアの登録など）が、次のテストの `clearFirestore` の後に書くことがある。トリガーが書くドキュメントを確かめるときは、ほかのテストのデータを数えないようにテストのルームの ID などで絞って読む（`test/emulator/close.test.ts` の `pastIdeas`）（2026-10-22）
- `defineString` などの Functions のパラメータに値が無いと、Functions の Emulator は起動時に対話で値を聞く（firebase-tools 15 の `resolveParams` は Emulator では `nonInteractive: false`）。`emulators:exec` では答えられないので、Emulator のプロジェクトだけで読む `functions/.env.demo-dokogacha` に目印の値を置いてある（実プロジェクトの `.env.<プロジェクト ID>` は `.gitignore`）（2026-10-22）
- `firebase.json` に `extensions` があると、`emulators:exec` が Extensions の Emulator で拡張のコードを取りに行き、必須のパラメータ（Trigger Email 拡張の `DEFAULT_FROM` など）も要る。Emulator の設定を書き出すときに `extensions` を外している（`scripts/emulator-config.cjs` の `withoutExtensions`）。拡張のパラメータは `extensions/<インスタンス>.env` の後に `.env.<プロジェクト ID>` が上書きで読まれるので、プロジェクトごと・秘密に近い値（SMTP の接続先・送り主）は後者に書く（2026-10-22）
- `firestore.indexes.json` の `fieldOverrides` で 1 つのフィールドの索引を書くと、そのフィールドの既定の単一フィールドの索引（コレクションの昇順・降順）は置き換わって消える。コレクショングループのクエリ（`notifyNewCandidates` の `candidates.createdAt`）のために足すときは、`COLLECTION` の昇順・降順も並べて残す（アプリの候補の一覧が `createdAt` の降順で読む）。Emulator は索引を見ないので、テストでは気づけない（2026-10-22）
- `@apple/app-store-server-library` の `SignedDataVerifier` は、環境が Xcode・LocalTesting のときは署名を確かめずに中身を返す（Bundle ID と環境だけを見る）。Xcode の StoreKit のテスト（`.storekit`）の購入は環境が `Xcode` なので、Emulator だけで Xcode の検証を足して通している（本番で受け付けると誰でも作れる）。Production の検証は `appAppleId` が無いとコンストラクタが投げるので、アプリを登録するまでは Sandbox だけにしている（`purchase/logic.ts` の `verificationEnvironments`）（2026-10-22）
- App Store の署名の根の証明書（Apple Root CA - G3）は `purchase/appleRootCertificates.ts` に PEM で置いてある（公開の証明書）。差し替えるときは `security find-certificate -c "Apple Root CA - G3" -Z /System/Library/Keychains/SystemRootCertificates.keychain` の SHA-256 と突き合わせる（Jest でも指紋を確かめる）（2026-10-22）
- `users/{uid}` の更新で動く `onUserProfileUpdate` は、`fcmTokens` が 9 個を超えると古いものから外して 9 個にする（ルールの上限 10 で新しい端末のトークンが拒否されないように）。Emulator のテストで 10 個のトークンを書いてから読み戻して比べると、トリガーに書き換えられて揺らぐ。トークンを数で確かめるテストは、作成（`set`。更新のトリガーは動かない）で置くか、トリガーの後の値を待つ（`test/emulator/fcm-tokens.test.ts`）（2026-10-22）

## アプリアイコン・画像の書き出し

- SVG を NSImage で `CGImageAlphaInfo.noneSkipLast`（アルファなし）の描画先に直接描くと、塗られていない（透けた）ところが黒い面になり、エラーにならない。アルファ付きの描画先に描いてアルファがすべて 255 か確かめてから、アルファなしに描き直す（`Tools/render_svg.swift` の `--opaque`）（2026-10-29）
- Read ツールなどの画像の表示は、透過したところを白で見せる。ダーク・ティントの透過の PNG は、白い背景のように見えても `sips -g hasAlpha` が `yes` なら透過のまま（2026-10-29）
- アセットカタログのアイコンセットにダーク・ティントを入れるには、`Contents.json` の画像に `"appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ]`（ティントは `"tinted"`）を付ける。ビルドした `Assets.car` に Appearance ごと（`None`・`UIAppearanceDark`・`ISAppearanceTintable`）に入ったかは `xcrun assetutil --info` で確かめる（2026-10-29）
- Simulator のホーム画面のアイコンは、`simctl install` の後に `simctl launch <UDID> com.apple.springboard` でホームに戻してから `simctl io <UDID> screenshot` で撮れる（空きのある最初のページに並ぶ）。iOS 26.5 の Simulator では `simctl ui <UDID> appearance dark` で壁紙は暗くなるが、ホーム画面のアイコンはライトのまま（アイコンの外観はホーム画面の「カスタマイズ」の設定で、システムの外観に付いてこない）。ダーク・ティントは角丸のマスクをかけた合成画像で見せる（2026-10-29）

## ローカライズ・表示名

- ホーム画面の名前（`CFBundleDisplayName`）は `Dokogacha/InfoPlist.xcstrings` に言語ごとに書けば、pbxproj の `knownRegions` に言語を足さなくても `<言語>.lproj/InfoPlist.strings` がアプリに入り、Info.plist に鍵が無くても言語ごとの値が出る（Xcode 26.6・iOS 26.5 の Simulator）。開発言語が `ja` なので、`en` を足すと日本語・英語のどちらでもない端末（フランス語など）でも `en` が選ばれる（2026-10-30）
- `en` のローカライズがあると、英語の端末ではアプリの言語が英語になり、文言が日本語のキーのままでも見た目が少し変わる: `DatePicker` は「Nov 2, 2026 9:00 PM」（`ja` しか無いときは「11/2/26 午後9:00」と混ざる）、地図の表記は「Maps / Legal」、和文と数字の間の自動の空き（「4 分前」）が無くなる（2026-10-30）
- ホーム画面を UI テストで撮るとき、アプリを `launch()` しないテストだけを流すと、`xcodebuild test` はアプリを Simulator に入れない（アイコンが無い）。先に `xcrun simctl install` で入れる。アイコンは `XCUIApplication(bundleIdentifier: "com.apple.springboard").icons["<表示名>"]` で探せる。言語は `simctl spawn <UDID> defaults write -g AppleLanguages -array <言語>` の後に shutdown → boot し直すと効く（2026-10-30）
