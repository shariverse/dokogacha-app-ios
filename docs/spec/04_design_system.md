# 04 デザインシステム

テーマ：**カプセルトイの筐体 × 暖色ポップ × 旅のモチーフ**（行き先表示、きっぷ、スタンプ、ピン）。
同じ値は `design/tokens.json` にも入っています。SwiftUI では `Color` / `Font` の extension として実装してください（末尾の実装メモ参照）。

## デザインの原則

1. **太い墨色の線**：主要なカード・ボタンは `ink` の線（2〜2.5pt）で縁取る。薄いグレーの線で囲んだカードを並べない
2. **ハードシャドウ**：ぼかしのない影を真下に4pt ずらす（`0 4 0 ink`）。押せる・目立たせたい要素だけに使う
3. **見出しはポップに、本文は読みやすく**：見出し＝Mochiy Pop One、本文＝Zen Maru Gothic
4. **旅のモチーフで個性を出す**：行き先は黒帯の「行き先表示」、結果は「きっぷ」、決定は「ハンコ」
5. **グラデーションで面を塗らない**。カプセルの2色塗り分け（上半分が色、下半分が白）だけは例外
6. **絵文字は使わない**。アイコンは `design/icons` の線画アイコンを使う

---

## 1. 色

### 基本

| トークン | 値 | 用途 |
|---|---|---|
| `bg.base` | `#FFF7EE` | 画面の背景 |
| `surface.card` | `#FFFFFF` | カード・入力欄 |
| `surface.highlight` | `#FFF1C9` | 人気候補（みんな推し／全員いいね）のカード |
| `surface.subtle` | `#FFF7EE` | 吹き出し（ひとこと）の背景 |
| `surface.muted` | `#F1E4D6` | タブの下地、メーターの溝 |
| `surface.disabled` | `#E6D9CB` | 無効ボタンの背景 |
| `surface.ad` | `#FBF1E6` | 広告枠のプレースホルダ |
| `ink` | `#2B2118` | 文字、線、ハードシャドウ、黒帯 |
| `text.secondary` | `#6E5E50` | 補足文（`bg.base` 上で 4.9:1） |
| `text.disabled` | `#5E5045` | 無効ボタンの文字 |
| `text.onInk` | `#F3E3CF` | 黒帯の上の補足文 |
| `line.dashed` | `#E3D3C2` | カード内の点線区切り |
| `line.dashedStrong` | `#CDB9A4` | きっぷの切り取り線、広告枠 |

### アクセント

| トークン | 値 | 用途 |
|---|---|---|
| `accent.primary` | `#D93A1F` | 主ボタンの背景（白文字で 4.6:1）、筐体の本体色、きっぷの帯 |
| `accent.text` | `#B8321A` | 朱色の文字、NEW バッジ、スタンプ、いいね済みのハート |
| `accent.secondary` | `#FFC93C` | 黄色ボタン（準備OK、候補を追加）、レバー、黒帯上の強調文字 |
| `accent.pale` | `#FFF0C2` | 「前回惜しかった」バッジ、広告なしメッセージの背景 |
| `accent.paleText` | `#5C4600` | `accent.pale` 上の文字 |
| `like.bg` | `#F7EEE4` | いいねボタン（未いいね） |
| `like.bgActive` | `#FDE3DC` | いいねボタン（いいね済み） |
| `like.icon` | `#5E5045` | いいねボタンのハート（未いいね） |
| `like.iconMine` | `#9C8B7C` | 自分の投稿のハート（無効） |

### 状態チップ

| 状態 | 背景 | 文字 |
|---|---|---|
| 候補募集中（`open`） | `#E3F2EC` | `#1E5E49` |
| ガチャ解禁！（`unlocked`） | `#FFC93C` | `#2B2118` |
| 行き先決定（`drawn`） | `#2B2118` | `#FFC93C` |
| 終了（`closed`） | `#F1E4D6` | `#5E5045` |

### 出やすさのレベル（F-22）

