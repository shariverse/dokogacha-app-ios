//
//  PostCandidateView.swift
//  Dokogacha
//

import MapKit
import SwiftUI

/// S-09 投稿の確認（シート・ハーフ。F-10）。03 の S-09 のとおり、場所名・エリア・カテゴリタイル・小さな地図（1 ピン・高さ 140）、
/// カテゴリ（自動判定済み・タップで 9 種から選び直し）、「ひとこと（任意）」（40 文字まで）、「参考URL（任意）」、「候補に追加」を並べる。
///
/// 状態は S-08 と同じ `AddCandidateModel` を見る（S-08 が `draft` をシートの行き先にして出す）。
/// 送っている途中は、下へのスワイプ・閉じるボタンで閉じさせない（`interactiveDismissDisabled`）。
/// トーストはシートの中に重ねる（`AddCandidateModel.sheetToasts`）。
struct PostCandidateView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// シート
        static let screen = "postCandidate.screen"
        /// 閉じるボタン
        static let close = "postCandidate.close"
        /// 場所名
        static let placeName = "postCandidate.placeName"
        /// カテゴリ（押すと選び直し）
        static let category = "postCandidate.category"
        /// ひとことの入力欄
        static let note = "postCandidate.note"
        /// 参考 URL の入力欄
        static let url = "postCandidate.url"
        /// 「候補に追加」
        static let submit = "postCandidate.submit"

        /// カテゴリの選択肢
        static func categoryOption(_ category: PlaceCategory) -> String {
            "postCandidate.category.\(category.rawValue)"
        }
    }

    /// 地図の高さ（03 の S-09「高さ140pt」）
    private static let mapHeight: CGFloat = 140
    /// 地図に映す範囲（度。場所の周り 1km 前後）
    private static let mapSpan: CLLocationDegrees = 0.01
    /// 閉じるアイコンの大きさ
    private static let closeIconSize: CGFloat = 20
    /// 場所名の大きさ
    private static let placeNameSize: CGFloat = 18
    /// カテゴリの選択肢の最小の幅
    private static let categoryOptionMinWidth: CGFloat = 96
    /// UI テスト（`-uiTesting`）では地図を出さない（地図のタイルを読みにネットワークへ出ないように。場所は文字で出ている）
    private static let showsMap = !LaunchContext.current.isUITesting

    /// 画面の状態（S-08 と同じもの）
    @Bindable var model: AddCandidateModel

    /// カテゴリの選択肢を開いているか
    @State private var isPickingCategory = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var closeIconSize = PostCandidateView.closeIconSize

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("投稿の確認"), onBack: nil) {
                closeButton
            }
            .padding(.leading, DGSpacing.s12)
            .dgContentColumn()
            ScrollView {
                if let draft = model.draft {
                    form(draft)
                        .padding(.horizontal, DGSpacing.screenX)
                        .dgContentColumn()
                        .padding(.bottom, DGSpacing.s16)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("候補に追加") {
                model.submitTapped()
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier(Identifier.submit)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s12)
            .padding(.bottom, DGSpacing.s14)
            .dgContentColumn()
            .background(Color.dgBgBase)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        // 送っている途中は閉じさせない（送った結果を見せる相手がいなくなるため）
        .lockNavigation(while: model.locksNavigation)
        .alert(
            Text("すでに候補にあります。いいねしますか？"),
            isPresented: duplicatePromptOnSheet,
            presenting: model.duplicatePrompt
        ) { prompt in
            DuplicatePromptActions(model: model, prompt: prompt)
        }
        .dgToast(model.sheetToasts)
    }

    /// シートの上で重複の確認を出すか
    private var duplicatePromptOnSheet: Binding<Bool> {
        Binding(
            get: { model.duplicatePrompt != nil && model.draft != nil },
            set: { presented in
                if !presented {
                    model.dismissDuplicatePrompt()
                }
            }
        )
    }

    /// 右上の閉じるボタン（アイコンだけなので VoiceOver のラベル「閉じる」を付ける）
    private var closeButton: some View {
        Button {
            model.closeDraft()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: closeIconSize))
                .fontWeight(.bold)
                .foregroundStyle(Color.dgInk)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .disabled(model.locksNavigation)
        .accessibilityLabel(Text("閉じる"))
        .accessibilityIdentifier(Identifier.close)
    }

    /// 場所・地図・カテゴリ・ひとこと・参考 URL
    private func form(_ draft: AddCandidateModel.Draft) -> some View {
        VStack(alignment: .leading, spacing: DGSpacing.s16) {
            placeSummary(draft)
            if Self.showsMap {
                map(draft.place.place)
            }
            categorySection(draft.category)
            DGTextField(
                label: "ひとこと（任意）",
                placeholder: "例：天空のペンギン見たい！",
                text: $model.note,
                count: model.noteCheck.characterCount,
                limit: model.noteCheck.limit,
                errorMessage: noteIssueMessage,
                identifier: Identifier.note
            )
            DGTextField(
                label: "参考URL（任意）",
                placeholder: "https://",
                text: $model.url,
                count: 0,
                limit: 0,
                errorMessage: model.urlInput == .invalid ? "http:// か https:// で始まるURLを入力してください" : nil,
                identifier: Identifier.url,
                showsCount: false
            )
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .disabled(model.isSubmitting || model.isLiking)
    }

    /// 場所名・エリア・カテゴリタイル
    private func placeSummary(_ draft: AddCandidateModel.Draft) -> some View {
        HStack(spacing: DGSpacing.s12) {
            DGCategoryTile(category: DGCategoryStyle.of(draft.category), size: .large)
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                Text(verbatim: draft.place.place.name)
                    .font(.dgBody(Self.placeNameSize, weight: .black, relativeTo: .headline))
                    .foregroundStyle(Color.dgInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.placeName)
                if !draft.place.place.area.isEmpty {
                    Text(verbatim: draft.place.place.area)
                        .font(.dg(.bodyCaption))
                        .foregroundStyle(Color.dgTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// 小さな地図（1 ピン・動かせない）。場所は文字で読むので、VoiceOver では読まない
    private func map(_ place: Place) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return Map(
            initialPosition: .region(
                MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: Self.mapSpan, longitudeDelta: Self.mapSpan))
            ),
            interactionModes: []
        ) {
            Marker(place.name, coordinate: coordinate)
                .tint(Color.dgAccentPrimary)
        }
        .frame(height: Self.mapHeight)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
        .accessibilityHidden(true)
    }

    // MARK: - カテゴリ

    /// カテゴリ（自動判定の値。押すと 9 種の選択肢を開く）
    private func categorySection(_ category: PlaceCategory) -> some View {
        let style = DGCategoryStyle.of(category)
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return VStack(alignment: .leading, spacing: DGSpacing.s6) {
            Text("カテゴリ")
                .font(.dgBody(DGTypeScale.bodyRegular.size, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.dgInk)
                .accessibilityHidden(true)
            Button {
                isPickingCategory.toggle()
            } label: {
                HStack(spacing: DGSpacing.s10) {
                    DGCategoryTile(category: style)
                    Text(style.label)
                        .font(.dg(.bodyTitle))
                        .foregroundStyle(Color.dgInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(isPickingCategory ? "閉じる" : "変更")
                        .font(.dgBody(DGTypeScale.bodyCaption.size, weight: .black, relativeTo: .caption))
                        .foregroundStyle(Color.dgTextSecondary)
                }
                .padding(.horizontal, DGSpacing.s12)
                .padding(.vertical, DGSpacing.s8)
                .frame(minHeight: DGMetrics.minTapTarget)
                .background(Color.dgSurfaceCard, in: shape)
                .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
                .contentShape(shape)
            }
            .buttonStyle(.dgBare)
            .accessibilityLabel(Text("カテゴリ"))
            .accessibilityValue(Text(style.label))
            .accessibilityHint(Text("カテゴリを選び直します"))
            .accessibilityIdentifier(Identifier.category)
            if isPickingCategory {
                categoryOptions(selected: category)
            }
        }
    }

    /// 9 種のカテゴリの選択肢（押すと選んで閉じる）
    private func categoryOptions(selected: PlaceCategory) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Self.categoryOptionMinWidth), spacing: DGSpacing.s8)],
            spacing: DGSpacing.s8
        ) {
            ForEach(PlaceCategory.allCases, id: \.self) { category in
                categoryOption(category, isSelected: category == selected)
            }
        }
    }

    /// カテゴリの選択肢 1 つ（タイル＋名前。選んでいるものは墨色の縁と淡い黄色）
    private func categoryOption(_ category: PlaceCategory, isSelected: Bool) -> some View {
        let style = DGCategoryStyle.of(category)
        let shape = RoundedRectangle(cornerRadius: DGRadius.sm)
        return Button {
            model.selectCategory(category)
            isPickingCategory = false
        } label: {
            VStack(spacing: DGSpacing.s4) {
                DGCategoryTile(category: style)
                Text(style.label)
                    .font(.dgBody(DGTypeScale.bodyCaption.size, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(Color.dgInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DGSpacing.s6)
            .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget)
            .background(isSelected ? Color.dgSurfaceHighlight : Color.dgSurfaceCard, in: shape)
            .overlay { shape.strokeBorder(isSelected ? Color.dgInk : Color.dgLineDashed, lineWidth: DGBorder.regular) }
            .contentShape(shape)
        }
        .buttonStyle(.dgBare)
        .accessibilityLabel(Text(style.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(Identifier.categoryOption(category))
    }

    /// ひとことのエラー（空・正しいときは nil）
    private var noteIssueMessage: LocalizedStringKey? {
        switch model.noteCheck.issue {
        case let .tooLong(limit):
            "\(limit)文字以内で入力してください"
        case .forbiddenCharacter:
            "使えない文字が含まれています"
        case nil:
            nil
        }
    }
}
