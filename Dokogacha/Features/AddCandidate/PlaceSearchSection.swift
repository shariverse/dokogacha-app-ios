//
//  PlaceSearchSection.swift
//  Dokogacha
//

import SwiftUI

/// S-08 の「場所を探す」のタブの中身（03 の S-08 の「場所を探す」・02 の §3.1 F-10）。検索欄・エリア（`SearchAreaPicker`）・クイックカテゴリ・
/// 検索結果（`DGPlaceRow`）を並べる。
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

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            searchField
            SearchAreaPicker(search: model.search)
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
        PlaceSearchChip(title: word, isSelected: model.search.trimmedQuery == word) {
            model.search.searchNow(word)
            queryText = word
        }
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
        .accessibilityLabel(Text("\(SearchAreaPicker.label(of: model.search.scope))で検索しています"))
    }

    /// 結果 0 件の表示（03 の S-08 の 5）。エリアを絞っているときは、エリアの名前を添え、一段上（地方・都道府県）と全国で探し直すボタンも出す
    /// （エリアの外の場所は、そのエリアでは見つからないため）
    @ViewBuilder private var noResults: some View {
        let scope = model.search.scope
        if let parent = scope.parent {
            VStack(spacing: DGSpacing.s12) {
                messageText("\(SearchAreaPicker.label(of: scope))では見つかりませんでした")
                    .accessibilityIdentifier(Identifier.noResults)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DGSpacing.s8) {
                        retryButtons(parent: parent)
                    }
                    VStack(spacing: DGSpacing.s8) {
                        retryButtons(parent: parent)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DGSpacing.s24)
        } else {
            message("見つかりませんでした")
                .accessibilityIdentifier(Identifier.noResults)
        }
    }

    /// 0 件のときに探し直すボタン（一段上が全国でなければ「{一段上}で探す」、続けて「全国で探す」）
    @ViewBuilder private func retryButtons(parent: SearchScope) -> some View {
        if parent != .nationwide {
            DGButton("\(SearchAreaPicker.label(of: parent))で探す", kind: .secondary, fillsWidth: false) {
                model.search.select(parent)
            }
            .accessibilityIdentifier(Identifier.searchParent)
        }
        DGButton("全国で探す", kind: .secondary, fillsWidth: false) {
            model.search.select(.nationwide)
        }
        .accessibilityIdentifier(Identifier.searchNationwide)
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
