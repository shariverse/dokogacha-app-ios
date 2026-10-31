//
//  LayoutTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import SwiftUI
import Testing

/// iPad の本文の幅と列の分け方（`DGLayout`。03 の §3「iPad」）を、端末とウィンドウの幅ごとに確かめる
struct LayoutTests {
    /// iPhone（横の size class が compact）は、どの幅でも列を分けない（iPhone の見た目を変えない）
    @Test(arguments: [320, 375, 393, 402, 440] as [CGFloat])
    func iPhoneNeverSplits(width: CGFloat) {
        #expect(!DGLayout.splitsHome(width: width, sizeClass: .compact))
        #expect(!DGLayout.splitsRoom(width: width, sizeClass: .compact))
    }

    /// iPhone のどの幅も本文の最大幅より狭いので、最大幅で中央に寄せても見た目は変わらない
    @Test
    func iPhoneWidthsAreNarrowerThanContentColumn() {
        let widestIPhone: CGFloat = 440
        #expect(widestIPhone <= DGLayout.contentMaxWidth + DGSpacing.screenX * 2)
    }

    /// iPad を全画面で使うとき（縦・横。mini の縦の 744 を含む）は、ホームもルームも 2 列にする
    @Test(arguments: [744, 820, 834, 1032, 1133, 1180, 1210, 1376] as [CGFloat])
    func iPadFullScreenSplits(width: CGFloat) {
        #expect(DGLayout.splitsHome(width: width, sizeClass: .regular))
        #expect(DGLayout.splitsRoom(width: width, sizeClass: .regular))
    }

    /// regular でも、列の最小の幅が取れない狭いウィンドウでは分けない（ホームは 688、ルームは 744 から分ける）
    @Test
    func splitsFromThresholdWidth() {
        #expect(!DGLayout.splitsHome(width: 687, sizeClass: .regular))
        #expect(DGLayout.splitsHome(width: 688, sizeClass: .regular))
        #expect(!DGLayout.splitsRoom(width: 743, sizeClass: .regular))
        #expect(DGLayout.splitsRoom(width: 744, sizeClass: .regular))
    }

    /// size class が分からないときは分けない
    @Test
    func unknownSizeClassDoesNotSplit() {
        #expect(!DGLayout.splitsHome(width: 1376, sizeClass: nil))
        #expect(!DGLayout.splitsRoom(width: 1376, sizeClass: nil))
    }

    /// 列を分けた画面の、列の外の余白は、画面の幅から本文の列（左右の余白を含む）を引いた残りの半分。列より狭ければ 0
    @Test
    func centeringMargin() {
        #expect(DGLayout.centeringMargin(width: 1376, maxWidth: DGLayout.wideContentMaxWidth) == 172)
        #expect(DGLayout.centeringMargin(width: 1032, maxWidth: DGLayout.wideContentMaxWidth) == 0)
        #expect(DGLayout.centeringMargin(width: 834, maxWidth: DGLayout.wideContentMaxWidth) == 0)
    }
}
