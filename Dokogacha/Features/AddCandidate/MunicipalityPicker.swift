//
//  MunicipalityPicker.swift
//  Dokogacha
//

import SwiftUI

/// S-08 の市区町村を選ぶシート（03 の S-08 の 6。Issue #160）。
///
/// - 上に、どの都道府県の市区町村かの道筋（「関東 › 東京都」）と、名前・よみで絞り込む入力欄を置く（`MunicipalityFilter`）
/// - 一番上の「{都道府県}全体」で、市区町村を選ばずに都道府県全体に戻せる（絞り込んでいる間は出さない）
/// - 市区町村は、よみの五十音順に「あ行」などの見出しで分け、名前の下によみを出す（読みにくい名前を探しやすく）。選んでいる行に印を付け、開いたときにその行まで送る
/// - 選んだら閉じて、S-08 がそのエリアで検索し直す。右上の閉じる・下に引くと、選び直さずに閉じる
struct MunicipalityPicker: View {
    /// UI テストが探す ID
    enum Identifier {
        /// シート
        static let screen = "municipalityPicker.screen"
        /// 絞り込みの入力欄
        static let filter = "municipalityPicker.filter"
        /// 「{都道府県}全体」
        static let whole = "municipalityPicker.whole"
        /// 閉じるボタン
        static let close = "municipalityPicker.close"
        /// 絞り込んで 0 件のときの文言
        static let empty = "municipalityPicker.empty"

        /// 市区町村の行（団体コード）
        static func row(_ municipality: Municipality) -> String {
            "municipalityPicker.row.\(municipality.code)"
        }
    }

    /// 入力欄の高さ（S-08 の検索欄と同じ 48）
    private static let filterHeight: CGFloat = 48
    /// 入力欄の角丸（S-08 の検索欄と同じ 14）
    private static let filterRadius: CGFloat = 14
    /// 虫めがねの大きさ（S-08 の検索欄と同じ 18）
    private static let searchIconSize: CGFloat = 18
    /// 入力欄の文字の大きさ（S-08 の検索欄と同じ 16）
    private static let filterTextSize: CGFloat = 16
    /// 道筋・見出し・よみの文字の大きさ（S-08 のチップと同じ 12）
    private static let captionSize: CGFloat = 12
    /// 道筋のピンの大きさ（S-08 の「エリア」の見出しと同じ 13）
    private static let pinSize: CGFloat = 13
    /// 0 件の案内の文字の大きさ（S-08 の「見つかりませんでした」と同じ 13）
    private static let messageSize: CGFloat = 13
    /// 選んでいる印の大きさ
    private static let checkSize: CGFloat = 20

    /// 市区町村の都道府県
    let prefecture: Prefecture
    /// 都道府県までの道筋（「関東」「東京都」）
    let path: [String]
    /// 選んでいる市区町村（都道府県全体なら nil）
    let selected: Municipality?
    /// 都道府県の市区町村（よみの五十音順）
    let municipalities: [Municipality]
    /// 選んだときの処理（市区町村か、都道府県全体）
    let onSelect: (SearchScope) -> Void

    /// 絞り込みの語
    @State private var filterText: String
    /// 絞り込みの入力欄に入力しているか
    @FocusState private var isFilterFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var searchIconSize = MunicipalityPicker.searchIconSize
    @ScaledMetric(relativeTo: .caption) private var pinSize = MunicipalityPicker.pinSize
    @ScaledMetric(relativeTo: .body) private var checkSize = MunicipalityPicker.checkSize

    /// - Parameters:
    ///   - prefecture: 市区町村の都道府県
    ///   - path: 都道府県までの道筋（「関東」「東京都」）
    ///   - selected: 選んでいる市区町村（都道府県全体なら nil）
    ///   - municipalities: 都道府県の市区町村（よみの五十音順）
    ///   - initialFilter: 初めに入れておく絞り込みの語（撮影モード）
    ///   - onSelect: 選んだときの処理（市区町村か、都道府県全体）
    init(
        prefecture: Prefecture,
        path: [String],
        selected: Municipality?,
        municipalities: [Municipality],
        initialFilter: String = "",
        onSelect: @escaping (SearchScope) -> Void
    ) {
        self.prefecture = prefecture
        self.path = path
        self.selected = selected
        self.municipalities = municipalities
        self.onSelect = onSelect
        _filterText = State(initialValue: initialFilter)
    }

    /// 絞り込んだ市区町村を、五十音の行ごとにまとめたもの
    private var sections: [KanaSection] {
        MunicipalityFilter.sections(MunicipalityFilter.filter(municipalities, query: filterText))
    }

