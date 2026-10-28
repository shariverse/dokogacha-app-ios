//
//  JoinByCodeView.swift
//  Dokogacha
//

import SwiftUI

/// S-05 招待コードで参加（シートの根元。F-04）。03 の S-05 のとおり、6 文字のコードの入力欄と「参加する」を置く。
///
/// ヘッダーは「招待コードで参加」と右上の閉じるボタン（シートなので戻るボタンは無い）。
/// 入力欄は招待コードの見た目（S-04 と同じ見出しフォント・字間）で、打つと英大文字・`ABC-123` の形になる。
/// F-04 の AC のエラーは入力欄の下に朱色の文言で出す（縁も朱色にし、色だけで伝えない）。
struct JoinByCodeView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 画面
        static let screen = "joinByCode.screen"
        /// 招待コードの入力欄
        static let code = "joinByCode.code"
        /// 入力欄の下のエラー
        static let error = "joinByCode.error"
        /// 「参加する」
        static let submit = "joinByCode.submit"
    }

    /// 「招待コード」のラベルの文字の大きさ（本文 Bold 14。`DGTextField` のラベルと同じ）
    private static let labelSize: CGFloat = 14
    /// 入力する招待コードの文字の大きさ（見出しフォント。S-04 の 36 より小さくし、文字を大きくしても 1 行に収める）
    private static let codeSize: CGFloat = 28
    /// 入力欄の上下の余白
    private static let fieldVerticalPadding: CGFloat = DGSpacing.s14
    /// 入力欄の文字を大きくする上限（7 文字を 1 行に収めるため。これより大きい設定でもこの大きさで止める）
    private static let codeMaxDynamicType: DynamicTypeSize = .accessibility1

    @State private var model: JoinByCodeModel
    /// 入力欄の文字列。打った・貼り付けた直後の値を受け、Model で正規化した値を入れ直す。
    ///
    /// Model の値に直接つなぐと、Model が値を書き換えても（`ABC-123` の形にしても）入力欄の表示が変わらないため、
    /// 画面の `@State` を挟み、`onChange` で入れ直す
    @State private var input: String
    /// 閉じるボタンを押したときの処理（シートを閉じる）
    private let onClose: () -> Void
    /// 行き先が決まったときの処理（S-06 を出す・ルームを開く）
    private let onOutcome: (JoinByCodeModel.Outcome) -> Void

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - onClose: 閉じるボタンを押したときの処理
    ///   - onOutcome: 行き先が決まったときの処理
    init(
        model: JoinByCodeModel,
        onClose: @escaping () -> Void,
        onOutcome: @escaping (JoinByCodeModel.Outcome) -> Void
    ) {
        _model = State(initialValue: model)
        _input = State(initialValue: model.codeText)
        self.onClose = onClose
        self.onOutcome = onOutcome
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("招待コードで参加"), onBack: nil) {
                JoinSheetCloseButton(action: onClose)
            }
            .padding(.leading, DGSpacing.s12)
            ScrollView {
                codeSection
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.top, DGSpacing.s8)
                    .padding(.bottom, DGSpacing.s16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("参加する") {
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
        .onChange(of: model.outcome) { _, outcome in
            if let outcome {
                model.clearOutcome()
                onOutcome(outcome)
            }
        }
        // 閉じた・S-06 に進んだら、確かめている途中の確認を止める（Task が Model を持ち続けないように）
        .onDisappear { model.cancelSubmit() }
    }

    /// 「招待コード」のラベル・入力欄・エラー
    private var codeSection: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s8) {
            Text("招待コード")
                .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
                // 入力欄の名前として読むので、ここでは読まない
                .accessibilityHidden(true)
            codeField
            if let errorMessage = model.errorMessage {
                Text(verbatim: errorMessage)
                    .font(.dgBody(DGTypeScale.bodyCaption.size, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(Color.dgAccentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.error)
            }
        }
    }

    /// 招待コードの入力欄（英大文字・ハイフンは自動。貼り付けた文字も同じく直す）
    private var codeField: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        let hasError = model.errorMessage != nil
        return TextField(
            "招待コード",
            text: $input,
            prompt: Text(verbatim: InviteCode.formatted("ABC123")).foregroundStyle(Color.dgTextSecondary)
        )
        .font(.dgDisplay(Self.codeSize, relativeTo: .title2))
        .tracking(DGTracking.points(DGTracking.inviteCode, fontSize: Self.codeSize))
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.dgInk)
        .tint(Color.dgAccentPrimary)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .keyboardType(.asciiCapable)
        .submitLabel(.join)
        .onSubmit { model.submitTapped() }
        .onChange(of: input) { _, newValue in
            model.codeText = newValue
            if input != model.codeText {
                input = model.codeText
            }
        }
        .disabled(!model.isEditable)
        .dynamicTypeSize(...Self.codeMaxDynamicType)
        .padding(.horizontal, DGSpacing.s14)
        .padding(.vertical, Self.fieldVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(hasError ? Color.dgAccentText : Color.dgInk, lineWidth: DGBorder.strong) }
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(Identifier.code)
    }

    /// VoiceOver で値の後に読む文言（入力した文字数・エラー）
    private var accessibilityHint: Text {
        let count = Text("\(InviteCode.length)文字中\(model.enteredCount)文字")
        guard let errorMessage = model.errorMessage else {
            return count
        }
        return count + Text(verbatim: "、\(errorMessage)")
    }
}

#Preview("S-05 空") {
    NavigationStack {
        JoinByCodeView(
            model: JoinByCodeModel(functions: InMemoryServer.demo(.joinable), toasts: DGToastCenter()),
            onClose: {},
            onOutcome: { _ in }
        )
    }
}

#Preview("S-05 入力した状態") {
    let model = JoinByCodeModel(functions: InMemoryServer.demo(.joinable), toasts: DGToastCenter())
    model.codeText = DemoScenario.joinableInviteCode
    return NavigationStack {
        JoinByCodeView(model: model, onClose: {}, onOutcome: { _ in })
    }
}

#Preview("S-05 文字を最大") {
    let model = JoinByCodeModel(functions: InMemoryServer.demo(.joinable), toasts: DGToastCenter())
    model.codeText = DemoScenario.joinableInviteCode
    return NavigationStack {
        JoinByCodeView(model: model, onClose: {}, onOutcome: { _ in })
    }
    .dynamicTypeSize(.accessibility5)
}
