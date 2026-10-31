//
//  AddCandidateView.swift
//  Dokogacha
//

import SwiftUI

/// S-08 候補を追加（プッシュ。F-10）。03 の S-08 のとおり、ヘッダー（戻る＋「行きたい場所を追加」＋右端に「n/上限」）、
/// タブ（「場所を探す」「過去のアイデア」）とタブの中身を並べる（検索欄・エリア・クイックカテゴリ・検索結果は `PlaceSearchSection`）。
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
        /// エリアを絞って結果が 0 件のときの「全国で探す」
        static let searchNationwide = "addCandidate.searchNationwide"
        /// エリアの見出しの道筋（「関東 › 東京都 › 墨田区」）
        static let areaPath = "addCandidate.areaPath"
        /// 都道府県・市区町村で結果が 0 件のときの「{一段上}で探す」
        static let searchParent = "addCandidate.searchParent"
        /// 都道府県の行の「{地方}全体」
        static let prefectureWhole = "addCandidate.prefecture.all"
        /// 市区町村の行の「{都道府県}全体」
        static let municipalityWhole = "addCandidate.municipality.all"
        /// 市区町村の行の「選ぶ」（選んでいれば市区町村の名前）
        static let municipalityPick = "addCandidate.municipality.pick"
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

        /// エリアのチップ（全国・地方）
        static func area(_ area: SearchArea) -> String {
            "addCandidate.area.\(area.rawValue)"
        }

        /// 都道府県のチップ（都道府県コード）
        static func prefecture(_ prefecture: Prefecture) -> String {
            "addCandidate.prefecture.\(prefecture.code)"
        }
    }

    /// ヘッダーの「n/上限」の文字の大きさ（プロトタイプの 13）
    private static let postCountSize: CGFloat = 13

    @State private var model: AddCandidateModel
    /// 検索欄の文字（Model の値を直接つながない。LEARNINGS の「TextField を Model に直接つなぐ」）
    @State private var queryText = ""
    /// 検索欄に入力しているか（キーボードを出している間はバナーを出さない）
    @FocusState private var isSearchFocused: Bool

    @Environment(\.dismiss) private var dismiss

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
            .dgContentColumn()
            .disabled(model.locksNavigation)
            DGTabSwitch(
                selection: $model.tab,
                options: [
                    DGChoiceOption("場所を探す", value: AddCandidateModel.Tab.search),
                    DGChoiceOption("過去のアイデア", value: AddCandidateModel.Tab.pastIdeas)
                ]
            )
            .padding(.horizontal, DGSpacing.screenX)
            .dgContentColumn()
            .padding(.top, DGSpacing.s4)
            .padding(.bottom, DGSpacing.s12)
            ScrollView {
                Group {
                    switch model.tab {
                    case .search:
                        PlaceSearchSection(model: model, queryText: $queryText, isSearchFocused: $isSearchFocused)
                    case .pastIdeas:
                        PastIdeasSection(model: model)
                    }
                }
                .padding(.horizontal, DGSpacing.screenX)
                .dgContentColumn()
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