    /// 絞り込んでいるか
    private var isFiltering: Bool {
        !MunicipalityFilter.searchKey(filterText).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("市区町村を選ぶ"), onBack: nil) {
                JoinSheetCloseButton { dismiss() }
                    .accessibilityIdentifier(Identifier.close)
            }
            .padding(.leading, DGSpacing.s12)
            VStack(alignment: .leading, spacing: DGSpacing.s10) {
                pathText
                filterField
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.bottom, DGSpacing.s12)
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
    }

    /// 都道府県までの道筋（「関東 › 東京都」）
    private var pathText: some View {
        HStack(spacing: DGSpacing.s4) {
            Image("ui-pin")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: pinSize, height: pinSize)
            Text(verbatim: path.joined(separator: " › "))
                .font(.dgBody(Self.captionSize, weight: .black, relativeTo: .caption))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.dgTextSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: path.joined(separator: "、")))
    }

    /// 名前・よみで絞り込む入力欄（見た目は S-08 の検索欄と同じ）
    private var filterField: some View {
        let shape = RoundedRectangle(cornerRadius: Self.filterRadius)
        return HStack(spacing: DGSpacing.s8) {
            Image("ui-search")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: searchIconSize, height: searchIconSize)
                .foregroundStyle(Color.dgTextSecondary)
                .accessibilityHidden(true)
            TextField(
                "市区町村を絞り込む",
                text: $filterText,
                prompt: Text("名前・よみで絞り込む").foregroundStyle(Color.dgTextSecondary)
            )
            .font(.dgBody(Self.filterTextSize, weight: .bold, relativeTo: .body))
            .foregroundStyle(Color.dgInk)
            .tint(Color.dgAccentPrimary)
            .submitLabel(.done)
            .autocorrectionDisabled()
            .focused($isFilterFocused)
            .accessibilityIdentifier(Identifier.filter)
        }
        .padding(.horizontal, DGSpacing.s14)
        .padding(.vertical, DGSpacing.s8)
        .frame(minHeight: Self.filterHeight)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
    }

    /// 「全体」と、五十音の行ごとの市区町村。絞り込んで 0 件なら案内
    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DGSpacing.s16, pinnedViews: [.sectionHeaders]) {
                    if !isFiltering {
                        card {
                            row(
                                title: Text("\(prefecture.name)全体"),
                                subtitle: Text("市区町村を選ばずに探します"),
                                isSelected: selected == nil
                            ) {
                                choose(SearchScope(prefecture: prefecture))
                            }
                            .accessibilityIdentifier(Identifier.whole)
                        }
                    }
                    if sections.isEmpty {
                        emptyMessage
                    }
                    ForEach(sections) { section in
                        Section {
                            card {
                                ForEach(Array(section.municipalities.enumerated()), id: \.element.id) { index, municipality in
                                    if index > 0 {
                                        DGDashedLine()
                                    }
                                    municipalityRow(municipality)
                                }
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.bottom, DGSpacing.s24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // 選んでいる市区町村まで送る（都道府県全体なら一番上のまま）
                if let selected {
                    proxy.scrollTo(selected.code, anchor: .center)
                }
            }
        }
    }

    /// 五十音の行の見出し（「あ行」。上に留まる間も下の行が透けないよう、画面の背景で塗る）
    private func sectionHeader(_ section: KanaSection) -> some View {
        Text("\(section.row)行")
            .font(.dgBody(Self.captionSize, weight: .black, relativeTo: .caption))
            .foregroundStyle(Color.dgTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DGSpacing.s6)
            .background(Color.dgBgBase)
            .accessibilityAddTraits(.isHeader)
    }

    /// 市区町村の行（名前とよみ）
    private func municipalityRow(_ municipality: Municipality) -> some View {
        row(title: Text(verbatim: municipality.name), subtitle: Text(verbatim: municipality.kana), isSelected: selected == municipality) {
            choose(SearchScope(municipality: municipality) ?? SearchScope(prefecture: prefecture))
        }
        // VoiceOver では名前だけを読む（よみは見た目の補助）。音声コントロールでは、よみでも押せる
        .accessibilityLabel(Text(verbatim: municipality.name))
        .accessibilityInputLabels([Text(verbatim: municipality.name), Text(verbatim: municipality.kana)])
        .accessibilityIdentifier(Identifier.row(municipality))
        .id(municipality.code)
    }

    /// 押せる行（名前・補足・選んでいる印）
    private func row(title: Text, subtitle: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DGSpacing.s8) {
                VStack(alignment: .leading, spacing: DGSpacing.s4) {
                    title
                        .font(.dg(.bodyTitle))
                        .foregroundStyle(Color.dgInk)
                    subtitle
                        .font(.dgBody(Self.captionSize, relativeTo: .caption))
                        .foregroundStyle(Color.dgTextSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image("ui-check")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: checkSize, height: checkSize)
                        .foregroundStyle(Color.dgInk)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DGSpacing.cardPadding)
            .padding(.vertical, DGSpacing.s10)
            .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 白いカードに行を並べる（設定の項目のまとまりと同じ見た目）
    private func card(@ViewBuilder content: () -> some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        return VStack(spacing: 0) {
            content()
        }
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
        .clipShape(shape)
    }

    /// 絞り込んで 0 件のときの案内
    private var emptyMessage: some View {
        Text("「\(NameValidation.trimWhitespace(filterText))」に合う市区町村はありません")
            .font(.dgBody(Self.messageSize, relativeTo: .subheadline))
            .foregroundStyle(Color.dgTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DGSpacing.s24)
            .accessibilityIdentifier(Identifier.empty)
    }

    /// 選んで閉じる
    private func choose(_ scope: SearchScope) {
        onSelect(scope)
        dismiss()
    }
}

#Preview("市区町村を選ぶ") {
    let tokyo = Prefecture.code(13) ?? Prefecture.all[0]
    Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            MunicipalityPicker(
                prefecture: tokyo,
                path: SearchAreaPicker.path(to: tokyo),
                selected: MunicipalityCatalog.bundled.municipality(code: "131164"),
                municipalities: MunicipalityCatalog.bundled.municipalities(in: tokyo)
            ) { _ in }
        }
}