| トークン | ラベル | チップ背景 | チップ文字 | メーター | %の文字色 |
|---|---|---|---|---|---|
| `level.high` | 出やすい | `#D93A1F` | `#FFFFFF` | `#D93A1F` | `#B8321A` |
| `level.mid` | ふつう | `#FFC93C` | `#2B2118` | `#FFC93C` | `#2B2118` |
| `level.low` | レア | `#DCEBFF` | `#1D5A99` | `#4DA3FF` | `#1D5A99` |
| `level.flat` | 平等 | `#F1E4D6` | `#2B2118` | `#CDB9A4` | `#2B2118` |

### カプセルの色（候補ごと）

候補の投稿順のインデックス `i` に対して `capsule[i % 6]` を割り当てる（並び順を変えても色は変わらない）。

`#FF7A59` `#FFC93C` `#3CC9A0` `#4DA3FF` `#FF8FC7` `#9B7BFF`

### アバターの色（白文字、すべて 4.5:1 以上）

`#B8321A` `#23775D` `#2F6FD0` `#A3367E` `#6B48C9` `#8A5A12` `#1F6E8C` `#5E5045`

未準備のアバター：背景 `#F1E7DC`、文字 `#5E5045`

### カテゴリタイル

| カテゴリ | 表示名 | 背景 | アイコン色 | アイコン |
|---|---|---|---|---|
| `aquarium` | 水族館 | `#D6ECFF` | `#1D5A99` | `cat-aquarium.svg` |
| `nature` | 自然 | `#DDF3E6` | `#1E6B47` | `cat-nature.svg` |
| `art` | アート・美術館 | `#F1E3FF` | `#6B3FA0` | `cat-art.svg` |
| `food` | グルメ | `#FFE4D6` | `#A23B12` | `cat-food.svg` |
| `activity` | アクティビティ | `#D9F4F1` | `#146B63` | `cat-activity.svg` |
| `park` | テーマパーク | `#FFE1EE` | `#A02A62` | `cat-park.svg` |
| `town` | 街歩き | `#FFF0C2` | `#7A5A00` | `cat-town.svg` |
| `shrine` | 寺社 | `#FFDCD6` | `#A12A1A` | `cat-shrine.svg` |
| `sea` | 海 | `#D6F0FF` | `#165E8C` | `cat-sea.svg` |

ダークモード：MVP では **ライトモード固定**（`UIUserInterfaceStyle = Light`）。

---

## 2. タイポグラフィ

### フォント

| 役割 | フォント | ウェイト | PostScript 名 |
|---|---|---|---|
| 見出し | Mochiy Pop One | Regular のみ | `MochiyPopOne-Regular` |
| 本文 | Zen Maru Gothic | Regular / Medium / Bold / Black | `ZenMaruGothic-Regular` `-Medium` `-Bold` `-Black` |

- どちらも Google Fonts で配布されている SIL Open Font License 1.1 のフォント。`.ttf` をアプリに同梱し、`Info.plist` の `UIAppFonts` に登録する。設定画面のライセンスに OFL の表記を入れる
- Mochiy Pop One には太字がないので、**見出しフォントに `.bold()` を付けない**（擬似ボールドで線がつぶれる）
- 本文の「bold」は Bold（700）、「heavy」は Black（900）を使う
- 数字（%、人数、カウント）も見出しフォントで表示する

### スケール

Dynamic Type に追従させる（`Font.custom(_:size:relativeTo:)`）。

