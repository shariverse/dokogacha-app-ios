//
//  Color+DG.swift
//  Dokogacha
//
//  `docs/spec/design/tokens.json` の `color` をそのまま写した色のトークン。
//  画面や部品では色を直接書かず、ここのトークンだけを使う（`04_design_system.md` の §1）。
//

import SwiftUI

// トークンはビューの外（モデル・テストの引数の一覧など）からも読めるように、MainActor に閉じ込めない。
// `Color` は `Sendable` なので、`nonisolated` の `static let` で安全に共有できる。
nonisolated extension Color {
    /// `0xRRGGBB` の 16 進数から、sRGB の不透明な色を作る。
    ///
    /// tokens.json の `#RRGGBB` をそのまま写せるようにするための入口。
    /// - Parameter hex: 上位から R・G・B を 8 ビットずつ並べた値（例: `0xFFF7EE`）
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    // MARK: 背景・面（`color.bg` / `color.surface`）

    /// 画面の背景（`bg.base`）
    static let dgBgBase = Color(hex: 0xFFF7EE)
    /// カード・入力欄（`surface.card`）
    static let dgSurfaceCard = Color(hex: 0xFFFFFF)
    /// 人気候補（みんな推し／全員いいね）のカード（`surface.highlight`）
    static let dgSurfaceHighlight = Color(hex: 0xFFF1C9)
    /// 吹き出し（ひとこと）の背景（`surface.subtle`）
    static let dgSurfaceSubtle = Color(hex: 0xFFF7EE)
    /// タブの下地、メーターの溝（`surface.muted`）
    static let dgSurfaceMuted = Color(hex: 0xF1E4D6)
    /// 無効ボタンの背景（`surface.disabled`）
    static let dgSurfaceDisabled = Color(hex: 0xE6D9CB)
    /// 広告枠のプレースホルダ（`surface.ad`）
    static let dgSurfaceAd = Color(hex: 0xFBF1E6)
    /// ガチャのドームの背景（`surface.gachaDome`）
    static let dgSurfaceGachaDome = Color(hex: 0xFFFDF9)

    // MARK: 墨色・文字・線（`color.ink` / `color.text` / `color.line`）

    /// 文字、線、ハードシャドウ、黒帯（`ink`）
    static let dgInk = Color(hex: 0x2B2118)
    /// 本文の文字（`text.primary`。`ink` と同じ値）
    static let dgTextPrimary = Color(hex: 0x2B2118)
    /// 補足文（`text.secondary`。`bg.base` の上で 4.9:1）
    static let dgTextSecondary = Color(hex: 0x6E5E50)
    /// 無効ボタンの文字（`text.disabled`）
    static let dgTextDisabled = Color(hex: 0x5E5045)
    /// 黒帯の上の補足文（`text.onInk`）
    static let dgTextOnInk = Color(hex: 0xF3E3CF)
    /// 朱色のボタンの上の文字（`text.onAccent`）
    static let dgTextOnAccent = Color(hex: 0xFFFFFF)
    /// カード内の点線の区切り（`line.dashed`）
    static let dgLineDashed = Color(hex: 0xE3D3C2)
    /// きっぷの切り取り線、広告枠（`line.dashedStrong`）
    static let dgLineDashedStrong = Color(hex: 0xCDB9A4)

    // MARK: アクセント（`color.accent`）

    /// 主ボタンの背景、筐体の本体色、きっぷの帯（`accent.primary`）
    static let dgAccentPrimary = Color(hex: 0xD93A1F)
    /// 朱色の文字、NEW バッジ、スタンプ、いいね済みのハート（`accent.text`）
    static let dgAccentText = Color(hex: 0xB8321A)
    /// 黄色ボタン（準備OK、候補を追加）、レバー、黒帯の上の強調文字（`accent.secondary`）
    static let dgAccentSecondary = Color(hex: 0xFFC93C)
    /// 「前回惜しかった」バッジ、広告なしメッセージの背景（`accent.pale`）
    static let dgAccentPale = Color(hex: 0xFFF0C2)
    /// `accent.pale` の上の文字（`accent.paleText`）
    static let dgAccentPaleText = Color(hex: 0x5C4600)

    // MARK: いいね（`color.like`）

    /// いいねボタンの背景（未いいね。`like.bg`）
    static let dgLikeBg = Color(hex: 0xF7EEE4)
    /// いいねボタンの背景（いいね済み。`like.bgActive`）
    static let dgLikeBgActive = Color(hex: 0xFDE3DC)
    /// いいねボタンのハート（未いいね。`like.icon`）
    static let dgLikeIcon = Color(hex: 0x5E5045)
    /// いいねボタンのハート（いいね済み。`like.iconActive`）
    static let dgLikeIconActive = Color(hex: 0xB8321A)
    /// 自分の投稿のハート（無効。`like.iconMine`）
    static let dgLikeIconMine = Color(hex: 0x9C8B7C)

    // MARK: カプセル・アバター（`color.capsule` / `color.avatar` / `color.avatarNotReady`）

    /// カプセルの色（`capsule`）。候補の投稿順のインデックスで `dgCapsule(at:)` から選ぶ
    static let dgCapsules: [Color] = [
        Color(hex: 0xFF7A59),
        Color(hex: 0xFFC93C),
        Color(hex: 0x3CC9A0),
        Color(hex: 0x4DA3FF),
        Color(hex: 0xFF8FC7),
        Color(hex: 0x9B7BFF)
    ]

    /// アバターの背景色（`avatar`）。どれも白文字で 4.5:1 以上
    static let dgAvatars: [Color] = [
        Color(hex: 0xB8321A),
        Color(hex: 0x23775D),
        Color(hex: 0x2F6FD0),
        Color(hex: 0xA3367E),
        Color(hex: 0x6B48C9),
        Color(hex: 0x8A5A12),
        Color(hex: 0x1F6E8C),
        Color(hex: 0x5E5045)
    ]

    /// 未準備のアバターの背景（`avatarNotReady.bg`）
    static let dgAvatarNotReadyBg = Color(hex: 0xF1E7DC)
    /// 未準備のアバターの文字（`avatarNotReady.fg`）
    static let dgAvatarNotReadyFg = Color(hex: 0x5E5045)

    /// 候補の投稿順のインデックスに対応するカプセルの色を返す。
    ///
    /// 04 の §1 のとおり `capsule[i % 6]` で割り当てるので、並び順を変えても色は変わらない。
    /// 負のインデックスが来ても落ちないよう、剰余を 0 以上にそろえる。
    /// - Parameter index: 候補の投稿順のインデックス（0 始まり）
    static func dgCapsule(at index: Int) -> Color {
        dgCapsules[wrappedIndex(index, count: dgCapsules.count)]
    }

    /// インデックスに対応するアバターの背景色を返す（8 色を順に繰り返す）。
    /// - Parameter index: 色を選ぶためのインデックス（0 始まり。負の値も受け付ける）
    static func dgAvatar(at index: Int) -> Color {
        dgAvatars[wrappedIndex(index, count: dgAvatars.count)]
    }

    /// `index` を `0..<count` に収める（負の値でも 0 以上の剰余にする）
    private static func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}

