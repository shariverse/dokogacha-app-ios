//
//  SearchAreaPicker.swift
//  Dokogacha
//

import SwiftUI

/// S-08 の検索のエリアを選ぶ段（03 の S-08 の 6。Issue #131・#160）。地方 → 都道府県 → 市区町村を、1 段 1 行のチップで並べる。
///
/// - 見出し: 「エリア」と、今どこで絞っているかの道筋（「関東 › 東京都 › 墨田区」）。チップの行を横に送っても、ここで分かる
/// - 1 行目: 全国と 8 つの地方。地方を選ぶと、次の行が出る
/// - 2 行目: 「{地方}全体」と地方の都道府県（北海道・沖縄は地方と同じなので出さない）
/// - 3 行目: 都道府県が決まると出す。「{都道府県}全体」と「選ぶ」（シートで一覧から選ぶ。`MunicipalityPicker`）。
///   選んだ市区町村は「選ぶ」の代わりに名前で出し、押すと選び直せる
///
/// 選んでいる段のチップを塗る。どの行も「〇〇全体」を押せば一段上に戻れる（地方のチップを押し直しても、その地方全体に戻る）。
/// 文字を大きくしても切れないよう、行ごとに横にスクロールし、選んでいるチップが画面の外なら見えるところまで寄せる
struct SearchAreaPicker: View {
    private typealias Identifier = AddCandidateView.Identifier

    /// 「全体」のチップのスクロールの ID
    private static let wholeID = "whole"
    /// 「選ぶ」のチップのスクロールの ID
    private static let pickID = "pick"
    /// 見出しのピンの大きさ（チップの文字に合わせる。プロトタイプに無い）
    private static let pinSize: CGFloat = 13

    /// 検索欄・エリアと結果の状態
    let search: PlaceSearchModel

    /// 市区町村のシートを出しているか
    @State private var isPickingMunicipality = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var pinSize = SearchAreaPicker.pinSize

