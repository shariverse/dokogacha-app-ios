//
//  HomeView.swift
//  Dokogacha
//

import SwiftUI

/// S-02 ホーム（`NavigationStack` の根元）。03 の S-02 の上から順に、ロゴエリア（装飾と設定の歯車）・進行中のルーム・
/// 思い出のきっぷを縦にスクロールで並べ、下に「＋ ルームを作る」「招待コードで参加」を固定する。
///
/// 標準のナビゲーションバーは使わない（03 の §3）。画面の行き先は `navigate` で親（`MainNavigationView`）に渡す。
/// バナー広告（03 の S-02 の 5・F-50）はボタンの下に置く（`BannerAdSlot`。ボタンと重ならない）。
struct HomeView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// ホームの画面
        static let screen = "home.screen"
        /// 設定の歯車
        static let settings = "home.settings"
        /// 「＋ ルームを作る」
        static let createRoom = "home.createRoom"
        /// 「招待コードで参加」
        static let joinByCode = "home.joinByCode"
        /// 進行中のルームの空の表示
        static let roomsEmpty = "home.rooms.empty"
        /// 思い出のきっぷの空の表示
        static let memoriesEmpty = "home.memories.empty"

        /// 進行中のルームのカード
        static func room(_ roomID: String) -> String {
            "home.room.\(roomID)"
        }
    }

    /// 右上の装飾（`route-deco.svg`）の大きさ（プロトタイプの 150×74）
    private static let decorationSize = CGSize(width: 150, height: 74)
    /// 装飾を上にはみ出させる量（プロトタイプの `top: -8px`）
    private static let decorationOverhang: CGFloat = 8
    /// 歯車の大きさ
    private static let settingsIconSize: CGFloat = 22
    /// セクション見出しの大きさ（03 の S-02「見出し16pt」）
    private static let sectionTitleSize: CGFloat = 16
    /// 空の表示の点線（`DGButton` の `dashed` と同じ刻み）
    private static let emptyDash: [CGFloat] = [6, 4]

    @State private var model: HomeModel
    /// 行き先を開く（親の `NavigationStack` に積む・シートで出す）
    private let navigate: (AppRoute) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var settingsIconSize = HomeView.settingsIconSize

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - navigate: 行き先を開く処理
    init(model: HomeModel, navigate: @escaping (AppRoute) -> Void) {
        _model = State(initialValue: model)
        self.navigate = navigate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpacing.s24) {
                logoArea
                roomsSection
                memoriesSection
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s24)
            .padding(.bottom, DGSpacing.s16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                bottomButtons
                // ホームの広告は、自分が買ったかだけで決める（F-51。ルームは渡さない）
                BannerAdSlot(screen: .home)
            }
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .task {
            await model.observe()
        }
    }

    // MARK: - ロゴエリア

    /// ロゴ・サブタイトル・右上の装飾・右上端の設定の歯車（03 の S-02 の 1）
    private var logoArea: some View {
        DGLogo()
            .frame(maxWidth: .infinity, alignment: .leading)
            // 文字を大きくしてもロゴが歯車の下に潜らないよう、歯車の幅を空ける
            .padding(.trailing, DGMetrics.minTapTarget)
            .padding(.top, DGSpacing.s6)
            .background(alignment: .topTrailing) {
                // 文字を大きくするとロゴと重なって読みにくくなるので、装飾は出さない
                if !dynamicTypeSize.isAccessibilitySize {
                    Image("route-deco")
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.decorationSize.width, height: Self.decorationSize.height)
                        .padding(.trailing, DGMetrics.minTapTarget)
                        .offset(y: -Self.decorationOverhang)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                settingsButton
            }
    }

    /// 設定の歯車（44×44。S-15 へ）
    private var settingsButton: some View {
        Button {
            navigate(.settings)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: settingsIconSize))
                .fontWeight(.bold)
                .foregroundStyle(Color.dgInk)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityLabel(Text("設定"))
        .accessibilityIdentifier(Identifier.settings)
    }

    // MARK: - 進行中のルーム

    /// 進行中のルーム（03 の S-02 の 2）
    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            sectionTitle("進行中のルーム")
            switch model.roomsState {
            case .loading:
                loadingCard
            case .loaded:
                if model.isEmpty {
                    emptyMessage("まだルームがありません。ルームを作って友だちを招待しよう")
                        .accessibilityIdentifier(Identifier.roomsEmpty)
                } else {
                    VStack(spacing: DGSpacing.s16) {
                        ForEach(model.cards) { card in
                            roomCard(card)
                        }
                    }
                }
            }
        }
    }

    /// ルームのカード。押すとルーム画面（S-07）へ
    private func roomCard(_ card: HomeRoomCard) -> some View {
        DGRoomTagCard(
            status: DGStatusChip.Status(card.status),
            roomName: card.name,
            capsuleCount: card.capsuleCount,
            members: card.members.map { member in
                DGRoomTagCard.Member(
                    id: member.id,
                    name: member.name,
                    color: member.avatarColorIndex.map(Color.dgAvatar(at:)) ?? Color.dgAvatarNotReadyBg,
                    isReady: member.isReady
                )
            }
        ) {
            navigate(.room(id: card.id))
        }
        .accessibilityIdentifier(Identifier.room(card.id))
    }

    /// 最初の一覧が届くまでの、カードの形を保った読み込み中の表示（03 の §3）
    private var loadingCard: some View {
        DGRoomTagCard(
            status: .open,
            roomName: String(localized: "読み込み中"),
            capsuleCount: 0,
            members: []
        ) {}
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }

    // MARK: - 思い出のきっぷ

    /// 思い出のきっぷ（03 の S-02 の 3）。`closed` のルームを新しい順に TicketStub で並べる（`HomeMemoryTickets`）。0 件なら空の表示
    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            sectionTitle("思い出のきっぷ")
            if model.isMemoriesEmpty {
                emptyMessage("まだ思い出のきっぷはありません。行き先が決まったルームがここに残ります")
                    .accessibilityIdentifier(Identifier.memoriesEmpty)
            } else {
                HomeMemoryTickets(model: model, navigate: navigate)
            }
        }
    }

    // MARK: - 部品

    /// セクションの見出し（見出し 16）
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.dgDisplay(Self.sectionTitleSize, relativeTo: .headline))
            .foregroundStyle(Color.dgInk)
            .accessibilityAddTraits(.isHeader)
    }

    /// 空の表示（点線の枠に補足の文言）
    private func emptyMessage(_ text: LocalizedStringKey) -> some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return Text(text)
            .font(.dg(.bodyRegular))
            .foregroundStyle(Color.dgTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DGSpacing.s16)
            .overlay {
                shape.strokeBorder(
                    Color.dgLineDashedStrong,
                    style: StrokeStyle(lineWidth: DGBorder.regular, dash: Self.emptyDash)
                )
            }
    }

    /// 下部に固定するボタン（03 の S-02 の 4）
    private var bottomButtons: some View {
        VStack(spacing: DGSpacing.s10) {
            DGButton("ルームを作る", icon: "ui-plus") {
                navigate(.createRoom)
            }
            .accessibilityIdentifier(Identifier.createRoom)
            DGButton("招待コードで参加", kind: .secondary) {
                navigate(.joinByCode)
            }
            .accessibilityIdentifier(Identifier.joinByCode)
        }
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.vertical, DGSpacing.s12)
        .background(Color.dgBgBase)
    }
}

#Preview("S-02 ルームあり") {
    HomeView(
        model: HomeModel(userID: DemoScenario.myUserID, repository: InMemoryServer.demo(.severalRooms), toasts: DGToastCenter())
    ) { _ in }
}

#Preview("S-02 空") {
    HomeView(
        model: HomeModel(userID: DemoScenario.myUserID, repository: InMemoryServer.demo(.empty), toasts: DGToastCenter())
    ) { _ in }
}

#Preview("S-02 文字を最大") {
    HomeView(
        model: HomeModel(userID: DemoScenario.myUserID, repository: InMemoryServer.demo(.oneRoom), toasts: DGToastCenter())
    ) { _ in }
    .dynamicTypeSize(.accessibility5)
}
