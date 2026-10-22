//
//  BundledResourcesTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing
import UIKit

/// アプリに同梱したフォントとアイコンが、実行時に名前で読めることを確かめる。
///
/// フォントは Info.plist の `UIAppFonts` の登録漏れ・ファイル名の誤りがあっても
/// ビルドは通り、`Font.custom` が黙ってシステムフォントに置き換わるだけなので、ここで検出する。
struct BundledResourcesTests {
    /// `docs/spec/04_design_system.md` の §2 に載っている PostScript 名。
    ///
    /// `@Test(arguments:)` はテストの一覧を作るときに MainActor の外から読むので、引数の一覧は `nonisolated` にする
    nonisolated static let postScriptNames = [
        "MochiyPopOne-Regular",
        "ZenMaruGothic-Regular",
        "ZenMaruGothic-Medium",
        "ZenMaruGothic-Bold",
        "ZenMaruGothic-Black"
    ]

    /// `docs/spec/design/icons/` の SVG のファイル名（＝アセット名）と、それを元にアプリ側で足したアイコン
    nonisolated static let templateIconNames = [
        "cat-activity",
        "cat-aquarium",
        "cat-art",
        "cat-food",
        "cat-nature",
        "cat-park",
        "cat-sea",
        "cat-shrine",
        "cat-town",
        "ui-back",
        "ui-check",
        "ui-crown",
        "ui-heart",
        "ui-history",
        "ui-pin",
        "ui-plus",
        "ui-search",
        "ui-share",
        "ui-star",
        // `ui-heart` を塗りつぶした版（いいね済みのハート）。04 の §6「塗りは fill で切り替え」をテンプレート画像で描くため、
        // `design/icons` には無いが同じ形の SVG をアプリ側で足している
        "ui-heart-fill"
    ]

    /// 多色の装飾。テンプレートにせず元の色で描く
    nonisolated static let originalIconName = "route-deco"

    /// PostScript 名で `UIFont` を作れること（＝フォントが登録されていること）を確かめる
    @Test(arguments: postScriptNames)
    func fontIsRegistered(postScriptName: String) throws {
        let font = try #require(
            UIFont(name: postScriptName, size: 17),
            "\(postScriptName) が読めない。Info.plist の UIAppFonts と Resources/Fonts を確かめる"
        )
        #expect(font.fontName == postScriptName)
    }

    /// 線画アイコンがテンプレート画像として読めて、何かが描かれていることを確かめる
    @Test(arguments: templateIconNames)
    func templateIconIsAvailable(name: String) throws {
        let image = try #require(UIImage(named: name), "アセット \(name) が読めない")
        #expect(image.renderingMode == .alwaysTemplate, "\(name) は Render As をテンプレートにする")
        #expect(Self.hasVisiblePixels(image), "\(name) を描くと何も描かれない")
    }

    /// 多色の装飾 `route-deco` が元の色のまま読めることを確かめる
    @Test
    func originalIconIsAvailable() throws {
        let name = Self.originalIconName
        let image = try #require(UIImage(named: name), "アセット \(name) が読めない")
        #expect(image.renderingMode == .alwaysOriginal, "\(name) は多色なのでテンプレートにしない")
        #expect(Self.hasVisiblePixels(image), "\(name) を描くと何も描かれない")
    }

    /// 画像を描いて、不透明度が 0 でない画素が 1 つでもあるかを返す。
    ///
    /// SVG の `stroke="currentColor"` が解釈されないと、読めても透明な画像になるため確かめる。
    private static func hasVisiblePixels(_ image: UIImage) -> Bool {
        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else {
            return false
        }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }
}
