//
//  Layout.swift
//  Dokogacha
//
//  `docs/spec/design/tokens.json` の `layout` を写した、広い画面（iPad）での本文の幅と列の分け方のトークン。
//  単位は pt（`04_design_system.md` の §3・03 の §3「iPad」）。
//

import SwiftUI

/// 広い画面（iPad）での本文の幅と列の分け方（`layout`）。
///
/// 本文は最大幅の列に収めて中央に寄せる（`View.dgContentColumn(maxWidth:)`）。iPhone の画面の幅はどれも
/// `contentMaxWidth` より狭いので、最大幅を付けても見た目は変わらない。
/// 列を分けるのは横の size class が regular で、列ごとの最小の幅が取れるときだけ（iPhone は縦向き固定で常に compact）
nonisolated enum DGLayout {
    /// 1 列の画面の本文の最大幅（左右の余白 `spacing.screenX` を除く。`layout.contentMaxWidth`）
    static let contentMaxWidth: CGFloat = 600
    /// 2 列に分けた画面（ホーム・ルーム）の本文の最大幅（左右の余白を除く。`layout.wideContentMaxWidth`）
    static let wideContentMaxWidth: CGFloat = 1000
    /// 2 列に分けるときの、1 列の本文の最小の幅（`layout.columnMinWidth`）
    static let columnMinWidth: CGFloat = 320
    /// ルームを 2 列に分けたときの、左の列（ルームパネルとガチャのボタン）の本文の幅（`layout.sidePaneWidth`）
    static let sidePaneWidth: CGFloat = 360
    /// ホームを 2 列に分けたときの列のあいだ（`spacing.s24`）
    static let columnSpacing: CGFloat = DGSpacing.s24

    /// ホーム（S-02）の「進行中のルーム」と「思い出のきっぷ」を左右の 2 列に分けるか。
    /// - Parameters:
    ///   - width: 画面（ウィンドウ）の幅（左右の余白を含む）
    ///   - sizeClass: 横の size class
    static func splitsHome(width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular && width >= columnMinWidth * 2 + columnSpacing + DGSpacing.screenX * 2
    }

    /// ルーム（S-07）を、左のルームパネルと右の候補の一覧の 2 列に分けるか。
    /// - Parameters:
    ///   - width: 画面（ウィンドウ）の幅（左右の余白を含む）
    ///   - sizeClass: 横の size class
    static func splitsRoom(width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular && width >= sidePaneWidth + columnMinWidth + DGSpacing.screenX * 4
    }

    /// 列を分けた画面の、本文の列の外の左右の余白（広い画面で中央に寄せるための余り。左右の余白 `screenX` は含めない）
    /// - Parameters:
    ///   - width: 画面（ウィンドウ）の幅
    ///   - maxWidth: 本文の最大幅
    static func centeringMargin(width: CGFloat, maxWidth: CGFloat) -> CGFloat {
        max(0, (width - maxWidth - DGSpacing.screenX * 2) / 2)
    }
}

extension View {
    /// 本文を最大幅の列に収め、広い画面では中央に寄せる（03 の §3「iPad」）。
    ///
    /// 左右の余白（`DGSpacing.screenX`）を付けた後のビューに付ける。ヘッダーにも付け、戻るボタンを本文の左端にそろえる。
    /// 背景（`Color.dgBgBase`）はこの後に付けると、画面の幅いっぱいに塗られる
    /// - Parameters:
    ///   - maxWidth: 本文の最大幅（左右の余白を除く）
    ///   - alignment: 中身が列より狭いときの寄せ方（列そのものは中央に寄せる）
    func dgContentColumn(maxWidth: CGFloat = DGLayout.contentMaxWidth, alignment: Alignment = .center) -> some View {
        frame(maxWidth: maxWidth + DGSpacing.screenX * 2, alignment: alignment)
            .frame(maxWidth: .infinity)
    }
}

/// iPad の大きな画面（横・縦の size class がどちらも regular）で、スクロールの中身が画面より低いときに縦の中央に寄せる。
///
/// 中身の少ない画面（ガチャ・結果・招待・オンボーディング）が、大きな画面の上にだけ寄って下が大きく空かないようにする。
/// 中身が画面より高いときは、ふつうどおり上から並べてスクロールする（`ScrollAnchorRole.alignment` は初めのスクロールの位置を変えない）。
/// iPhone（横が compact）では何もしない。iOS 17 には寄せ方の指定（`for: .alignment`）が無いので、上に寄せたままにする
private struct DGTallScreenCentering: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.defaultScrollAnchor(centers ? .center : nil, for: .alignment)
        } else {
            content
        }
    }

    /// 縦の中央に寄せるか
    private var centers: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
}

extension View {
    /// `ScrollView` に付ける。iPad の大きな画面で、中身が画面より低いときに縦の中央に寄せる（03 の §3「iPad」）
    func dgCentersContentOnTallScreen() -> some View {
        modifier(DGTallScreenCentering())
    }
}
