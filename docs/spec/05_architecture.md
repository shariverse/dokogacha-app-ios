# 05 技術構成

## 1. 技術スタック

| 領域 | 採用 | 備考 |
|---|---|---|
| クライアント | Swift 6（言語モード 6 / Strict Concurrency）/ SwiftUI / iOS 17+ | 状態管理は `@Observable`。並行処理は async/await。テストは Swift Testing（Unit）と XCTest（UI） |
| 地図・場所検索 | MapKit（`MKLocalSearch`、`Map`、`MKMapItem.openInMaps`） | 位置情報の許可は取らない |
| 演出 | SwiftUI のアニメーション＋`PhaseAnimator`/`KeyframeAnimator`、Core Haptics（`sensoryFeedback`） | 物理演算が必要になったら SpriteKit を検討（MVP では不要） |
| バックエンド | Firebase（Auth / Cloud Firestore / Cloud Functions 2nd gen（TypeScript）/ Cloud Messaging / Hosting / Analytics / Crashlytics） | Swift Package Manager で `firebase-ios-sdk` を導入 |
| 広告 | Google Mobile Ads SDK（AdMob）アダプティブバナー | ATT 対応 |
| 課金 | StoreKit 2（非消耗型 `remove_ads`） | サーバー検証は App Store Server Library（Node） |
| Web | Firebase Hosting | 招待リンクのランディングページ、`apple-app-site-association`、利用規約、プライバシーポリシー |

Bundle ID は `jp.shilokuma.Dokogacha`（`Configs/Project.xcconfig` の `APP_BUNDLE_IDENTIFIER` に設定済み）。Firebase の iOS アプリ登録、App Store Connect、AdMob、Associated Domains（`apple-app-site-association` の `appID` は `<TeamID>.jp.shilokuma.Dokogacha`）でこの ID を使う。

環境は **dev** と **prod** の2つの Firebase プロジェクトに分け、Xcode のビルド構成（Debug / Release）で `GoogleService-Info.plist` を切り替える。

---

## 2. クライアントの構成

リポジトリのテンプレートに合わせ、アプリ本体は `Dokogacha/`（フォルダ同期グループなので、ファイルを足しても pbxproj は変わらない）、Unit テストは `DokogachaTests/`、UI テストは `DokogachaUITests/` に置く。Firebase の Cloud Functions・ルール・Hosting はリポジトリ直下の `backend/`（`firebase.json`、`firestore.rules`、`functions/`、`hosting/`）に置く。

```
Dokogacha/
├─ App/                     DokoGachaApp.swift、AppDelegate（FCM・通知）、DeepLinkRouter
├─ DesignSystem/
│  ├─ Tokens/               Color+DG.swift、Font+DG.swift、Metrics.swift（tokens.json の値）
│  └─ Components/           PrimaryButton.swift、CandidateCard.swift、ProbabilityMeter.swift、
│                           DestinationBoard.swift、DestinationTicket.swift、GachaMachine.swift … （1部品1ファイル）
├─ Features/
│  ├─ Onboarding/
│  ├─ Home/
│  ├─ RoomCreate/
│  ├─ Invite/               招待・コード参加・参加確認
│  ├─ Room/                 ルーム、メンバー一覧、ルーム設定、候補の詳細
│  ├─ AddCandidate/         場所検索、過去のアイデア、投稿の確認
│  ├─ Gacha/                ガチャ、結果、引き直し
│  └─ Settings/
├─ Domain/
│  ├─ Models/               Room、Member、Candidate、Draw、PastIdea、UserProfile（Codable）
│  ├─ Logic/                Probability.swift（F-21〜23）、UnlockRule.swift（F-31）、RelativeTime.swift
│  └─ Category.swift        MapKit カテゴリ → アプリのカテゴリ
├─ Data/
│  ├─ RoomRepository.swift  Firestore のリアルタイム購読（AsyncStream で公開）
│  ├─ FunctionsClient.swift Callable Functions の呼び出し
│  ├─ PlaceSearchService.swift
│  ├─ PurchaseService.swift StoreKit 2
│  └─ AdService.swift
└─ Resources/               Fonts（.ttf）、Assets（icons）、Localizable.xcstrings
```

- 画面ごとに `XxxView` と `XxxModel`（`@Observable`）を作る。Model は Repository をプロトコル経由で受け取り、プレビューとテストではモックに差し替える
- **出やすさ・解禁判定の計算は `Domain/Logic` の純粋関数** にし、単体テストする。表示用の確率はクライアントで計算し、抽選はサーバーで行う（同じ式を TypeScript でも実装する）

---

## 3. データモデル（Cloud Firestore）

### `users/{uid}`

