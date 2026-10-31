//
//  RoomLayout.swift
//  Dokogacha
//

import SwiftUI

/// S-07 ルームの画面の組み方。iPhone と iPad の狭いウィンドウでは 1 列、iPad の広い画面では 2 列にする（03 の §3「iPad」）。
///
/// - 1 列: ヘッダー・スクロールする中身（ルームパネルと候補）・下部に固定するボタンと広告。本文は最大幅の列に収めて中央に寄せる
/// - 2 列: 左の列にルームパネルと下部のボタン・広告、右の列に候補を置き、それぞれでスクロールする。
///   候補を見ている間も、準備OKの状態と「ガチャを回す」が見える。右の列のスクロールは画面の右端まで広げ
///   （余白でもスクロールでき、スクロールバーが画面の端に出る）、中身だけを本文の列にそろえる
///
/// どちらにするかは、横の size class と画面（ウィンドウ）の幅で決める（`DGLayout.splitsRoom`。iPhone は常に 1 列）
struct RoomLayout<Header: View, Content: View, SidePane: View, MainPane: View, BottomBar: View>: View {
    /// 2 列に分けてよいか（ルームが見つからないときの案内は 1 列で出す）
    let allowsSplit: Bool
    /// ヘッダー
    let header: Header
    /// 1 列のときのスクロールする中身
    let content: Content
    /// 2 列のときの左の列（ルームパネル）
    let sidePane: SidePane
    /// 2 列のときの右の列（候補）
    let mainPane: MainPane
    /// 下部に固定するボタンと広告（2 列のときは左の列の下）
    let bottomBar: BottomBar

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// - Parameters:
    ///   - allowsSplit: 2 列に分けてよいか
    ///   - header: ヘッダー
    ///   - content: 1 列のときのスクロールする中身
    ///   - sidePane: 2 列のときの左の列
    ///   - mainPane: 2 列のときの右の列
    ///   - bottomBar: 下部に固定するボタンと広告
    init(
        allowsSplit: Bool,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder sidePane: () -> SidePane,
        @ViewBuilder mainPane: () -> MainPane,
        @ViewBuilder bottomBar: () -> BottomBar
    ) {
        self.allowsSplit = allowsSplit
        self.header = header()
        self.content = content()
        self.sidePane = sidePane()
        self.mainPane = mainPane()
        self.bottomBar = bottomBar()
    }

    var body: some View {
        GeometryReader { proxy in
            if allowsSplit, DGLayout.splitsRoom(width: proxy.size.width, sizeClass: horizontalSizeClass) {
                splitLayout(width: proxy.size.width)
            } else {
                singleColumnLayout
            }
        }
    }

    /// 1 列
    private var singleColumnLayout: some View {
        VStack(spacing: 0) {
            header
                .dgContentColumn()
            ScrollView {
                content
                    .padding(.horizontal, DGSpacing.screenX)
                    .dgContentColumn()
                    .padding(.top, DGSpacing.s4)
                    .padding(.bottom, DGSpacing.s16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    /// 2 列
    /// - Parameter width: 画面（ウィンドウ）の幅
    private func splitLayout(width: CGFloat) -> some View {
        let margin = DGLayout.centeringMargin(width: width, maxWidth: DGLayout.wideContentMaxWidth)
        return VStack(spacing: 0) {
            header
                .dgContentColumn(maxWidth: DGLayout.wideContentMaxWidth)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    sidePane
                        .padding(.horizontal, DGSpacing.screenX)
                        .padding(.top, DGSpacing.s4)
                        .padding(.bottom, DGSpacing.s16)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
                .frame(width: DGLayout.sidePaneWidth + DGSpacing.screenX * 2)
                ScrollView {
                    mainPane
                        .padding(.leading, DGSpacing.screenX)
                        .padding(.trailing, DGSpacing.screenX + margin)
                        .padding(.top, DGSpacing.s4)
                        .padding(.bottom, DGSpacing.s16)
                }
            }
            .padding(.leading, margin)
        }
    }
}

/// S-07 の最初のルームが届くまでの、部品の形を保った読み込み中の表示（03 の §3）
enum RoomLoadingPlaceholder {
    /// 1 列のとき（ルームパネルと候補カード）
    static var content: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s14) {
            panel
            card
        }
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }

    /// 2 列のときの左の列（ルームパネル）
    static var sidePane: some View {
        panel
            .redacted(reason: .placeholder)
            .disabled(true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("読み込み中"))
    }

    /// 2 列のときの右の列（候補カード。「読み込み中」は左の列で 1 回だけ読む）
    static var mainPane: some View {
        card
            .redacted(reason: .placeholder)
            .disabled(true)
            .accessibilityHidden(true)
    }

    /// 読み込み中のルームパネル（中身は空）
    private static var panel: some View {
        RoomPanel(
            capsuleCount: 0,
            readyCount: 0,
            memberCount: 0,
            members: [],
            myPostCount: 0,
            postLimit: 0,
            likeMode: .boost
        ) {}
    }

    /// 読み込み中の候補カード（中身は空）
    private static var card: some View {
        DGCandidateCard(
            name: String(localized: "読み込み中"),
            meta: String(localized: "読み込み中"),
            category: .town,
            author: .departed,
            elapsed: "",
            likeStatus: .locked,
            likers: [],
            level: .flat,
            percent: 0,
            maxPercent: 0
        ) {}
    }
}