/// 背景と文字の 2 色の組（状態チップ・未準備のアバターなど）。
nonisolated struct DGColorPair: Sendable {
    /// 背景色
    let background: Color
    /// 文字・アイコンの色
    let foreground: Color
}

/// ルームの状態チップ（`color.status`）の色。
///
/// ルームの状態の型（`Domain/Models`）にはまだ依存させず、デザインのトークンとして状態ごとの組を持つ。
nonisolated enum DGStatusColors {
    /// 候補募集中（`status.open`）
    static let open = DGColorPair(background: Color(hex: 0xE3F2EC), foreground: Color(hex: 0x1E5E49))
    /// ガチャ解禁！（`status.unlocked`）
    static let unlocked = DGColorPair(background: Color(hex: 0xFFC93C), foreground: Color(hex: 0x2B2118))
    /// 行き先決定（`status.drawn`）
    static let drawn = DGColorPair(background: Color(hex: 0x2B2118), foreground: Color(hex: 0xFFC93C))
    /// 終了（`status.closed`）
    static let closed = DGColorPair(background: Color(hex: 0xF1E4D6), foreground: Color(hex: 0x5E5045))
}

/// 出やすさのレベル（F-22。`color.level`）のラベルと色。
nonisolated struct DGLevelStyle: Sendable {
    /// チップに出す文言（03 の表記）
    let label: LocalizedStringResource
    /// レベルのチップの背景
    let chipBackground: Color
    /// レベルのチップの文字
    let chipForeground: Color
    /// メーターのバーの色
    let bar: Color
    /// 出やすさ % の数字の色
    let number: Color

    /// 出やすい（`level.high`）
    static let high = DGLevelStyle(
        label: "出やすい",
        chipBackground: Color(hex: 0xD93A1F),
        chipForeground: Color(hex: 0xFFFFFF),
        bar: Color(hex: 0xD93A1F),
        number: Color(hex: 0xB8321A)
    )
    /// ふつう（`level.mid`）
    static let mid = DGLevelStyle(
        label: "ふつう",
        chipBackground: Color(hex: 0xFFC93C),
        chipForeground: Color(hex: 0x2B2118),
        bar: Color(hex: 0xFFC93C),
        number: Color(hex: 0x2B2118)
    )
    /// レア（`level.low`）
    static let low = DGLevelStyle(
        label: "レア",
        chipBackground: Color(hex: 0xDCEBFF),
        chipForeground: Color(hex: 0x1D5A99),
        bar: Color(hex: 0x4DA3FF),
        number: Color(hex: 0x1D5A99)
    )
    /// 平等（`level.flat`）
    static let flat = DGLevelStyle(
        label: "平等",
        chipBackground: Color(hex: 0xF1E4D6),
        chipForeground: Color(hex: 0x2B2118),
        bar: Color(hex: 0xCDB9A4),
        number: Color(hex: 0x2B2118)
    )
}