| トークン | フォント | サイズ | relativeTo | 主な用途 |
|---|---|---|---|---|
| `display.xl` | 見出し | 32 | `.largeTitle` | ホームのロゴ |
| `display.ticket` | 見出し | 27 | `.title` | きっぷの「◯◯ ゆき」 |
| `display.l` | 見出し | 24 | `.title2` | ガチャのタイトル、出やすさ%、招待コード（36） |
| `display.m` | 見出し | 22 | `.title2` | 行き先表示「？？？」、結果のタイトル |
| `display.s` | 見出し | 20 | `.title3` | いいね人数、準備OK人数 |
| `display.header` | 見出し | 18 | `.headline` | 画面ヘッダーのタイトル |
| `display.section` | 見出し | 16〜17 | `.headline` | セクション見出し |
| `display.tag` | 見出し | 11〜12 | `.caption` | NEW バッジ、リボン |
| `body.title` | 本文 Black | 16〜18 | `.body` | 候補名、ルーム名 |
| `body.button` | 本文 Black | 15〜17 | `.body` | ボタン |
| `body.regular` | 本文 Regular | 13〜14 | `.subheadline` | ひとこと、ヒント文 |
| `body.caption` | 本文 Regular/Bold | 11〜12 | `.caption` | メタ情報、補足 |

字間：行き先表示の「？？？」は 0.2em、招待コードは 0.12em。それ以外は 0。

---

## 3. 形・余白・線・影

| トークン | 値 |
|---|---|
| 画面の左右余白 | 16 |
| カード内の余白 | 14（人気カードは上だけ 20） |
| 要素間の間隔 | 4 / 6 / 8 / 10 / 12 / 14 / 16 / 22 / 24 |
| 角丸 `radius.xs` | 6〜8（バッジ、チップ） |
| 角丸 `radius.s` | 10〜12（小ボタン、タブ、タイル小） |
| 角丸 `radius.m` | 14〜16（入力欄、ボタン、PlaceRow、カテゴリタイル） |
| 角丸 `radius.l` | 18〜20（カード、主ボタン、ルームパネル） |
| 角丸 `radius.pill` | 999（状態チップ、アバター） |
| 線 `border.regular` | 2pt `ink` |
| 線 `border.strong` | 2.5pt `ink` |
| ハードシャドウ `shadow.hard` | x 0 / y 4 / ぼかし 0 / `ink`（小さいボタンは y 3） |
| 最小タップ領域 | 44×44 |
| 本文の最大幅 `layout.contentMaxWidth` | 600（左右の余白 16 を除く。iPad の広い画面では中央に寄せる） |
| 2 列の画面の本文の最大幅 `layout.wideContentMaxWidth` | 1000（ホーム・ルームを 2 列に分けたとき） |
| 2 列に分けるときの 1 列の最小の幅 `layout.columnMinWidth` | 358（iPhone 15 の本文の幅。列を iPhone より狭くしない） |
| ルームの左の列の幅 `layout.sidePaneWidth` | 360（ルームパネルとガチャのボタン） |

iPad での使い方は 03 の §3「iPad」。iPhone の画面の幅はどれも本文の最大幅より狭いので、iPhone の見た目は変わらない。

---

## 4. 部品

寸法の単位は pt。プロトタイプの該当箇所を見ると正確な見た目が確認できます。

### Button

| 種類 | 高さ | 角丸 | 背景 | 文字 | 線 | 影 |
|---|---|---|---|---|---|---|
| `PrimaryButton` | 56 | 18 | `accent.primary` | 白 body.button 17 | 2.5 ink | hard |
| `SecondaryButton` | 48〜52 | 16 | 白 | ink 15 | 2 ink | なし |
| `YellowButton` | 40〜44 | 12〜14 | `accent.secondary` | ink 14 | 2 ink | なし |
| `DarkButton` | 52 | 16 | `ink` | 白 16 | なし | なし |
| `DashedButton` | 48 | 16 | 透明 | ink 14 | 2 ink 点線 | なし |
| 無効状態 | — | — | `surface.disabled` | `text.disabled` | 背景と同色 | なし |

押下時：`scaleEffect(0.97)`＋影を y 1 に縮める（0.1秒）。

### StatusChip
高さ約22、左右10、角丸 pill、本文 Bold 12。色は「状態チップ」の表。

