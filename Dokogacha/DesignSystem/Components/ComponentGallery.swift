//
//  ComponentGallery.swift
//  Dokogacha
//
//  部品の見本。Xcode Preview と PR のスクリーンショットで `docs/spec/04_design_system.md` の §4 と見比べるためだけに使い、画面からは使わない。
//  Stg・Release のアプリに入れないよう、Debug でだけコンパイルする。
//

#if DEBUG
import SwiftUI

/// 部品を状態ごとに並べた見本の画面。
///
/// 基本の部品（Button・StatusChip・Avatar・TabSwitch・SegmentedChoice・Stepper・Toast・PlaceRow）を 3 つのページに、
/// カードと表示の部品（CandidateCard・ProbabilityMeter・RoomTagCard・DestinationBoard・TicketStub・Stamp・AdFreeNotice）を 2 つのページに分け、
/// 上の選択肢（基本の部品とカード・表示の 2 段）で切り替える。部品の名前は翻訳の対象ではないので `Text(verbatim:)` で出す。
struct ComponentGallery: View {
    /// 見本のページ
    enum Page: Hashable, CaseIterable {
        /// Button・StatusChip
        case buttons
        /// TabSwitch・SegmentedChoice・Stepper・Avatar
        case choices
        /// PlaceRow・CategoryTile・Toast
        case rows
        /// CandidateCard・ProbabilityMeter・LikeButton・LikeRow（`CardComponentsPage`）
        case cards
        /// RoomTagCard・DestinationBoard・TicketStub・Stamp・AdFreeNotice（`DisplayComponentsPage`）
        case displays
    }

    /// 選んでいるページ
    @State private var page: Page
    /// TabSwitch の見本の選択
    @State private var tab = 0
    /// SegmentedChoice（3 択）の見本の選択
    @State private var condition = 0
    /// SegmentedChoice（2 択）の見本の選択
    @State private var mode = 0
    /// Stepper の見本の値
    @State private var limit = 3
    /// Stepper（下限）の見本の値
    @State private var lowerLimit = 1
    /// Toast の見本の窓口
    @State private var toastCenter = DGToastCenter()