/// カテゴリタイル（`color.category`）の表示名・色・アイコン。
///
/// 表示名・アイコン名の正本はここに置く。アプリのカテゴリ（`Domain/Category.swift` の `PlaceCategory`）は
/// 保存する値と MapKit からの対応だけを持ち、見た目は `DGCategoryStyle.of(_:)` で引く。
nonisolated struct DGCategoryStyle: Sendable {
    /// カテゴリの表示名（03 の表記）
    let label: LocalizedStringResource
    /// タイルの背景
    let background: Color
    /// アイコンの色
    let foreground: Color
    /// アセットカタログのアイコン名（`design/icons` の SVG のファイル名）
    let iconName: String

    /// 水族館（`category.aquarium`）
    static let aquarium = DGCategoryStyle(
        label: "水族館", background: Color(hex: 0xD6ECFF), foreground: Color(hex: 0x1D5A99), iconName: "cat-aquarium"
    )
    /// 自然（`category.nature`）
    static let nature = DGCategoryStyle(
        label: "自然", background: Color(hex: 0xDDF3E6), foreground: Color(hex: 0x1E6B47), iconName: "cat-nature"
    )
    /// アート・美術館（`category.art`）
    static let art = DGCategoryStyle(
        label: "アート・美術館", background: Color(hex: 0xF1E3FF), foreground: Color(hex: 0x6B3FA0), iconName: "cat-art"
    )
    /// グルメ（`category.food`）
    static let food = DGCategoryStyle(
        label: "グルメ", background: Color(hex: 0xFFE4D6), foreground: Color(hex: 0xA23B12), iconName: "cat-food"
    )
    /// アクティビティ（`category.activity`）
    static let activity = DGCategoryStyle(
        label: "アクティビティ", background: Color(hex: 0xD9F4F1), foreground: Color(hex: 0x146B63), iconName: "cat-activity"
    )
    /// テーマパーク（`category.park`）
    static let park = DGCategoryStyle(
        label: "テーマパーク", background: Color(hex: 0xFFE1EE), foreground: Color(hex: 0xA02A62), iconName: "cat-park"
    )
    /// 街歩き（`category.town`）
    static let town = DGCategoryStyle(
        label: "街歩き", background: Color(hex: 0xFFF0C2), foreground: Color(hex: 0x7A5A00), iconName: "cat-town"
    )
    /// 寺社（`category.shrine`）
    static let shrine = DGCategoryStyle(
        label: "寺社", background: Color(hex: 0xFFDCD6), foreground: Color(hex: 0xA12A1A), iconName: "cat-shrine"
    )
    /// 海（`category.sea`）
    static let sea = DGCategoryStyle(
        label: "海", background: Color(hex: 0xD6F0FF), foreground: Color(hex: 0x165E8C), iconName: "cat-sea"
    )
}