### DestinationBoard（行き先表示）
黒帯（背景 `ink`）、左右14〜16、上下10〜12、角丸12（カードの上部に置くときは上だけ角丸）。
「行き先」（11 Bold、`text.onInk`）＋「？？？」（display.m、`accent.secondary`、字間0.2em）＋右端「カプセル **N** 個」（12、数字は `accent.secondary` 15 Bold）。

### RoomTagCard（ホームの進行中ルーム）
白、線2.5、角丸20、hard 影、余白16。右上に荷札の穴（直径14、線2.5、中は `bg.base`）。中身は 03 の S-02 参照。

### TicketStub（思い出のきっぷ）
白、線2、角丸16。右端78pt幅を点線（2pt `line.dashedStrong`）で区切り、中央に **Stamp**（直径50、「済」）。

### Stamp（ハンコ）
円、線3 `accent.text`、文字 `accent.text`（見出しフォント）、`rotationEffect(-14°)`。結果のきっぷでは直径70「決定」19pt＋日付 `M.DD` 9pt Black、背景は白85%。

### CandidateCard

```
┌───────────────────────────────────────────┐  白 / 線2 / 角丸18 / 余白14
│ [タイル52] [NEW] 候補名（16 Black）  [♥ 52] │
│           📍 エリア · カテゴリ（12）    いいね │
│           ┌ひとこと（13、吹き出し）┐           │
│           みさきさんの投稿 · 3日前（12）      │
│ (ア)(イ)(ウ) 4 人がいいね                    │  ← LikeRow
│ - - - - - - - - - - - - - - - - - - - - - │  点線 2pt line.dashed
│ [出やすい] ■■■■■■■■■□□□□  16%            │  ← ProbabilityMeter
└───────────────────────────────────────────┘
```
（図中の 📍 はピンアイコン `ui-pin.svg` を表す。実装では絵文字を使わない）

- **人気カード**（F-23）：背景 `surface.highlight`、線2.5、hard 影、上の余白20。左上（x14, y−13）に **Ribbon**
- **Ribbon**：背景 `ink`、文字 `accent.secondary`（display.tag 12）、星アイコン13、左右10・上下3、角丸8。文言「みんな推し」／「全員いいね」
- **NEW バッジ**：背景 `accent.text`、白、display.tag 11、左右7、角丸6、字間0.06em
- **ひとこと吹き出し**：背景 `surface.subtle`、角丸「左上4・他12」、左右10・上下6
- **いいねボタン**：52×52、角丸14、線なし。ハート22＋下に11pt の文言（いいね／いいね済／自分）。背景・色は `like.*`。いいね済みはハートを塗りつぶし `accent.text`
- **LikeRow**：アバター26（白い2pt の縁、左に6pt ずつ重ねる。縁の色はカード背景と同じ）＋人数（display.s 20、人気カードでは `accent.text`）＋「人がいいね」（13 Black）。0件なら「まだいいねはありません」（12 `text.secondary`）
- **ProbabilityMeter**：レベルチップ（最小幅56、12 Black、角丸8）＋溝（高さ12、角丸6、`surface.muted`）＋バー（レベル色、幅は F-22）＋%（display.l 24 ＋「%」13、最小幅58、右寄せ）

### PlaceRow（検索結果・過去のアイデア）
白、線2、角丸16、余白 10/12。カテゴリタイル42（角丸12、アイコン24）、場所名15 Black、メタ12、右にボタン（高さ40、最小幅72、角丸12、線2。有効：`accent.secondary`、無効：`surface.disabled`）。

### TabSwitch
下地 `surface.muted`、角丸14、内側4。各タブ高さ40、角丸10。選択中は白＋線2 ink、非選択は透明。

### SegmentedChoice / Stepper
SegmentedChoice：等幅グリッド、間隔8、各ボタン高さ48・角丸12・線2。選択中 `accent.primary`＋白文字、非選択 白＋ink 文字。
Stepper：白、線2、角丸14、内側8。−／＋ボタン44×44（角丸12、線2、`bg.base`）、中央に数値（display 22）＋「件まで」（14 Black）。

