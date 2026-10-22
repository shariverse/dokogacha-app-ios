//
//  DesignTokensTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import SwiftUI
import Testing

/// `DesignSystem/Tokens` の値を、正本の `docs/spec/design/tokens.json` と突き合わせる。
///
/// tokens.json はテストのバンドルに複製せず、このファイルの場所（`#filePath`）からリポジトリの正本を読む。
/// 複製すると正本を直したときに片方だけ古くなり、テストが古い値どうしで通ってしまうため。
/// テストはソースを持つ Mac の Simulator で動くので、ホストのファイルをそのまま読める。
///
/// 色は「tokens.json の色の一覧」と「アプリの色の一覧」の鍵が過不足なく一致することも確かめ、
/// tokens.json に色を足したのにアプリで定義し忘れた、という漏れを検出する。
struct DesignTokensTests {
    // MARK: tokens.json の読み込み

    /// リポジトリの `docs/spec/design/tokens.json` の場所（このファイルは `DokogachaTests/` の直下にある）
    nonisolated static let tokensURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "docs/spec/design/tokens.json")

    /// tokens.json を読んで、最上位の辞書を返す
    static func loadTokens() throws -> [String: Any] {
        let data = try Data(contentsOf: tokensURL)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], "tokens.json の最上位が辞書ではない")
    }

    /// `a.b.c` の形の鍵で、入れ子の辞書から値を取り出す
    static func value(_ path: String, in root: [String: Any]) throws -> Any {
        var current: Any = root
        for key in path.split(separator: ".").map(String.init) {
            let dictionary = try #require(current as? [String: Any], "\(path) の途中が辞書ではない")
            current = try #require(dictionary[key], "tokens.json に \(path) が無い")
        }
        return current
    }

    /// `a.b.c` の形の鍵で、数値を取り出す
    static func number(_ path: String, in root: [String: Any]) throws -> Double {
        let raw = try value(path, in: root)
        return try #require((raw as? NSNumber)?.doubleValue, "\(path) が数値ではない")
    }

    /// `color` の下にある `#RRGGBB` の値を、`status.open.bg`・`capsule[0]` の形の鍵ですべて集める。
    ///
    /// `label`・`icon` のような色でない文字列は集めない（別のテストで確かめる）。
    static func colorLeaves(_ node: Any, prefix: String = "") -> [String: String] {
        if let hex = node as? String {
            return hex.hasPrefix("#") ? [prefix: hex.uppercased()] : [:]
        }
        if let array = node as? [Any] {
            return array.enumerated().reduce(into: [:]) { result, item in
                result.merge(colorLeaves(item.element, prefix: "\(prefix)[\(item.offset)]")) { first, _ in first }
            }
        }
        if let dictionary = node as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, item in
                let path = prefix.isEmpty ? item.key : "\(prefix).\(item.key)"
                result.merge(colorLeaves(item.value, prefix: path)) { first, _ in first }
            }
        }
        return [:]
    }

    /// 色を sRGB の `#RRGGBB` の文字列にする（tokens.json の表記と比べるため）
    static func hexString(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        let components = [resolved.red, resolved.green, resolved.blue].map { Int(($0 * 255).rounded()) }
        return "#" + components.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: アプリ側のトークンの一覧

    /// tokens.json の `color` の鍵と、アプリの色のトークンの対応
    static var appColors: [String: Color] {
        var colors: [String: Color] = [
            "bg.base": .dgBgBase,
            "surface.card": .dgSurfaceCard,
            "surface.highlight": .dgSurfaceHighlight,
            "surface.subtle": .dgSurfaceSubtle,
            "surface.muted": .dgSurfaceMuted,
            "surface.disabled": .dgSurfaceDisabled,
            "surface.ad": .dgSurfaceAd,
            "surface.gachaDome": .dgSurfaceGachaDome,
            "ink": .dgInk,
            "text.primary": .dgTextPrimary,
            "text.secondary": .dgTextSecondary,
            "text.disabled": .dgTextDisabled,
            "text.onInk": .dgTextOnInk,
            "text.onAccent": .dgTextOnAccent,
            "line.dashed": .dgLineDashed,
            "line.dashedStrong": .dgLineDashedStrong,
            "accent.primary": .dgAccentPrimary,
            "accent.text": .dgAccentText,
            "accent.secondary": .dgAccentSecondary,
            "accent.pale": .dgAccentPale,
            "accent.paleText": .dgAccentPaleText,
            "like.bg": .dgLikeBg,
            "like.bgActive": .dgLikeBgActive,
            "like.icon": .dgLikeIcon,
            "like.iconActive": .dgLikeIconActive,
            "like.iconMine": .dgLikeIconMine,
            "avatarNotReady.bg": .dgAvatarNotReadyBg,
            "avatarNotReady.fg": .dgAvatarNotReadyFg
        ]
        let statuses: [String: DGColorPair] = [
            "open": DGStatusColors.open,
            "unlocked": DGStatusColors.unlocked,
            "drawn": DGStatusColors.drawn,
            "closed": DGStatusColors.closed
        ]
        for (key, pair) in statuses {
            colors["status.\(key).bg"] = pair.background
            colors["status.\(key).fg"] = pair.foreground
        }
        for (key, level) in levels {
            colors["level.\(key).chipBg"] = level.chipBackground
            colors["level.\(key).chipFg"] = level.chipForeground
            colors["level.\(key).bar"] = level.bar
            colors["level.\(key).number"] = level.number
        }
        for (key, category) in categories {
            colors["category.\(key).bg"] = category.background
            colors["category.\(key).fg"] = category.foreground
        }
        for (index, color) in Color.dgCapsules.enumerated() {
            colors["capsule[\(index)]"] = color
        }
        for (index, color) in Color.dgAvatars.enumerated() {
            colors["avatar[\(index)]"] = color
        }
        return colors
    }

    /// tokens.json の `level` の鍵と、アプリの出やすさのレベル
    static let levels: [String: DGLevelStyle] = ["high": .high, "mid": .mid, "low": .low, "flat": .flat]

    /// tokens.json の `category` の鍵と、アプリのカテゴリタイル。
    ///
    /// 鍵はアプリのカテゴリ（`PlaceCategory`）の `rawValue` から作るので、保存する値が tokens.json の鍵と
    /// 一致すること・カテゴリごとの見た目（`DGCategoryStyle.of(_:)`）の対応が正しいことも一緒に確かめる。
    static let categories: [String: DGCategoryStyle] = Dictionary(
        uniqueKeysWithValues: PlaceCategory.allCases.map { ($0.rawValue, DGCategoryStyle.of($0)) }
    )

    /// tokens.json の `typeScale` の鍵と、アプリのタイプスケール
    static let typeScales: [String: DGTypeScale] = [
        "display.xl": .displayXL,
        "display.ticket": .displayTicket,
        "display.l": .displayL,
        "display.m": .displayM,
        "display.s": .displayS,
        "display.header": .displayHeader,
        "display.section": .displaySection,
        "display.tag": .displayTag,
        "body.title": .bodyTitle,
        "body.button": .bodyButton,
        "body.regular": .bodyRegular,
        "body.caption": .bodyCaption
    ]

    /// tokens.json の `motion` の鍵と、アプリのアニメーションのトークン
    static let motions: [String: DGMotionSpec] = [
        "shake": DGMotion.shake,
        "turn": DGMotion.turn,
        "drop": DGMotion.drop,
        "pulse": DGMotion.pulse,
        "open": DGMotion.open,
        "pop": DGMotion.pop,
        "stamp": DGMotion.stamp,
        "meter": DGMotion.meter,
        "toast": DGMotion.toast
    ]

    // MARK: 色

    /// tokens.json の色がすべてアプリにあり、アプリにだけある色も無いことを確かめる
    @Test
    func colorKeysMatchTokens() throws {
        let tokens = try Self.colorLeaves(Self.value("color", in: Self.loadTokens()))
        #expect(!tokens.isEmpty)
        let missing = Set(tokens.keys).subtracting(Self.appColors.keys).sorted()
        let extra = Set(Self.appColors.keys).subtracting(tokens.keys).sorted()
        #expect(missing.isEmpty, "アプリに無い色: \(missing)")
        #expect(extra.isEmpty, "tokens.json に無い色: \(extra)")
    }

    /// アプリの色の値が tokens.json の `#RRGGBB` と同じであることを確かめる
    @Test
    func colorValuesMatchTokens() throws {
        let tokens = try Self.colorLeaves(Self.value("color", in: Self.loadTokens()))
        for (key, color) in Self.appColors {
            guard let expected = tokens[key] else {
                continue // 鍵の過不足は colorKeysMatchTokens で確かめる
            }
            #expect(Self.hexString(color) == expected, "\(key) の色が tokens.json と違う")
        }
    }

    /// `Color(hex:)` が上位から R・G・B の順に読むことを確かめる（並びを間違えると全部の色がずれる）
    @Test
    func hexInitializerReadsRGBInOrder() {
        #expect(Self.hexString(Color(hex: 0x123456)) == "#123456")
        #expect(Self.hexString(Color(hex: 0x000000)) == "#000000")
        #expect(Self.hexString(Color(hex: 0xFFFFFF)) == "#FFFFFF")
    }

    /// カプセルの色を投稿順のインデックスで 6 色の繰り返しに割り当てることを確かめる（04 の §1）
    @Test
    func capsuleColorWrapsByIndex() {
        #expect(Color.dgCapsules.count == 6)
        #expect(Self.hexString(.dgCapsule(at: 0)) == "#FF7A59")
        #expect(Self.hexString(.dgCapsule(at: 6)) == "#FF7A59")
        #expect(Self.hexString(.dgCapsule(at: 11)) == "#9B7BFF")
        #expect(Self.hexString(.dgCapsule(at: -1)) == "#9B7BFF")
        #expect(Self.hexString(.dgAvatar(at: 8)) == "#B8321A")
    }

    /// 出やすさのレベルとカテゴリの表示名・アイコン名が tokens.json と同じであることを確かめる
    @Test
    func labelsAndIconsMatchTokens() throws {
        let root = try Self.loadTokens()
        for (key, level) in Self.levels {
            let label = try #require(Self.value("color.level.\(key).label", in: root) as? String)
            #expect(String(localized: level.label) == label, "level.\(key) の表示名が tokens.json と違う")
        }
        let categoryKeys = try #require(Self.value("color.category", in: root) as? [String: Any]).keys
        #expect(Set(categoryKeys) == Set(Self.categories.keys))
        for (key, category) in Self.categories {
            let label = try #require(Self.value("color.category.\(key).label", in: root) as? String)
            let icon = try #require(Self.value("color.category.\(key).icon", in: root) as? String)
            #expect(String(localized: category.label) == label, "category.\(key) の表示名が tokens.json と違う")
            #expect(category.iconName == icon, "category.\(key) のアイコン名が tokens.json と違う")
        }
    }

    // MARK: フォント

    /// PostScript 名が tokens.json の `font` と同じであることを確かめる
    @Test
    func fontNamesMatchTokens() throws {
        let root = try Self.loadTokens()
        #expect(try Self.value("font.display.postScript.regular", in: root) as? String == DGFontName.display)
        for weight in DGWeight.allCases {
            let expected = try Self.value("font.body.postScript.\(weight.rawValue)", in: root) as? String
            #expect(expected == weight.postScriptName, "本文の \(weight.rawValue) の PostScript 名が tokens.json と違う")
        }
    }

    /// タイプスケールの種類・ウェイト・大きさ・追従するテキストスタイルが tokens.json と同じであることを確かめる
    @Test
    func typeScaleMatchesTokens() throws {
        let root = try Self.loadTokens()
        let scale = try #require(root["typeScale"] as? [String: [String: Any]])
        #expect(Set(scale.keys) == Set(Self.typeScales.keys))
        let textStyles: [String: Font.TextStyle] = [
            "largeTitle": .largeTitle,
            "title": .title,
            "title2": .title2,
            "title3": .title3,
            "headline": .headline,
            "body": .body,
            "subheadline": .subheadline,
            "caption": .caption
        ]
        for (key, token) in Self.typeScales {
            let entry = try #require(scale[key], "tokens.json に typeScale.\(key) が無い")
            #expect(entry["font"] as? String == token.family.rawValue, "\(key) のフォントの種類")
            #expect(entry["weight"] as? String == token.weight?.rawValue, "\(key) のウェイト")
            #expect((entry["size"] as? NSNumber)?.doubleValue == Double(token.size), "\(key) の大きさ")
            let style = try #require(textStyles[entry["relativeTo"] as? String ?? ""], "\(key) の relativeTo が対応表に無い")
            #expect(style == token.relativeTo, "\(key) の relativeTo")
        }
    }

    /// 見出しは Mochiy Pop One、本文はウェイトごとの Zen Maru Gothic を名前で選ぶことを確かめる
    @Test
    func typeScaleUsesBundledFonts() {
        #expect(DGTypeScale.displayXL.postScriptName == "MochiyPopOne-Regular")
        #expect(DGTypeScale.bodyButton.postScriptName == "ZenMaruGothic-Black")
        #expect(DGTypeScale.bodyRegular.postScriptName == "ZenMaruGothic-Regular")
    }

    // MARK: 寸法・線・影

    /// 角丸・線・余白・最小タップ領域が tokens.json と同じであることを確かめる
    @Test
    func metricsMatchTokens() throws {
        let root = try Self.loadTokens()
        let radius = try #require(root["radius"] as? [String: Any])
        #expect(radius.count == 5)
        #expect(try Self.number("radius.xs", in: root) == DGRadius.xs)
        #expect(try Self.number("radius.s", in: root) == DGRadius.sm)
        #expect(try Self.number("radius.m", in: root) == DGRadius.md)
        #expect(try Self.number("radius.l", in: root) == DGRadius.lg)
        #expect(try Self.number("radius.pill", in: root) == DGRadius.pill)

        let border = try #require(root["border"] as? [String: Any])
        #expect(border.count == 3)
        #expect(try Self.number("border.regular", in: root) == DGBorder.regular)
        #expect(try Self.number("border.strong", in: root) == DGBorder.strong)
        #expect(try Self.number("border.machine", in: root) == DGBorder.machine)

        #expect(try Self.number("spacing.screenX", in: root) == DGSpacing.screenX)
        #expect(try Self.number("spacing.cardPadding", in: root) == DGSpacing.cardPadding)
        let scale = try #require(Self.value("spacing.scale", in: root) as? [NSNumber]).map { CGFloat($0.doubleValue) }
        #expect(scale == DGSpacing.scale)
        #expect(try Self.number("minTapTarget", in: root) == DGMetrics.minTapTarget)
    }

    /// ハードシャドウのずれ・ぼかし・色が tokens.json と同じであることを確かめる
    @Test
    func shadowsMatchTokens() throws {
        let root = try Self.loadTokens()
        let shadows: [String: DGShadow] = ["hard": .hard, "hardSmall": .hardSmall]
        let keys = try #require(root["shadow"] as? [String: Any]).keys
        #expect(Set(keys) == Set(shadows.keys))
        for (key, shadow) in shadows {
            #expect(try Self.number("shadow.\(key).x", in: root) == shadow.x, "shadow.\(key).x")
            #expect(try Self.number("shadow.\(key).y", in: root) == shadow.y, "shadow.\(key).y")
            #expect(try Self.number("shadow.\(key).blur", in: root) == shadow.blur, "shadow.\(key).blur")
            let color = try #require(Self.value("shadow.\(key).color", in: root) as? String)
            #expect(Self.hexString(shadow.color) == color.uppercased(), "shadow.\(key).color")
        }
    }

    // MARK: アニメーション

    /// アニメーションの時間・曲線・遅れ・繰り返しが tokens.json と同じであることを確かめる
    @Test
    func motionsMatchTokens() throws {
        let root = try Self.loadTokens()
        let motion = try #require(root["motion"] as? [String: [String: Any]])
        #expect(Set(motion.keys) == Set(Self.motions.keys))
        for (key, spec) in Self.motions {
            let entry = try #require(motion[key])
            // pulse だけは繰り返しの周期を period で書いている
            let duration = (entry["duration"] ?? entry["period"]) as? NSNumber
            #expect(duration?.doubleValue == spec.duration, "\(key) の時間")
            #expect((entry["delay"] as? NSNumber)?.doubleValue ?? 0 == spec.delay, "\(key) の遅れ")
            #expect((entry["repeat"] as? NSNumber)?.intValue == spec.repeatCount, "\(key) の繰り返し")
            #expect(Self.curve(entry["curve"]) == spec.curve, "\(key) の曲線")
        }
        #expect(try Self.number("motion.toast.visibleFor", in: root) == DGMotion.toastVisibleFor)
    }

    /// tokens.json に無い、04 の §5 の「いいね」（ハートを 1.0→1.25→1.0 に 0.25 秒のばねで弾ませる）の値
    @Test
    func likeMotionMatchesDesignSystem() {
        #expect(DGMotion.like.duration == 0.25)
        #expect(DGMotion.like.delay == 0)
        #expect(DGMotion.like.repeatCount == nil)
        #expect(DGMotion.likeScale == 1.25)
    }

    /// tokens.json の `curve`（名前か、制御点 4 つの配列）を `DGMotionCurve` にする
    static func curve(_ raw: Any?) -> DGMotionCurve? {
        if let name = raw as? String {
            return switch name {
            case "easeIn": .easeIn
            case "easeOut": .easeOut
            case "easeInOut": .easeInOut
            default: nil
            }
        }
        if let points = (raw as? [NSNumber])?.map(\.doubleValue), points.count == 4 {
            return .bezier(points[0], points[1], points[2], points[3])
        }
        return nil
    }
}