| フィールド | 型 | 説明 |
|---|---|---|
| `displayName` | string | 1〜10文字 |
| `avatarColor` | string | `avatar` パレットのいずれか |
| `adFree` | bool | 広告非表示を購入済み（Functions のみが書き込む） |
| `fcmTokens` | array<string> | 通知トークン |
| `createdAt` | timestamp | |

### `users/{uid}/pastIdeas/{ideaId}`（ルーム終了時に Functions が作成）

| フィールド | 型 | 説明 |
|---|---|---|
| `sourceRoomId` / `sourceRoomName` | string | 元のルーム |
| `sourceClosedAt` | timestamp | 並び替え用 |
| `sourceWinnerName` | string | 「◯◯ ゆき」表示用 |
| `place` | map | 候補の `place` と同じ |
| `category` | string | |
| `prevLikeCount` | number | 前回のいいね数 |

### `rooms/{roomId}`

| フィールド | 型 | 説明 |
|---|---|---|
| `name` | string | 1〜20文字 |
| `ownerId` | string | 作成者 |
| `inviteCode` | string | 6文字（ハイフンなしで保存） |
| `status` | string | `open` / `unlocked` / `drawn` / `closed` |
| `settings.postLimit` | number | 1〜10 |
| `settings.unlockRule` | string | `all` / `majority` / `deadline` |
| `settings.deadlineAt` | timestamp? | `deadline` のとき |
| `settings.likeMode` | string | `boost` / `equal` |
| `forcedUnlock` | bool | 強制解禁済み |
| `memberIds` | array<string> | クエリ用（最大20） |
| `memberCount` / `readyCount` | number | Functions が更新 |
| `candidateCount` | number | Functions が更新 |
| `adFreeSponsor` | map? | `{ uid, displayName }` 購入者がいれば最初に参加した人 |
| `currentDrawId` | string? | 最新の抽選 |
| `winnerCandidateId` | string? | |
| `excludedCandidateIds` | array<string> | 引き直しで外れた候補 |
| `reroll` | map | `{ used: bool, proposedBy, proposedAt, votesFor: [uid], votesAgainst: [uid], status: none/voting/passed/rejected }` |
| `createdAt` / `drawnAt` / `closedAt` | timestamp | |

### `rooms/{roomId}/members/{uid}`

| フィールド | 型 | 説明 |
|---|---|---|
| `displayName` / `avatarColor` | string | 参加時点のコピー（プロフィール変更時に Functions が更新） |
| `role` | string | `owner` / `member` |
| `ready` | bool | 準備OK |
| `joinedAt` / `lastSeenAt` | timestamp | NEW 判定に `lastSeenAt` を使う |

### `rooms/{roomId}/candidates/{candidateId}`

| フィールド | 型 | 説明 |
|---|---|---|
| `place.name` | string | 場所名 |
| `place.area` | string | 「東京・豊島区」形式 |
| `place.latitude` / `place.longitude` | number | |
| `place.mapItemId` | string? | `MKMapItem.identifier`（iOS 18 以降で取得できる場合） |
| `category` | string | 9種のいずれか |
| `note` | string | 0〜40文字 |
| `url` | string? | 参考URL |
| `postedBy` / `postedByName` | string | |
| `colorIndex` | number | 投稿順の通し番号（カプセルの色に使う） |
| `likedBy` | array<string> | いいねしたメンバーの uid |
| `fromPastIdeaId` | string? | 持ち込み元 |
| `createdAt` | timestamp | 並び替え用 |

### `rooms/{roomId}/draws/{drawId}`

| フィールド | 型 | 説明 |
|---|---|---|
| `candidateId` | string | 当選 |
| `probability` | number | 当選時の確率（0〜1） |
| `weights` | map<candidateId, number> | 抽選時の重みのスナップショット |
| `drawnBy` / `drawnByName` | string | 回した人 |
| `isReroll` | bool | |
| `createdAt` | timestamp | |

### `inviteCodes/{code}`

`{ roomId, createdAt }`。コード重複時は再生成。

### インデックス
- `rooms`：`memberIds` array-contains ＋ `status` ＋ `createdAt desc`
- `users/{uid}/pastIdeas`：`sourceClosedAt desc`

---

## 4. 書き込みの方針とセキュリティルール

整合性が必要な操作は **Callable Functions** を通し、クライアントからの直接書き込みは「自分の準備OK」「いいね」「lastSeenAt」だけに限る。