### Avatar
円。44（ルームパネル）／28（ホーム）／26（LikeRow）。1文字（Black、サイズの約0.36倍）。準備OKのバッジ：直径20、`accent.secondary`、白い2pt の縁、チェック12、右下に −3 ずらす。

### GachaMachine

| パーツ | 寸法・見た目 |
|---|---|
| ドーム | 直径250、線5 ink、背景 `#FFFDF9`、中身をクリップ。左上にハイライト（46×18 白90%、−30°） |
| ドームのカプセル | 直径40、線3 ink、`capsule` 色の2色塗り分け、ランダムな回転。下半分（y 120〜200）に散らす |
| 本体 | 280×210、ドームに14重ねる、線5 ink、角丸「上14・下30」、背景 `accent.primary` |
| ネームプレート | 本体上部中央、白、線2.5、角丸8、「ドコガチャ」見出し15 |
| レバー | 本体の左（x30, y70）、直径96、線5、背景 `accent.secondary`。中に白いバー（72×18、線3、角丸9） |
| 取り出し口 | 本体の右下（右26, 下26）、96×76、角丸16、背景 `ink` |
| 出てくるカプセル | 直径60、白い線4、当選候補の色の2色塗り分け |

### DestinationTicket（行き先きっぷ）

```
┌──────────────────────────────────┐ 白 / 線2.5 / 角丸18 / hard 影（y5）
│▓ 行き先きっぷ          11月の日帰り旅行 ▓│ 帯：accent.primary、白文字、上下10・左右16
│ [タイル52]                    ╭決定╮ │
│ 高尾山 ゆき（27 / 15）         │10.21│ │ スタンプ：右12・上54、直径70
│ 東京・八王子市 · 自然・ハイキング  ╰───╯ │ 本文の右余白86（スタンプと重ならない）
│ ┌紅葉シーズンにちょうどいい┐            │
◖- - - - - - - - - - - - - - - - - - -◗ 切り取り線：左右に直径22の半円の切り欠き
│ 投稿        いいね        当選確率     │ 3列：ラベル11 / 値（名前14 Black、数値は見出し17）
│ みさきさん   4            16%        │
└──────────────────────────────────┘
```
共有画像は、このきっぷを 3倍の解像度で書き出し、下に「ドコガチャ｜友達旅行・おでかけの行き先ガチャ」を追加する。

### Toast
背景 `ink`、白、14 Bold、左右18・上下12、角丸14。画面下から150。

### AdFreeNotice
高さ40、角丸20、背景 `accent.pale`、文字 `accent.paleText` 12 Bold、王冠アイコン16。

---

## 5. アニメーション

「視差効果を減らす」がオンのときは、すべて即時切り替え（フェード0.2秒のみ）にする。
S-13 の筐体の動き（`shake`〜`open`）の値は、コードの `GachaMotion`・`GachaTimeline` にまとめている。

