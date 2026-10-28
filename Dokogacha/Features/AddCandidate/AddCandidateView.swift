//
//  AddCandidateView.swift
//  Dokogacha
//

import SwiftUI

/// S-08 候補を追加（プッシュ。F-10）。03 の S-08 のとおり、ヘッダー（戻る＋「行きたい場所を追加」＋右端に「n/上限」）、
/// タブ（「場所を探す」「過去のアイデア」）、検索欄・クイックカテゴリ・検索結果（`DGPlaceRow`）を並べる。
///
/// 「追加」で S-09 投稿の確認をシート（ハーフ。03 の §1）で出す。ほかの人が同じ場所を投稿していれば、
/// S-09 を出さずに「すでに候補にあります。いいねしますか？」を出す（02 の F-10）。
/// 追加できた・いいねしたら S-07 に戻る（S-09 から戻るときは、シートが閉じ終わってから S-08 を外す）。
/// 「過去のアイデア」の中身は `PastIdeasSection`（F-13。「持ち込む」も同じ S-09 を出す）。
/// バナー広告（F-50）は下部に置く（`BannerAdSlot`）。検索欄に入力している間（キーボードを出している間）は、キーボードの上に広告が浮いて
/// 検索結果の「追加」の隣に来ないよう出さない。
struct AddCandidateView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 画面
        static let screen = "addCandidate.screen"
        /// ヘッダーの「n/上限」
        static let postCount = "addCandidate.postCount"
        /// 検索欄
        static let searchField = "addCandidate.search"
        /// 結果 0 件の表示
        static let noResults = "addCandidate.noResults"
        /// 「過去のアイデア」の 0 件の表示
        static let pastIdeas = "addCandidate.pastIdeas"

        /// 検索結果の行
        static func place(_ placeID: String) -> String {
            "addCandidate.place.\(placeID)"
        }

        /// 検索結果の行の「追加」ボタン
        static func add(_ placeID: String) -> String {
            "addCandidate.place.\(placeID).add"
        }

        /// クイックカテゴリ（並びの位置）
        static func quickCategory(_ index: Int) -> String {
            "addCandidate.quick.\(index)"
        }
    }

    /// 検索欄の高さ（03 の S-08「高さ48pt」）
    private static let searchFieldHeight: CGFloat = 48
    /// 検索欄の角丸（プロトタイプの 14）
    private static let searchFieldRadius: CGFloat = 14
    /// 虫めがねの大きさ（プロトタイプの 18）
    private static let searchIconSize: CGFloat = 18
    /// 検索欄の文字の大きさ（プロトタイプの 16）
    private static let searchTextSize: CGFloat = 16
    /// クイックカテゴリのチップの見た目の高さ（プロトタイプの 34。タップ領域は上下を広げて 44）
    private static let chipHeight: CGFloat = 34
    /// クイックカテゴリのチップの角丸（プロトタイプの 10）
    private static let chipRadius: CGFloat = 10
    /// クイックカテゴリの文字の大きさ（プロトタイプの 12）
    private static let chipTextSize: CGFloat = 12
    /// ヘッダーの「n/上限」の文字の大きさ（プロトタイプの 13）
    private static let postCountSize: CGFloat = 13
    /// 結果 0 件などの文言の大きさ（プロトタイプの 13）
    private static let messageSize: CGFloat = 13
    /// 読み込み中に出す行の数
    private static let placeholderRows = 3

    @State private var model: AddCandidateModel
    /// 検索欄の文字（Model の値を直接つながない。LEARNINGS の「TextField を Model に直接つなぐ」）
    @State private var queryText = ""
    /// 検索欄に入力しているか（キーボードを出している間はバナーを出さない）
    @FocusState private var isSearchFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var searchIconSize = AddCandidateView.searchIconSize

    /// - Parameter model: 画面の状態（最初の 1 回だけ使う）
    init(model: AddCandidateModel) {
        _model = State(initialValue: model)
        _queryText = State(initialValue: model.search.query)
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("行きたい場所を追加"), onBack: { dismiss() }, trailing: {
                postCount
            })
            .disabled(model.locksNavigation)
            DGTabSwitch(
                selection: $model.tab,
                options: [
                    DGChoiceOption("場所を探す", value: AddCandidateModel.Tab.search),
                    DGChoiceOption("過去のアイデア", value: AddCandidateModel.Tab.pastIdeas)
                ]
            )
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s4)
            .padding(.bottom, DGSpacing.s12)
            ScrollView {
                Group {
                    switch model.tab {
                    case .search:
                        searchContent
                    case .pastIdeas:
                        PastIdeasSection(model: model)
                    }
                }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.bottom, DGSpacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isSearchFocused {
                BannerAdSlot(screen: .addCandidate, room: model.room)
            }
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .task {
            await model.observe()
        }
        .onChange(of: queryText) { _, text in
            model.search.updateQuery(text)
        }
        .onChange(of: model.finish) { _, finish in
            if finish == .fromList {
                dismiss()
            }
        }
        .sheet(item: $model.draft, onDismiss: sheetDismissed) { _ in
            PostCandidateView(model: model)
                .offlineBanner()
        }
        .alert(
            Text("すでに候補にあります。いいねしますか？"),
            isPresented: duplicatePromptOnList,
            presenting: model.duplicatePrompt
        ) { prompt in
            DuplicatePromptActions(model: model, prompt: prompt)
        }
        // 戻ったら、待っている検索・送っている途中の追加といいねを止める（Task が Model を持ち続けないように）
        // 重複の確認からいいねを送っている途中は、端からのスワイプでも戻らせない
        .lockNavigation(while: model.locksNavigation)
        .onDisappear { model.cancelTasks() }
    }

    /// S-09 のシートが閉じた。S-09 から追加した・いいねしたときは、シートが閉じ終わってから S-07 に戻る
    private func sheetDismissed() {
        if model.finish == .fromSheet {
            dismiss()
        }
    }

    /// S-08 の上で重複の確認を出すか（S-09 を出しているときはシートの中で出す）
    private var duplicatePromptOnList: Binding<Bool> {
        Binding(
            get: { model.duplicatePrompt != nil && model.draft == nil },
            set: { presented in
                if !presented {
                    model.dismissDuplicatePrompt()
                }
            }
        )
    }

    /// ヘッダーの右端の「n/上限」（ルームが届くまでは出さない）
    @ViewBuilder private var postCount: some View {
        if model.room != nil {
            Text(verbatim: "\(model.myPostCount)/\(model.postLimit)")
                .font(.dgBody(Self.postCountSize, weight: .black, relativeTo: .subheadline))
                .foregroundStyle(Color.dgInk)
                .monospacedDigit()
                .fixedSize()
                .padding(.trailing, DGSpacing.s12)
                .accessibilityLabel(Text("あなたの投稿 \(model.myPostCount)/\(model.postLimit)件"))
                .accessibilityIdentifier(Identifier.postCount)
        }
    }

    // MARK: - 場所を探す

    /// 検索欄・クイックカテゴリ・結果
    private var searchContent: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            searchField
            quickCategories
            results
        }
    }

    /// 検索欄（虫めがね＋入力。03 の S-08 の 1）
    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: Self.searchFieldRadius)
        return HStack(spacing: DGSpacing.s8) {
            Image("ui-search")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: searchIconSize, height: searchIconSize)
                .foregroundStyle(Color.dgTextSecondary)
                .accessibilityHidden(true)
            TextField(
                "場所を検索",
                text: $queryText,
                prompt: Text("水族館、高尾山 など").foregroundStyle(Color.dgTextSecondary)
            )
            .font(.dgBody(Self.searchTextSize, weight: .bold, relativeTo: .body))
            .foregroundStyle(Color.dgInk)
            .tint(Color.dgAccentPrimary)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onSubmit {
                model.search.searchNow(queryText)
            }
            .focused($isSearchFocused)
            .accessibilityIdentifier(Identifier.searchField)
        }
        .padding(.horizontal, DGSpacing.s14)
        .padding(.vertical, DGSpacing.s8)
        .frame(minHeight: Self.searchFieldHeight)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
    }

    /// クイックカテゴリのチップ（03 の S-08 の 2）。文字を大きくしても切れないよう、横にスクロールする
    private var quickCategories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpacing.s6) {
                ForEach(Array(PlaceSearchModel.quickCategories.enumerated()), id: \.offset) { index, resource in
                    quickCategoryChip(String(localized: resource), index: index)
                }
            }
        }
        .scrollClipDisabled()
    }

    /// クイックカテゴリのチップ 1 つ。押すとその語を検索欄に入れて検索する。いまの語と同じなら塗る
    private func quickCategoryChip(_ word: String, index: Int) -> some View {
        let isSelected = model.search.trimmedQuery == word
        let shape = RoundedRectangle(cornerRadius: Self.chipRadius)
        return Button {
            model.search.searchNow(word)
            queryText = word
        } label: {
            Text(verbatim: word)
                .font(.dgBody(Self.chipTextSize, weight: .black, relativeTo: .caption))
                .foregroundStyle(isSelected ? Color.dgTextOnAccent : Color.dgInk)
                .padding(.horizontal, DGSpacing.s12)
                .frame(minHeight: Self.chipHeight)
                .background(isSelected ? Color.dgInk : Color.dgSurfaceCard, in: shape)
                .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
                // 見た目の 34 の上下を広げて、タップ領域を 44 にする
                .padding(.vertical, (DGMetrics.minTapTarget - Self.chipHeight) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("この語で検索します"))
        .accessibilityIdentifier(Identifier.quickCategory(index))
    }

    /// 検索の状態ごとの結果
    @ViewBuilder private var results: some View {
        switch model.search.phase {
        case .idle, .failed:
            EmptyView()
        case .searching:
            searchingPlaceholder
        case .noResults:
            message("見つかりませんでした")
                .accessibilityIdentifier(Identifier.noResults)
        case let .results(places):
            VStack(spacing: DGSpacing.s10) {
                ForEach(places) { place in
                    placeRow(place)
                }
            }
        }
    }

    /// 検索結果の行（03 の S-08 の 3）。「追加」「追加済み」「上限」
    private func placeRow(_ place: SearchedPlace) -> some View {
        let style = DGCategoryStyle.of(place.category)
        let availability = model.availability(of: place)
        let categoryLabel = String(localized: style.label)
        return DGPlaceRow(
            name: place.place.name,
            meta: place.place.area.isEmpty ? categoryLabel : "\(place.place.area) · \(categoryLabel)",
            category: style,
            actionTitle: Self.actionTitle(availability),
            isActionEnabled: availability.isEnabled,
            actionHint: availability.isEnabled ? Text("\(place.place.name)を候補に追加します") : nil,
            actionIdentifier: Identifier.add(place.id)
        ) {
            model.addTapped(place)
        }
        .accessibilityIdentifier(Identifier.place(place.id))
    }

    /// 行のボタンの文言
    private static func actionTitle(_ availability: PlaceAddAvailability) -> LocalizedStringKey {
        switch availability {
        case .addable, .duplicate, .unavailable:
            "追加"
        case .added:
            "追加済み"
        case .limitReached:
            "上限"
        }
    }

    /// 検索している途中の、行の形を保った表示（03 の §3）
    private var searchingPlaceholder: some View {
        VStack(spacing: DGSpacing.s10) {
            ForEach(0..<Self.placeholderRows, id: \.self) { _ in
                DGPlaceRow(
                    name: String(localized: "読み込み中"),
                    meta: String(localized: "読み込み中"),
                    category: .town,
                    actionTitle: "追加",
                    isActionEnabled: false
                ) {}
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("検索しています"))
    }

    /// 中央に置く案内の文言
    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.dgBody(Self.messageSize, relativeTo: .subheadline))
            .foregroundStyle(Color.dgTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DGSpacing.s24)
    }
}

/// 重複の確認（「すでに候補にあります。いいねしますか？」）のボタン。S-08 とシートの S-09 で同じものを使う
struct DuplicatePromptActions: View {
    /// 画面の状態
    let model: AddCandidateModel
    /// 出している確認
    let prompt: AddCandidateModel.DuplicatePrompt

    var body: some View {
        Button("いいねする") {
            model.likeDuplicateTapped(prompt)
        }
        Button("キャンセル", role: .cancel) {
            model.dismissDuplicatePrompt()
        }
    }
}

#Preview("S-08 検索") {
    let server = InMemoryServer.demo(.roomWithCandidates)
    NavigationStack {
        AddCandidateView(
            model: AddCandidateModel(
                roomID: DemoScenario.roomID,
                userID: DemoScenario.myUserID,
                repository: server,
                functions: server,
                places: DemoPlaceSearchService(),
                toasts: DGToastCenter()
            )
        )
    }
}
