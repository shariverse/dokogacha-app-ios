//
//  Font+DG.swift
//  Dokogacha
//
//  `docs/spec/design/tokens.json` の `font` と `typeScale` を写したフォントのトークン。
//  見出しは Mochiy Pop One、本文は Zen Maru Gothic（`04_design_system.md` の §2）。
//

import SwiftUI

/// 同梱したフォントの PostScript 名（`font.*.postScript`）。
///
/// `Font.custom` は名前を間違えても黙ってシステムフォントに置き換わるので、名前はここ 1 か所にまとめる。
nonisolated enum DGFontName {
    /// 見出し（Mochiy Pop One。Regular だけで太字は無い）
    static let display = "MochiyPopOne-Regular"
    /// 本文 Regular（400）
    static let bodyRegular = "ZenMaruGothic-Regular"
    /// 本文 Medium（500）
    static let bodyMedium = "ZenMaruGothic-Medium"
    /// 本文 Bold（700）。04 の「bold」はこれ
    static let bodyBold = "ZenMaruGothic-Bold"
    /// 本文 Black（900）。04 の「heavy」「Black」はこれ
    static let bodyBlack = "ZenMaruGothic-Black"
}

/// 本文フォント（Zen Maru Gothic）のウェイト。
///
/// SwiftUI の `.fontWeight` で太らせると擬似ボールドになるので、ウェイトごとのフォントファイルを名前で選ぶ。
nonisolated enum DGWeight: String, CaseIterable, Sendable {
    /// Regular（400）
    case regular
    /// Medium（500）
    case medium
    /// Bold（700）
    case bold
    /// Black（900）
    case black

    /// このウェイトのフォントの PostScript 名
    var postScriptName: String {
        switch self {
        case .regular: DGFontName.bodyRegular
        case .medium: DGFontName.bodyMedium
        case .bold: DGFontName.bodyBold
        case .black: DGFontName.bodyBlack
        }
    }
}

nonisolated extension Font {
    /// 見出しフォント（Mochiy Pop One）を作る。数字（%・人数・カウント）もこれで表示する。
    ///
    /// Mochiy Pop One には太字が無いので、返した `Font` に `.bold()` を付けないこと（擬似ボールドで線がつぶれる）。
    /// - Parameters:
    ///   - size: 標準の文字サイズでの大きさ（pt）
    ///   - style: Dynamic Type で拡大・縮小するときに追従するテキストスタイル
    static func dgDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(DGFontName.display, size: size, relativeTo: style)
    }

    /// 本文フォント（Zen Maru Gothic）を作る。
    /// - Parameters:
    ///   - size: 標準の文字サイズでの大きさ（pt）
    ///   - weight: ウェイト（ウェイトごとのフォントファイルを選ぶ）
    ///   - style: Dynamic Type で拡大・縮小するときに追従するテキストスタイル
    static func dgBody(_ size: CGFloat, weight: DGWeight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: style)
    }

    /// タイプスケールのトークンからフォントを作る（`Font.dg(.displayXL)` のように使う）。
    /// - Parameter token: `typeScale` のトークン
    static func dg(_ token: DGTypeScale) -> Font {
        token.font
    }
}

/// タイプスケール（`typeScale`）の 1 段。フォントの種類・ウェイト・大きさ・追従するテキストスタイルの組。
///
/// `Font` からは大きさや種類を読み出せないので、値を持つ型にしてテストで tokens.json と突き合わせる。
/// 04 の §2 で幅のある大きさ（「16〜17」など）は tokens.json の値を既定にしてある。
/// 部品で別の大きさが要るときは `Font.dgDisplay(_:relativeTo:)` / `Font.dgBody(_:weight:relativeTo:)` を使う。
nonisolated struct DGTypeScale: Sendable {
    /// フォントの種類（見出し・本文）
    enum Family: String, Sendable {
        /// 見出し（Mochiy Pop One）
        case display
        /// 本文（Zen Maru Gothic）
        case body
    }

    /// フォントの種類
    let family: Family
    /// 本文のウェイト（見出しは Regular だけなので `nil`）
    let weight: DGWeight?
    /// 標準の文字サイズでの大きさ（pt）
    let size: CGFloat
    /// Dynamic Type で追従するテキストスタイル
    let relativeTo: Font.TextStyle

    /// この段の PostScript 名
    var postScriptName: String {
        switch family {
        case .display: DGFontName.display
        case .body: (weight ?? .regular).postScriptName
        }
    }

    /// この段のフォント（Dynamic Type に追従する）
    var font: Font {
        .custom(postScriptName, size: size, relativeTo: relativeTo)
    }

    /// ホームのロゴ（`display.xl`）
    static let displayXL = DGTypeScale(family: .display, weight: nil, size: 32, relativeTo: .largeTitle)
    /// きっぷの「◯◯ ゆき」（`display.ticket`）
    static let displayTicket = DGTypeScale(family: .display, weight: nil, size: 27, relativeTo: .title)
    /// ガチャのタイトル、出やすさ %（`display.l`）
    static let displayL = DGTypeScale(family: .display, weight: nil, size: 24, relativeTo: .title2)
    /// 行き先表示の「？？？」、結果のタイトル（`display.m`）
    static let displayM = DGTypeScale(family: .display, weight: nil, size: 22, relativeTo: .title2)
    /// いいね人数、準備OK人数（`display.s`）
    static let displayS = DGTypeScale(family: .display, weight: nil, size: 20, relativeTo: .title3)
    /// 画面ヘッダーのタイトル（`display.header`）
    static let displayHeader = DGTypeScale(family: .display, weight: nil, size: 18, relativeTo: .headline)
    /// セクション見出し（`display.section`）
    static let displaySection = DGTypeScale(family: .display, weight: nil, size: 17, relativeTo: .headline)
    /// NEW バッジ、リボン（`display.tag`）
    static let displayTag = DGTypeScale(family: .display, weight: nil, size: 12, relativeTo: .caption)
    /// 候補名、ルーム名（`body.title`）
    static let bodyTitle = DGTypeScale(family: .body, weight: .black, size: 16, relativeTo: .body)
    /// ボタン（`body.button`）
    static let bodyButton = DGTypeScale(family: .body, weight: .black, size: 17, relativeTo: .body)
    /// ひとこと、ヒント文（`body.regular`）
    static let bodyRegular = DGTypeScale(family: .body, weight: .regular, size: 14, relativeTo: .subheadline)
    /// メタ情報、補足（`body.caption`）
    static let bodyCaption = DGTypeScale(family: .body, weight: .regular, size: 12, relativeTo: .caption)
}

/// 字間（`04_design_system.md` の §2。文字の大きさに対する倍率 em）。
///
/// SwiftUI の `.tracking` は pt で受けるので、`DGTracking.points(_:fontSize:)` で換算して渡す。
nonisolated enum DGTracking {
    /// 行き先表示の「？？？」（0.2em）
    static let destination: CGFloat = 0.2
    /// 招待コード（0.12em）
    static let inviteCode: CGFloat = 0.12

    /// em の字間を、文字の大きさに合わせた pt に換算する。
    /// - Parameters:
    ///   - em: 文字の大きさに対する倍率
    ///   - fontSize: 文字の大きさ（pt）
    static func points(_ em: CGFloat, fontSize: CGFloat) -> CGFloat {
        em * fontSize
    }
}