| 名前 | 対象 | 内容 | 時間・カーブ |
|---|---|---|---|
| `shake` | ドーム | ±4°→±3°で左右に揺れる。抽選の結果が遅いときは落ち始めるまで繰り返し、落ち始めから0.35秒で0に収める | 0.4秒×4回（回転中の1.6秒）、easeInOut |
| `turn` | レバーのバー | 0.2秒ごとに90°ずつ、押し込むように加速して（easeIn）回り、刻みの終わり（回転中の触覚の刻みと同じ時刻）でカチッと止まる。止まった直後に少し（最大約4°）行き過ぎて戻る。8刻みで720° | 1.6秒 |
| `tumble` | ドームのカプセル | 1個ずつ、横に6〜16・上に12〜30の範囲でかき混ぜて跳ねさせ（底より下には行かない）、転がす。番号ごとに速さ（9〜15 rad/秒）・向き・位相をずらす。強さは0.25秒で最大にし、抽選の結果が遅いときは落ち始めるまで続け、落ち始めから0.35秒で置き場所に収める。転がる角度は強さに比例した速さで積み、収めるときも巻き戻さずに減速して止める | 回転中（通常1.6秒）＋0.35秒 |
| `exit` | 当選のカプセル（ドームの中） | 置き場所から、ドームの底の真ん中（抜け口）へ吸い込まれ（easeIn）、0.7倍に小さくなって、後ろの4割で消える | 0.35秒（落ち始めから） |
| `drop` | 出てくるカプセル | `exit` の後に、上−90から落ちて（easeIn）、+6→−8→0とバウンド。底に当たった瞬間に横1.12倍・縦0.86倍につぶれて0.12秒で戻り、跳ね返りで−22°転がって戻る | 0.7秒（`exit` の後） |
| `open` | カプセル | 落ちて跳ね終えてから0.4秒後に、1.6倍に拡大しながら消える（押さずに開く） | 0.5秒、easeIn |
| `pop` | きっぷ | 0.7倍・透明 → 等倍（S-14 をルーム・通知から直接開いたとき） | 0.45秒、cubic-bezier(.2,.9,.3,1.3)（SwiftUI では `.spring(response: 0.45, dampingFraction: 0.6)`） |
| `stamp` | 決定スタンプ | 2.2倍・透明 → 0.92倍 → 等倍（−14°のまま） | 0.5秒、0.5秒遅延 |
| `meter` | 出やすさのバー | 幅の変化 | 0.35秒、easeOut |
| `toast` | トースト | 下から12上がりながらフェードイン | 0.25秒 |
| いいね | ハート | 押した瞬間に 1.0→1.25→1.0 | 0.25秒（spring） |

### 結果の演出（S-14）

S-13 でカプセルを開けた直後に、S-14 で行き先きっぷを出す演出。S-16 で 3 つから選ぶ（標準はパタパタ行き先表示）。
時刻は S-14 に替わってから（S-13 のフェード 0.45 秒と重なる）。値はコードの `FlapBoardTimeline`・`CapsuleBurstTimeline`・`TicketIssueTimeline` にまとめている。

共通：
- 演出の間は見出し・レア当選・ボタン・引き直しの欄・下部の決定を隠し、**決まる瞬間**に見出しとレア当選、**終わり**に残りを、下から 8 上げながら出す（0.3秒、easeOut）
- ハンコは `stamp` と同じ形（2.2倍・透明 → 0.92倍 → 等倍）で、演出の時刻に合わせて押す。紙に当たった瞬間に `.impact(.rigid)`
- 決まる瞬間に `.success`。演出の途中にきっぷの辺りを押すと最後まで飛ばす
- 「視差効果を減らす」では、下の表の「視差効果を減らす」の流れ（フェード 0.2秒だけ）にする。刻みの触覚は鳴らさない

