//
//  CreateRoomView.swift
//  Dokogacha
//

import SwiftUI

/// S-03 ルーム作成（プッシュ。F-02）。03 の S-03 のとおり、ヘッダー（戻る＋「ルームを作る」）の下に、
/// ルーム名・1人あたりの投稿数・ガチャ解禁の条件（「締切日時」のときだけ日時ピッカー）・いいねの効き方を間隔 22 で並べ、
/// 「ルームを作成」を下に固定する。
///
/// 標準のナビゲーションバーは使わない（03 の §3）。作成できたら `onCreated` で親（`MainNavigationView`）に S-04 の行き先を渡す。
/// 文字を最大にしても切れないよう、フォームは縦にスクロールする。
struct CreateRoomView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 画面
        static let screen = "createRoom.screen"
        /// ルーム名の入力欄
        static let name = "createRoom.name"
        /// 締切日時のピッカー
        static let deadline = "createRoom.deadline"
        /// 「ルームを作成」
        static let submit = "createRoom.submit"
    }

    /// 項目の見出しの文字の大きさ（本文 Bold 14。`DGTextField` のラベルと同じ）
    private static let labelSize: CGFloat = 14

    @State private var model: CreateRoomModel
    /// 作成できたときの処理（S-04 へ進む）
    private let onCreated: (InviteDestination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - onCreated: 作成できたときの処理
    init(model: CreateRoomModel, onCreated: @escaping (InviteDestination) -> Void) {
        _model = State(initialValue: model)
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("ルームを作る"), onBack: { dismiss() })
                .padding(.horizontal, DGSpacing.s4)
            ScrollView {
                form
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.top, DGSpacing.s8)
                    .padding(.bottom, DGSpacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("ルームを作成") {
                model.submitTapped()
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier(Identifier.submit)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s12)
            .padding(.bottom, DGSpacing.s14)
            .background(Color.dgBgBase)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .onChange(of: model.createdRoom) { _, destination in
            if let destination {
                onCreated(destination)
            }
        }
        // 前面に戻ったら、締切日時の範囲を今の時刻で計算し直す（裏にいた間に下限が進んでいるため）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshDeadlineRange()
            }
        }
        // 戻った・S-04 に進んだら、送っている途中の作成を止める（Task が Model を持ち続けないように）
        .onDisappear { model.cancelSubmit() }
    }

    /// 入力の項目（03 の S-03 の 1〜4。間隔 22）
    private var form: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s22) {
            DGTextField(
                label: "どんなおでかけ？",
                placeholder: "例：年末の旅行",
                text: $model.name,
                count: model.nameCount,
                limit: model.nameLimit,
                errorMessage: nameIssueMessage,
                identifier: Identifier.name
            )
            .submitLabel(.done)
            postLimitSection
            unlockRuleSection
            likeModeSection
        }
        .disabled(!model.isEditable)
    }

    /// 1人あたりの投稿数（03 の S-03 の 2）
    private var postLimitSection: some View {
        section("1人あたりの投稿数", hint: postLimitHint) {
            DGStepper(
                value: $model.postLimit,
                range: CreateRoomModel.postLimitRange,
                unit: "件まで",
                valueLabel: "1人あたりの投稿数",
                decrementLabel: "投稿数を減らす",
                incrementLabel: "投稿数を増やす"
            )
        }
    }

    /// ガチャ解禁の条件（03 の S-03 の 3）。「締切日時」のときだけ下に日時ピッカーを出す
    private var unlockRuleSection: some View {
        section("ガチャ解禁の条件", hint: "作成者はいつでも強制解禁できます") {
            DGSegmentedChoice(
                selection: $model.unlockRule,
                options: [
                    DGChoiceOption("全員OK", value: .all),
                    DGChoiceOption("過半数OK", value: .majority),
                    DGChoiceOption("締切日時", value: .deadline)
                ]
            )
            if model.showsDeadlinePicker {
                DeadlinePickerField(date: $model.deadline, range: model.deadlineRange, identifier: Identifier.deadline)
            }
        }
    }

    /// いいねの効き方（03 の S-03 の 4）。補足は選んだものに合わせて切り替える
    private var likeModeSection: some View {
        section("いいねの効き方", hint: likeModeHint) {
            DGSegmentedChoice(
                selection: $model.likeMode,
                options: [
                    DGChoiceOption("共感ブースト", value: .boost),
                    DGChoiceOption("みんな平等", value: .equal)
                ]
            )
        }
    }

    // MARK: - 部品

    /// 見出し・中身・補足を縦に並べた項目（間隔 8）
    private func section(
        _ title: LocalizedStringKey,
        hint: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DGSpacing.s8) {
            Text(title)
                .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            content()
            Text(hint)
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 投稿数の補足（03 の S-03「1〜10件。作成後は引き上げのみできます」。範囲は定数から）
    private var postLimitHint: LocalizedStringKey {
        let range = CreateRoomModel.postLimitRange
        return "\(range.lowerBound)〜\(range.upperBound)件。作成後は引き上げのみできます"
    }

    /// いいねの効き方の補足（03 の S-03 の 4）
    private var likeModeHint: LocalizedStringKey {
        switch model.likeMode {
        case .boost:
            "いいねが多い候補ほど出やすくなります（いいね0でも当たります）"
        case .equal:
            "どの候補も同じ確率で出ます"
        }
    }

    /// ルーム名の入力が正しくないときの文言（S-01 の表示名と同じ表記）
    private var nameIssueMessage: LocalizedStringKey? {
        switch model.nameIssue {
        case let .tooLong(limit):
            "\(limit)文字以内で入力してください"
        case .forbiddenCharacter:
            "使えない文字が含まれています"
        case nil:
            nil
        }
    }
}

#Preview("S-03 初期") {
    NavigationStack {
        CreateRoomView(
            model: CreateRoomModel(functions: InMemoryServer.demo(.empty), toasts: DGToastCenter())
        ) { _ in }
    }
}

#Preview("S-03 締切日時") {
    let model = CreateRoomModel(functions: InMemoryServer.demo(.empty), toasts: DGToastCenter())
    model.name = "年末の旅行"
    model.unlockRule = .deadline
    return NavigationStack {
        CreateRoomView(model: model) { _ in }
    }
}

#Preview("S-03 文字を最大") {
    NavigationStack {
        CreateRoomView(
            model: CreateRoomModel(functions: InMemoryServer.demo(.empty), toasts: DGToastCenter())
        ) { _ in }
    }
    .dynamicTypeSize(.accessibility5)
}
