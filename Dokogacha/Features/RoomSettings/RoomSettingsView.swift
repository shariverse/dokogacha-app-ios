//
//  RoomSettingsView.swift
//  Dokogacha
//

import SwiftUI

/// S-12 ルーム設定（シート。作成者だけ）。03 の S-12 のとおり、ルーム名・投稿数（今の値より少なくは選べない）・
/// 解禁の条件（`open` のときだけ変えられる。「締切日時」なら日時ピッカー）・いいねの効き方を並べ、「保存」を下に固定する（02 の F-03）。
///
/// 入力の部品と文言は S-03 と同じ（`DGTextField`・`DGStepper`・`DGSegmentedChoice`・`DeadlinePickerField`）。
/// 状態で変えられない項目は今の設定のまま無効にし、理由を補足に出す。作成者以外・終了したルームでは、すべて無効にして理由を上に出す。
/// 「ルームを終了する」（03 の S-12）は `closeRoom`（F-44）のタスクで足す。
///
/// 標準のナビゲーションバーは使わず、ヘッダー（タイトルと右端の閉じる）を置く（03 の §3）。トーストはシートの中に重ねる。
/// 保存を送っている間は、閉じるボタンと下スワイプで閉じられないようにする。保存できたら `onSaved` で親に知らせる（親がシートを閉じる）。
struct RoomSettingsView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// ルーム設定の画面
        static let screen = "roomSettings.screen"
        /// ルーム名の入力欄
        static let name = "roomSettings.name"
        /// 締切日時のピッカー
        static let deadline = "roomSettings.deadline"
        /// 作成者以外・終了したルームの案内
        static let lockNotice = "roomSettings.lockNotice"
        /// 「保存」
        static let save = "roomSettings.save"
        /// 閉じるボタン
        static let close = "roomSettings.close"
    }

    /// 項目の見出しの文字の大きさ（本文 Bold 14。S-03 と同じ）
    private static let labelSize: CGFloat = 14

    @State private var model: RoomSettingsModel
    @State private var toasts: DGToastCenter
    /// 保存できたときの処理（シートを閉じる）
    private let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - toasts: 失敗を出すトーストの窓口（`model` に渡したもの。シートの根元に重ねる）
    ///   - onSaved: 保存できたときの処理
    init(model: RoomSettingsModel, toasts: DGToastCenter, onSaved: @escaping () -> Void) {
        _model = State(initialValue: model)
        _toasts = State(initialValue: toasts)
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.top, DGSpacing.s8)
                    .padding(.bottom, DGSpacing.s16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("保存") {
                model.saveTapped()
            }
            .disabled(!model.canSave)
            .accessibilityIdentifier(Identifier.save)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s12)
            .padding(.bottom, DGSpacing.s14)
            .background(Color.dgBgBase)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .dgToast(toasts)
        // 送っている間は、下スワイプで閉じさせない（S-09・S-10 と同じ）
        .lockNavigation(while: model.locksNavigation)
        .task {
            await model.observe()
        }
        // 前面に戻ったら、締切日時の範囲を今の時刻で計算し直す（S-03 と同じ）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshDeadlineRange()
            }
        }
        // ルームが無くなった・自分が外されたら、シートを閉じる
        .onChange(of: model.shouldClose, initial: true) { _, shouldClose in
            if shouldClose {
                dismiss()
            }
        }
        .onChange(of: model.didSave) { _, didSave in
            if didSave {
                onSaved()
            }
        }
        // 閉じたら、送っている途中の保存を止める（Task が Model を持ち続けないように）
        .onDisappear { model.cancelSave() }
    }

    // MARK: - ヘッダー

    /// タイトルと、右端の閉じるボタン
    private var header: some View {
        DGHeader(Text("ルーム設定"), onBack: nil) {
            JoinSheetCloseButton { dismiss() }
                .disabled(model.locksNavigation)
                .accessibilityIdentifier(Identifier.close)
        }
        .padding(.leading, DGSpacing.s12)
    }

    // MARK: - 中身

    /// ルームが届くまでは読み込み中の形（03 の §3）、届いたら入力の項目（間隔 22。S-03 と同じ）
    private var content: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s22) {
            if let lock = model.formLock {
                lockNotice(lock)
            }
            DGTextField(
                label: "ルーム名",
                placeholder: "例：年末の旅行",
                text: $model.name,
                count: model.nameCheck.characterCount,
                limit: model.nameCheck.limit,
                errorMessage: nameIssueMessage,
                identifier: Identifier.name
            )
            .submitLabel(.done)
            .disabled(!model.isNameEditable)
            postLimitSection
            unlockRuleSection
            likeModeSection
        }
        .redacted(reason: model.isLoaded ? [] : .placeholder)
        .disabled(!model.isLoaded)
    }

    /// 作成者以外・終了したルームの案内（どの項目も変えられない理由）
    private func lockNotice(_ lock: RoomSettingsModel.LockReason) -> some View {
        Text(lockMessage(lock))
            .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(Color.dgAccentText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(Identifier.lockNotice)
    }

    /// 1人あたりの投稿数（今の値より少なくは選べない）
    private var postLimitSection: some View {
        section("1人あたりの投稿数", hint: postLimitHint) {
            DGStepper(
                value: $model.postLimit,
                range: model.postLimitChoices,
                unit: "件まで",
                valueLabel: "1人あたりの投稿数",
                decrementLabel: "投稿数を減らす",
                incrementLabel: "投稿数を増やす"
            )
            .disabled(!model.isPostLimitEditable)
        }
    }

    /// ガチャ解禁の条件（`open` のときだけ変えられる）。「締切日時」のときだけ下に日時ピッカーを出す
    private var unlockRuleSection: some View {
        section("ガチャ解禁の条件", hint: unlockRuleHint) {
            Group {
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
            .disabled(!model.isUnlockRuleEditable)
        }
    }

    /// いいねの効き方（`open`・`unlocked` のときだけ変えられる）
    private var likeModeSection: some View {
        section("いいねの効き方", hint: likeModeHint) {
            DGSegmentedChoice(
                selection: $model.likeMode,
                options: [
                    DGChoiceOption("共感ブースト", value: .boost),
                    DGChoiceOption("みんな平等", value: .equal)
                ]
            )
            .disabled(!model.isLikeModeEditable)
        }
    }

    // MARK: - 部品

    /// 見出し・中身・補足を縦に並べた項目（間隔 8。S-03 と同じ）
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

    // MARK: - 文言

    /// どの項目も変えられない理由の文言
    private func lockMessage(_ lock: RoomSettingsModel.LockReason) -> LocalizedStringKey {
        switch lock {
        case .notOwner:
            "ルーム設定は作成者だけが変更できます"
        case .closed:
            "このルームは終了しています"
        case .status:
            "今の状態では変更できません"
        }
    }

    /// 投稿数の補足（F-03「引き上げのみ可」）
    private var postLimitHint: LocalizedStringKey {
        "引き上げのみできます（今は\(model.currentPostLimit)件まで）"
    }

    /// 解禁の条件の補足（状態で変えられないときは、その理由）
    private var unlockRuleHint: LocalizedStringKey {
        model.unlockRuleLock == .status ? "解禁の条件は候補募集中のときだけ変更できます" : "作成者はいつでも強制解禁できます"
    }

    /// いいねの効き方の補足（状態で変えられないときは、その理由。変えられるときは S-03 と同じく選択に応じて切り替える）
    private var likeModeHint: LocalizedStringKey {
        if model.likeModeLock == .status {
            return "行き先が決まった後は、いいねの効き方を変更できません"
        }
        switch model.likeMode {
        case .boost:
            return "いいねが多い候補ほど出やすくなります（いいね0でも当たります）"
        case .equal:
            return "どの候補も同じ確率で出ます"
        }
    }

    /// ルーム名の入力が正しくないときの文言（S-03 と同じ表記）
    private var nameIssueMessage: LocalizedStringKey? {
        switch model.nameCheck.issue {
        case let .tooLong(limit):
            "\(limit)文字以内で入力してください"
        case .forbiddenCharacter:
            "使えない文字が含まれています"
        case nil:
            nil
        }
    }
}

#Preview("S-12 作成者") {
    let toasts = DGToastCenter()
    let server = InMemoryServer.demo(.roomWithCandidates)
    return Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            RoomSettingsView(
                model: RoomSettingsModel(
                    roomID: DemoScenario.roomID,
                    userID: DemoScenario.myUserID,
                    repository: server,
                    functions: server,
                    toasts: toasts
                ),
                toasts: toasts
            ) {}
        }
}

#Preview("S-12 解禁済み・文字を最大") {
    let toasts = DGToastCenter()
    let server = InMemoryServer.demo(.severalRooms)
    return Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            RoomSettingsView(
                model: RoomSettingsModel(
                    roomID: DemoScenario.unlockedRoomID,
                    userID: DemoScenario.myUserID,
                    repository: server,
                    functions: server,
                    toasts: toasts
                ),
                toasts: toasts
            ) {}
            .dynamicTypeSize(.accessibility5)
        }
}