| 演出 | 溜め | 決まる瞬間 | 余韻 | 終わり | 触覚 | 視差効果を減らす |
|---|---|---|---|---|---|---|
| パタパタ行き先表示（標準） | きっぷと同じ大きさの黒帯（`ink`。上に「行き先」とルーム名、真ん中に高さ112の札の窓、右下に「カプセル N個」）。0.35秒から「？？？」→ 抽選の対象だった候補の名前を14回めくる（1回 0.14 → 0.07秒まで速くし、最後は 0.30秒までゆっくり）。上の札が手前に倒れてから下の札が落ちる | 1.98秒。当選の名前（`display.xl`、`accent.secondary`）で止まり、窓の縁が `accent.secondary` で2回点滅、名前が1.06倍に弾む | 0.55秒見せてから、黒帯が手前に倒れ（0.18秒、easeIn）、裏からきっぷが起き上がる（ばね response 0.42・damping 0.72）→ 0.4秒後にハンコ | 3.61秒 | めくるたびに `.impact(.light)`（速いとき 0.3・遅いとき 0.7） | 「？？？」0.5秒 → 当選の名前へフェード → 0.65秒後にきっぷへフェード |
| カプセルぱかっ | 当選の色のカプセル（直径120・線5）が1.25倍から縮んで出る（0.35秒）→ 0.4秒から底を支点に揺れる（−6°→6°→−8°→8°→−11°→11°→0°、0.12秒ずつ）→ 横1.1倍・縦0.86倍に縮む（0.14秒） | 1.38秒。上下に割れ、殻は回りながら飛んで消える（0.55秒）。きっぷが0.2倍・−8°からばね（response 0.5・damping 0.6）で飛び出す。紙吹雪（カプセルの6色・42片・線1.5 `ink`。1.6秒で消える） | 0.1秒後に見出し → 0.6秒後にハンコ | 2.48秒 | 揺れの山ごとに `.impact(.light)` を6回（0.35 → 0.8） | カプセルを0.55秒見せ、きっぷへフェード。紙吹雪なし |
| 発券 | きっぷの下端に `ink` の取り出し口（高さ14、左右に10はみ出す）が出て（0.25秒）、きっぷが下から押し出される（7刻み・0.1秒ずつ。帯からカテゴリタイルまで）。名前の手前で0.45秒止める | 1.82秒。名前の段を一気に押し出す（0.22秒） | 残りを6刻みで出し、取り出し口が下に外れ、きっぷが4沈んで戻る → ハンコ | 3.37秒 | 押し出す刻みごとに `.impact(.light)`（13回）、取り出し口から離れた瞬間 `.impact(.medium)` | 取り出し口を出さず、きっぷをフェード |

サウンド：MVP では入れない（後で追加できるように、演出の各タイミングにフックを用意する）。

---

## 6. アイコン

`design/icons/` に 24×24 の線画 SVG を同梱しています（線幅は各ファイルに記載、`stroke="currentColor"`）。
Xcode のアセットカタログに SVG のまま入れ、「Preserve Vector Data」をオン、Render As を「Template Image」にして色を付けてください。

| ファイル | 用途 |
|---|---|
| `cat-*.svg`（9種） | カテゴリタイル |
| `ui-back.svg` | 戻る |
| `ui-plus.svg` | 追加 |
| `ui-heart.svg` | いいね（塗りは `fill` で切り替え） |
| `ui-pin.svg` | 場所・マップで開く |
| `ui-share.svg` | 共有・招待リンク |
| `ui-search.svg` | 検索 |
| `ui-history.svg` | 過去のアイデア |
| `ui-check.svg` | 準備OK のバッジ |
| `ui-star.svg` | リボン（塗り） |
| `ui-crown.svg` | 広告なしメッセージ |
| `route-deco.svg` | ホームの装飾（点線の道のり＋ピン。多色、テンプレートにしない） |

歯車・閉じるなど、ここにないアイコンは SF Symbols（`gearshape`、`xmark`）を `fontWeight(.bold)` で使ってよい。

---

## 7. SwiftUI 実装メモ

```swift
extension Color {
    static let dgBase = Color(hex: 0xFFF7EE)
    static let dgInk = Color(hex: 0x2B2118)
    static let dgAccent = Color(hex: 0xD93A1F)
    // … tokens.json の値をすべて定義する
}

extension Font {
    static func dgDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("MochiyPopOne-Regular", size: size, relativeTo: style)
    }
    static func dgBody(_ size: CGFloat, weight: DGWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style) // ZenMaruGothic-*
    }
}

/// ハードシャドウ：ぼかしのない影を真下にずらす
struct HardShadow: ViewModifier {
    var y: CGFloat = 4
    var cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.dgInk)
                .offset(y: y)
        )
    }
}

/// カプセルの2色塗り分け
struct CapsuleBall: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(LinearGradient(stops: [.init(color: color, location: 0.5), .init(color: .white, location: 0.5)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Circle().stroke(Color.dgInk, lineWidth: 3))
    }
}
```

- 部品は `DesignSystem/Components/` に1ファイル1部品で置き、Xcode Preview でプロトタイプと見比べられるようにする
- 色のコントラスト：本文の文字は背景に対して 4.5:1 以上を守る（上の表の組み合わせはすべて満たす）