| 操作 | 方式 |
|---|---|
| ルーム作成・参加・退出・メンバー削除 | Callable：`createRoom` `joinRoom` `leaveRoom` `removeMember` |
| ルーム設定の変更・終了 | Callable：`updateRoomSettings` `closeRoom` |
| 候補の追加・削除 | Callable：`addCandidate`（上限・重複・状態をチェック）`deleteCandidate` |
| いいね | 直接：`likedBy` に自分の uid を `arrayUnion` / `arrayRemove` |
| 準備OK・lastSeenAt | 直接：自分の member ドキュメント |
| 強制解禁・抽選・引き直し | Callable：`forceUnlock` `drawGacha` `proposeReroll` `voteReroll` |
| 広告非表示の購入反映 | Callable：`verifyPurchase` |

ルールの骨子（`firestore.rules`）：

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function isMember(roomId) {
      return signedIn() && request.auth.uid in get(/databases/$(db)/documents/rooms/$(roomId)).data.memberIds;
    }
    function roomStatus(roomId) { return get(/databases/$(db)/documents/rooms/$(roomId)).data.status; }

    match /users/{uid} {
      allow read: if signedIn() && request.auth.uid == uid;
      allow update: if request.auth.uid == uid
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['displayName', 'fcmTokens']);
      match /pastIdeas/{id} { allow read: if request.auth.uid == uid; }
    }

    match /rooms/{roomId} {
      allow read: if isMember(roomId);

      match /members/{uid} {
        allow read: if isMember(roomId);
        allow update: if request.auth.uid == uid
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['ready', 'lastSeenAt'])
          && (!('ready' in request.resource.data.diff(resource.data).affectedKeys())
              || roomStatus(roomId) in ['open', 'unlocked']);
      }

      match /candidates/{cid} {
        allow read: if isMember(roomId);
        // いいね：自分の uid の追加・削除だけ。自分の投稿は不可
        allow update: if isMember(roomId)
          && roomStatus(roomId) in ['open', 'unlocked']
          && resource.data.postedBy != request.auth.uid
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likedBy'])
          && request.resource.data.likedBy.toSet().difference(resource.data.likedBy.toSet())
               .union(resource.data.likedBy.toSet().difference(request.resource.data.likedBy.toSet()))
               == [request.auth.uid].toSet();
      }

      match /draws/{drawId} { allow read: if isMember(roomId); }
    }
    // inviteCodes は Functions 経由でのみ参照
  }
}
```

---

## 5. Cloud Functions

| 関数 | 種類 | 処理 |
|---|---|---|
| `createRoom` | callable | 入力検証、招待コード発行、ルームと作成者の member を作成 |
| `joinRoom` | callable | コード→ルーム、状態と人数（<20）を確認、member 追加、`memberIds`/`memberCount` 更新、広告スポンサーの再計算、解禁の再判定 |
| `leaveRoom` / `removeMember` | callable | member 削除、その人のいいねを全候補から除去、カウント更新、解禁の再判定 |
| `updateRoomSettings` | callable | 作成者のみ。F-03 の変更ルールを検証 |
| `addCandidate` | callable | 状態・上限・重複（F-10）を検証して作成、`colorIndex` 採番。重複時は `{ duplicateOf: candidateId }` を返す |
| `deleteCandidate` | callable | 投稿者または作成者のみ |
| `onMemberWrite` | Firestore トリガー | `readyCount` を更新し、解禁条件（F-31）を判定して `status` を `open`⇄`unlocked` に更新。`unlocked` になったら通知 |
| `forceUnlock` | callable | 作成者のみ。`forcedUnlock = true`, `status = unlocked`、通知 |
| `checkDeadlines` | スケジュール（5分ごと） | 締切を過ぎた `open` ルームを `unlocked` に |
| `drawGacha` | callable | 下記 |
| `proposeReroll` / `voteReroll` | callable | F-43。可決で除外リストに追加し `unlocked` に戻す |
| `expireRerolls` | スケジュール（1時間ごと） | 24時間を過ぎた投票を否決 |
| `closeRoom` | callable | 作成者のみ。`closed` にし、各メンバーの `pastIdeas` を作成 |
| `autoCloseRooms` | スケジュール（1日1回） | 抽選から7日経過した `drawn` を `closed` に（`closeRoom` と同じ処理） |
| `inviteLastMembers` | callable | 前回ルームのメンバーに招待通知 |
| `notifyNewCandidates` | スケジュール（1日1回、20:00 JST） | 新しい候補のまとめ通知 |
| `verifyPurchase` | callable | StoreKit 2 の署名付きトランザクション（JWS）を App Store Server Library で検証し、`users.adFree = true`。参加中ルームの `adFreeSponsor` を更新 |
| `onUserProfileUpdate` | Firestore トリガー | 参加中ルームの member の表示名を更新 |
| `deleteAccount` | callable | F-06。参加中ルームからの退出、作成者のルームの終了、ユーザーデータと Auth ユーザーの削除 |
| `reportCandidate` | callable | F-14。`reports/{id}`（`roomId` `candidateId` `reporterId` `reason` `createdAt`）を作成し、運営にメール通知 |

### `drawGacha` の擬似コード

```ts
export const drawGacha = onCall(async (req) => {
  const uid = requireAuth(req);
  const { roomId } = req.data;
  return db.runTransaction(async (tx) => {
    const room = await tx.get(roomRef(roomId));
    assertMember(room, uid);
    if (room.status === 'drawn') return { drawId: room.currentDrawId }; // 先に誰かが回した
    if (room.status !== 'unlocked') throw new HttpsError('failed-precondition', 'not-unlocked');

    const cands = (await tx.get(candidatesRef(roomId)))
      .docs.filter((d) => !room.excludedCandidateIds.includes(d.id));
    if (cands.length === 0) throw new HttpsError('failed-precondition', 'no-candidates');

    const weights = Object.fromEntries(cands.map((d) => [d.id, weightOf(d.likedBy.length, room.settings.likeMode)]));
    const winnerId = pickWeighted(weights, crypto.randomInt); // 暗号論的乱数
    const total = sum(Object.values(weights));
    const drawRef = drawsRef(roomId).doc();
    tx.set(drawRef, { candidateId: winnerId, probability: weights[winnerId] / total, weights,
                      drawnBy: uid, isReroll: room.excludedCandidateIds.length > 0, createdAt: now() });
    tx.update(roomRef(roomId), { status: 'drawn', currentDrawId: drawRef.id, winnerCandidateId: winnerId, drawnAt: now() });
    return { drawId: drawRef.id };
  });
});

