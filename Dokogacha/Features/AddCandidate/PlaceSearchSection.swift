//
//  PlaceSearchSection.swift
//  Dokogacha
//

import SwiftUI

/// S-08 の「場所を探す」のタブの中身（03 の S-08 の「場所を探す」・02 の §3.1 F-10）。検索欄・エリア・クイックカテゴリ・検索結果（`DGPlaceRow`）を並べる。
///
/// 検索欄の文字と入力しているかは、S-08（`AddCandidateView`）が持つ（入力している間はバナーを出さないため）
struct PlaceSearchSection: View {
    private typealias Identifier = AddCandidateView.Identifier

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
    /// エリアの見出しのピンの大きさ（チップの文字に合わせる。プロトタイプに無い）
    private static let areaIconSize: CGFloat = 13
    /// 結果 0 件などの文言の大きさ（プロトタイプの 13）
    private static let messageSize: CGFloat = 13
    /// 読み込み中に出す行の数
    private static let placeholderRows = 3

    let model: AddCandidateModel
    /// 検索欄の文字（Model の値を直接つながない。LEARNINGS の「TextField を Model に直接つなぐ」）
    @Binding var queryText: String
    /// 検索欄に入力しているか
    var isSearchFocused: FocusState<Bool>.Binding

    @ScaledMetric(relativeTo: .body) private var searchIconSize = PlaceSearchSection.searchIconSize
    @ScaledMetric(relativeTo: .caption) private var areaIconSize = PlaceSearchSection.areaIconSize

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            searchField
            areaChips
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
            .focused(isSearchFocused)
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
        chip(
            word,
            isSelected: model.search.trimmedQuery == word,
            hint: Text("この語で検索します"),
            identifier: Identifier.quickCategory(index)
        ) {
            model.search.searchNow(word)
            queryText = word
        }
    }

    /// 検索するエリアのチップ（03 の S-08 の 6）。選んでいるエリアを塗る。クイックカテゴリと分かるよう、前に「エリア」の見出しを置く。
    /// 文字を大きくしても切れないよう、見出しごと横にスクロールする
    private var areaChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DGSpacing.s6) {
                HStack(spacing: DGSpacing.s4) {
                    Image("ui-pin")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: areaIconSize, height: areaIconSize)
                    Text("エリア")
                        .font(.dgBody(Self.chipTextSize, weight: .black, relativeTo: .caption))
                }
                .foregroundStyle(Color.dgTextSecondary)
                .accessibilityHidden(true)
                ForEach(SearchArea.allCases) { area in
                    chip(
                        Self.areaLabel(area),
                        isSelected: model.search.scope == SearchScope(area: area),
                        hint: Text("このエリアで検索します"),
                        identifier: Identifier.area(area)
                    ) {
                        model.search.select(SearchScope(area: area))
                    }
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("検索するエリア"))
    }

    /// エリアの表示名（03 の S-08 の 6）
    static func areaLabel(_ area: SearchArea) -> String {
        switch area {
        case .nationwide: String(localized: "全国")
        case .hokkaido: String(localized: "北海道")
        case .tohoku: String(localized: "東北")
        case .kanto: String(localized: "関東")
        case .chubu: String(localized: "中部")
        case .kansai: String(localized: "関西")
        case .chugokuShikoku: String(localized: "中国・四国")
        case .kyushu: String(localized: "九州")
        case .okinawa: String(localized: "沖縄")
        }
    }

    /// クイックカテゴリ・エリアのチップ 1 つ（選んでいるものは塗る）
    private func chip(
        _ title: String,
        isSelected: Bool,
        hint: Text,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.chipRadius)
        return Button(action: action) {
            Text(verbatim: title)
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
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    /// 検索の状態ごとの結果
    @ViewBuilder private var results: some View {
        switch model.search.phase {
        case .idle, .failed:
            EmptyView()
        case .searching:
            searchingPlaceholder
        case .noResults:
            noResults
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

    /// 結果 0 件の表示（03 の S-08 の 5）。地方で探したときは、地方の名前を添え、全国で探し直すボタンも出す
    /// （地方の外の場所は、地方では見つからないため）
    @ViewBuilder private var noResults: some View {
        let area = model.search.scope.area
        if area == .nationwide {
            message("見つかりませんでした")
                .accessibilityIdentifier(Identifier.noResults)
        } else {
            VStack(spacing: DGSpacing.s12) {
                messageText("\(Self.areaLabel(area))では見つかりませんでした")
                    .accessibilityIdentifier(Identifier.noResults)
                DGButton("全国で探す", kind: .secondary, fillsWidth: false) {
                    model.search.select(.nationwide)
                }
                .accessibilityIdentifier(Identifier.searchNationwide)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DGSpacing.s24)
        }
    }

    /// 中央に置く案内の文言
    private func message(_ text: LocalizedStringKey) -> some View {
        messageText(text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DGSpacing.s24)
    }

    /// 案内の文言の文字
    private func messageText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.dgBody(Self.messageSize, relativeTo: .subheadline))
            .foregroundStyle(Color.dgTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