    /// - Parameter page: 最初に開くページ
    init(page: Page = .buttons) {
        _page = State(initialValue: page)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpacing.s16) {
                DGSegmentedChoice(
                    selection: $page,
                    options: [
                        DGChoiceOption("ボタン・チップ", value: .buttons),
                        DGChoiceOption("選択・入力", value: .choices),
                        DGChoiceOption("行・トースト", value: .rows)
                    ]
                )
                DGSegmentedChoice(
                    selection: $page,
                    options: [
                        DGChoiceOption("カード", value: .cards),
                        DGChoiceOption("表示", value: .displays)
                    ]
                )
                switch page {
                case .buttons: buttonsPage
                case .choices: choicesPage
                case .rows: rowsPage
                case .cards: CardComponentsPage()
                case .displays: DisplayComponentsPage()
                }
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.vertical, DGSpacing.s16)
        }
        .background(Color.dgBgBase)
        .dgToast(toastCenter)
    }

    // MARK: ページ

    /// Button・StatusChip のページ
    private var buttonsPage: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            sectionTitle("Button")
            DGButton("ルームを作る", icon: "ui-plus") {}
            DGButton("招待コードで参加", kind: .secondary) {}
            HStack(spacing: DGSpacing.s8) {
                DGButton("準備OK", kind: .yellow) {}
                DGButton("候補を追加", icon: "ui-plus", kind: .yellow) {}
            }
            DGButton("ルームへ進む", kind: .dark) {}
            DGButton("引き直しを提案（過半数の賛成で1回まで）", kind: .dashed) {}
            sectionTitle("Button 無効")
            DGButton("準備OKが揃うと回せます") {}
                .disabled(true)
            HStack(spacing: DGSpacing.s8) {
                DGButton("候補を追加", kind: .yellow) {}
                    .disabled(true)
                DGButton("引き直しは使用済みです", kind: .dashed) {}
                    .disabled(true)
            }
            sectionTitle("StatusChip")
            HStack(spacing: DGSpacing.s8) {
                ForEach(DGStatusChip.Status.allCases, id: \.self) { status in
                    DGStatusChip(status: status)
                }
            }
        }
    }

    /// TabSwitch・SegmentedChoice・Stepper・Avatar のページ
    private var choicesPage: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            sectionTitle("TabSwitch")
            DGTabSwitch(
                selection: $tab,
                options: [DGChoiceOption("場所を探す", value: 0), DGChoiceOption("過去のアイデア", value: 1)]
            )
            sectionTitle("SegmentedChoice")
            DGSegmentedChoice(
                selection: $condition,
                options: [
                    DGChoiceOption("全員OK", value: 0),
                    DGChoiceOption("過半数OK", value: 1),
                    DGChoiceOption("締切日時", value: 2)
                ]
            )
            DGSegmentedChoice(
                selection: $mode,
                options: [DGChoiceOption("共感ブースト", value: 0), DGChoiceOption("みんな平等", value: 1)]
            )
            sectionTitle("Stepper")
            DGStepper(
                value: $limit,
                range: 1...10,
                unit: "件まで",
                valueLabel: "1人あたりの投稿数",
                decrementLabel: "投稿数を減らす",
                incrementLabel: "投稿数を増やす"
            )
            DGStepper(
                value: $lowerLimit,
                range: 1...10,
                unit: "件まで",
                valueLabel: "1人あたりの投稿数",
                decrementLabel: "投稿数を減らす",
                incrementLabel: "投稿数を増やす"
            )
            sectionTitle("Avatar")
            HStack(spacing: DGSpacing.s8) {
                DGAvatar(name: "ゆい", color: .dgAvatar(at: 0), readiness: .ready)
                DGAvatar(name: "けんた", color: .dgAvatar(at: 1), readiness: .ready)
                DGAvatar(name: "みさき", color: .dgAvatar(at: 2), readiness: .notReady)
                DGAvatar(name: "そら", color: .dgAvatar(at: 3), readiness: .notReady)
            }
            HStack(spacing: DGSpacing.s16) {
                HStack(spacing: DGSpacing.s4) {
                    ForEach(0..<4) { index in
                        DGAvatar(name: "ゆい", color: .dgAvatar(at: index), size: .medium, readiness: index < 2 ? .ready : .notReady)
                    }
                }
                HStack(spacing: -DGSpacing.s6) {
                    ForEach(0..<3) { index in
                        DGAvatar(name: "みさき", color: .dgAvatar(at: index + 4), size: .small, ringColor: .dgSurfaceCard)
                    }
                }
                .padding(DGSpacing.s6)
                .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: DGRadius.sm))
            }
        }
    }

    /// PlaceRow・CategoryTile・Toast のページ
    private var rowsPage: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            sectionTitle("PlaceRow")
            DGPlaceRow(name: "すみだ水族館", meta: "東京・墨田区 · 水族館", category: .aquarium, actionTitle: "追加") {}
            DGPlaceRow(name: "高尾山", meta: "東京・八王子市 · 自然", category: .nature, actionTitle: "追加済み", isActionEnabled: false) {}
            DGPlaceRow(name: "横浜中華街", meta: "神奈川・横浜市 · グルメ", category: .food, actionTitle: "上限", isActionEnabled: false) {}
            DGPlaceRow(
                name: "江の島",
                meta: "神奈川・藤沢市 · 海 · 前回 3いいね",
                category: .sea,
                badge: "前回惜しかった",
                actionTitle: "持ち込む"
            ) {}
            sectionTitle("CategoryTile")
            HStack(spacing: DGSpacing.s6) {
                ForEach(Self.categories.prefix(5).indices, id: \.self) { index in
                    DGCategoryTile(category: Self.categories[index])
                }
                ForEach(Self.categories.prefix(2).indices, id: \.self) { index in
                    DGCategoryTile(category: Self.categories[index], size: .large)
                }
            }
            HStack(spacing: DGSpacing.s6) {
                ForEach(Self.categories.indices.dropFirst(5), id: \.self) { index in
                    DGCategoryTile(category: Self.categories[index])
                }
            }
            sectionTitle("Toast")
            DGToast("候補に追加しました")
                .frame(maxWidth: .infinity)
            DGButton("トーストを出す", kind: .secondary) {
                toastCenter.show("通信できませんでした")
            }
        }
    }

    // MARK: 部品

    /// カテゴリタイルの見本に並べるカテゴリ（9 種）
    private static let categories: [DGCategoryStyle] = [.aquarium, .nature, .art, .food, .activity, .park, .town, .shrine, .sea]

    /// セクションの見出し（部品の名前）
    private func sectionTitle(_ name: String) -> some View {
        Text(verbatim: name)
            .font(.dg(.displaySection))
            .foregroundStyle(Color.dgInk)
            .padding(.top, DGSpacing.s4)
    }
}

#Preview("ボタン・チップ") {
    ComponentGallery(page: .buttons)
}

#Preview("選択・入力") {
    ComponentGallery(page: .choices)
}

#Preview("行・トースト") {
    ComponentGallery(page: .rows)
}
#endif