const weightOf = (likes: number, mode: 'boost' | 'equal') => (mode === 'equal' ? 1 : 1 + Math.sqrt(likes));
```

抽選後、`onRoomDrawn`（トリガー）で回した人以外に結果を通知する。

---

## 6. リアルタイム同期

- ルーム画面を開いている間、`rooms/{id}`、`members`、`candidates` を購読する（`addSnapshotListener` を `AsyncStream` に変換）
- ガチャ画面では `rooms/{id}.status` と `currentDrawId` を購読し、他の人が回したら演出を自動再生する（F-41）
- 自分の操作（いいね・準備OK）は楽観的更新で即時に表示し、失敗したら元に戻してトースト「通信できませんでした」
- ホームでは `rooms` を `memberIds array-contains uid` で購読

## 7. ディープリンク

- ドメイン（仮決め）：`dokogacha.app`。Firebase Hosting で配信
- `https://dokogacha.app/.well-known/apple-app-site-association` に `/r/*` を登録し、Associated Domains（`applinks:dokogacha.app`）を設定
- `/r/{code}`：アプリがあれば S-06 参加確認へ。なければランディングページ（アプリの紹介、App Store ボタン、招待コードを大きく表示）
- OGP：タイトル「{ルーム名} に招待されました｜ドコガチャ」、画像はアプリの汎用 OGP 画像（ルーム名は Hosting の Functions 経由で動的に差し込む。仮決め：MVP は固定の OGP 画像＋固定タイトル「ドコガチャに招待されました」）
- 通知のペイロードに `roomId` と遷移先（`room` / `result`）を入れる

## 8. 課金と広告

- `PurchaseService`：起動時に `Transaction.currentEntitlements` を確認し、`remove_ads` があれば `verifyPurchase` を呼ぶ（初回のみ）。`Transaction.updates` を購読
- 広告を出すかの判定：

```swift
func shouldShowAds(screen: Screen, me: UserProfile, room: Room?) -> Bool {
    guard screen.allowsAds else { return false }   // home / room / addCandidate のみ true
    if me.adFree { return false }
    if let room, room.adFreeSponsor != nil { return false }
    return true
}
```

- 広告ユニットID は dev ではテスト用ID を使う
- 日本国内向けのため UMP（GDPR 同意）は MVP では組み込まない（仮決め。EEA 配信時に追加）

## 9. 計測（Firebase Analytics）

| イベント | パラメータ |
|---|---|
| `room_create` | `post_limit`, `unlock_rule`, `like_mode` |
| `room_join` | `via`（link / code / push） |
| `candidate_add` | `source`（search / past）, `category` |
| `like_toggle` | `on` |
| `ready_toggle` | `on` |
| `room_unlock` | `rule`, `forced` |
| `gacha_draw` | `candidate_count`, `is_reroll`, `rare` |
| `ticket_share` | |
| `reroll_propose` / `reroll_result` | `passed` |
| `room_close` | `auto` |
| `purchase_remove_ads` | |