    var body: some View {
        let scope = search.scope
        VStack(alignment: .leading, spacing: 0) {
            header(scope)
                .padding(.bottom, DGSpacing.s4)
            areaRow(scope)
            if scope.area != .nationwide, scope.area.soloPrefecture == nil {
                prefectureRow(scope)
                    .transition(.opacity)
            }
            if let prefecture = scope.prefecture {
                municipalityRow(scope, prefecture: prefecture)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $isPickingMunicipality) {
            if let prefecture = scope.prefecture {
                MunicipalityPicker(
                    prefecture: prefecture,
                    path: Self.path(to: prefecture),
                    selected: scope.municipality,
                    municipalities: MunicipalityCatalog.bundled.municipalities(in: prefecture)
                ) { picked in
                    select(picked)
                }
            }
        }
    }

    // MARK: - 見出し

    /// 「エリア」と、今どこで絞っているかの道筋。VoiceOver では「検索するエリア」と道筋をまとめて読む
    private func header(_ scope: SearchScope) -> some View {
        let path = Self.path(of: scope)
        return HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s8) {
            HStack(spacing: DGSpacing.s4) {
                Image("ui-pin")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: pinSize, height: pinSize)
                Text("エリア")
            }
            .foregroundStyle(Color.dgTextSecondary)
            Text(verbatim: path.joined(separator: " › "))
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.dgBody(PlaceSearchChip.textSize, weight: .black, relativeTo: .caption))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("検索するエリア"))
        .accessibilityValue(Text(verbatim: path.joined(separator: "、")))
        .accessibilityIdentifier(Identifier.areaPath)
    }

    // MARK: - 行

    /// 全国と地方。都道府県・市区町村まで絞っていても、その地方を塗る
    private func areaRow(_ scope: SearchScope) -> some View {
        row(label: Text("地方"), selection: scope.area.rawValue) {
            ForEach(SearchArea.allCases) { area in
                PlaceSearchChip(title: Self.areaLabel(area), isSelected: scope.area == area) {
                    select(SearchScope(area: area))
                }
                .accessibilityHint(Text("このエリアで検索します"))
                .accessibilityIdentifier(Identifier.area(area))
                .id(area.rawValue)
            }
        }
    }

    /// 「{地方}全体」と地方の都道府県
    private func prefectureRow(_ scope: SearchScope) -> some View {
        row(label: Text("都道府県"), selection: scope.prefecture.map { String($0.code) } ?? Self.wholeID) {
            PlaceSearchChip(title: String(localized: "\(Self.areaLabel(scope.area))全体"), isSelected: scope.level == .area) {
                select(SearchScope(area: scope.area))
            }
            .accessibilityHint(Text("このエリアで検索します"))
            .accessibilityIdentifier(Identifier.prefectureWhole)
            .id(Self.wholeID)
            ForEach(scope.area.prefectures) { prefecture in
                PlaceSearchChip(title: prefecture.shortName, isSelected: scope.prefecture == prefecture) {
                    select(SearchScope(prefecture: prefecture))
                }
                // チップは「都」「府」「県」を外して短くし、VoiceOver では正式な名前で読む
                .accessibilityLabel(Text(verbatim: prefecture.name))
                .accessibilityHint(Text("このエリアで検索します"))
                .accessibilityIdentifier(Identifier.prefecture(prefecture))
                .id(String(prefecture.code))
            }
        }
    }

    /// 「{都道府県}全体」と、市区町村を選ぶチップ（選んでいれば市区町村の名前）
    private func municipalityRow(_ scope: SearchScope, prefecture: Prefecture) -> some View {
        row(label: Text("市区町村"), selection: scope.municipality == nil ? Self.wholeID : Self.pickID) {
            PlaceSearchChip(title: String(localized: "\(prefecture.name)全体"), isSelected: scope.municipality == nil) {
                select(SearchScope(prefecture: prefecture))
            }
            .accessibilityHint(Text("このエリアで検索します"))
            .accessibilityIdentifier(Identifier.municipalityWhole)
            .id(Self.wholeID)
            PlaceSearchChip(
                title: scope.municipality?.name ?? String(localized: "選ぶ"),
                isSelected: scope.municipality != nil,
                trailingSymbol: "chevron.down"
            ) {
                isPickingMunicipality = true
            }
            .accessibilityLabel(scope.municipality.map { Text(verbatim: $0.name) } ?? Text("市区町村を選ぶ"))
            .accessibilityHint(Text("\(prefecture.name)の市区町村の一覧から選びます"))
            .accessibilityIdentifier(Identifier.municipalityPick)
            .id(Self.pickID)
        }
    }

    /// チップの 1 行。横にスクロールし、選んでいるチップ（`selection` の ID）が画面の外なら、見えるところまでだけ動かす
    /// （見えていれば動かさないので、行の頭がそろったまま。押したチップは見えているので、選び直しても動かない）
    private func row(label: Text, selection: String, @ViewBuilder chips: () -> some View) -> some View {
        let chips = chips()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DGSpacing.s6) {
                    chips
                }
            }
            .scrollClipDisabled()
            .onAppear {
                proxy.scrollTo(selection)
            }
            .onChange(of: selection) { _, id in
                withAnimation(reduceMotion ? nil : DGMotion.reducedFade) {
                    proxy.scrollTo(id)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: - 操作

    /// エリアを選ぶ。出る行・消える行はフェードで切り替える（「視差効果を減らす」では動かさずに切り替える。04 の §5）
    private func select(_ scope: SearchScope) {
        withAnimation(reduceMotion ? nil : DGMotion.reducedFade) {
            search.select(scope)
        }
    }

    // MARK: - 表示名

    /// 地方の表示名（03 の S-08 の 6）
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

    /// 選んでいるエリアの表示名（いちばん下の段。「関東」「東京都」「墨田区」。北海道・沖縄は地方の名前）
    static func label(of scope: SearchScope) -> String {
        path(of: scope).last ?? areaLabel(scope.area)
    }

    /// 選んでいるエリアの道筋（「全国」「関東」「関東・東京都・墨田区」「北海道・札幌市」）
    static func path(of scope: SearchScope) -> [String] {
        let prefecturePath = scope.prefecture.map(path(to:)) ?? [areaLabel(scope.area)]
        return prefecturePath + [scope.municipality?.name].compactMap(\.self)
    }

    /// 都道府県までの道筋（「関東」「東京都」。北海道・沖縄は「北海道」だけ）
    static func path(to prefecture: Prefecture) -> [String] {
        prefecture.area.soloPrefecture == nil ? [areaLabel(prefecture.area), prefecture.name] : [areaLabel(prefecture.area)]
    }
}

#Preview("S-08 エリア（市区町村まで）") {
    let model = PlaceSearchModel(
        places: DemoPlaceSearchService(),
        areaStore: InMemorySearchAreaStore(
            scope: MunicipalityCatalog.bundled.municipality(code: "131075").flatMap(SearchScope.init(municipality:)) ?? .nationwide
        ),
        toasts: DGToastCenter()
    )
    return SearchAreaPicker(search: model)
        .padding(DGSpacing.screenX)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase)
}
