//
//  OnboardingView.swift
//  Dokogacha
//

import SwiftUI

/// S-01 オンボーディング（表示名の入力。全画面）。03 の S-01 の上から順に、ロゴ・説明 3 行・表示名の入力欄・「はじめる」を並べる。
///
/// ヘッダー（戻るボタン）は置かない（最初の画面で戻る先が無い）。文字を最大にしても切れないよう、上の部分はスクロールし、
/// 「はじめる」は画面の下（キーボードが出たらその上）に固定する。
struct OnboardingView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 表示名の入力欄
        static let displayName = "onboarding.displayName"
        /// 「はじめる」
        static let start = "onboarding.start"
    }

    /// 説明の 1 行（アイコンと文言）
    private struct Feature: Identifiable {
        let icon: String
        let text: LocalizedStringKey
        var id: String { icon }
    }

    /// 説明 3 行（03 の S-01 の 2）
    private static let features = [
        Feature(icon: "ui-pin", text: "行きたい場所を持ち寄る"),
        Feature(icon: "ui-heart", text: "いいねで出やすさアップ"),
        Feature(icon: "ui-check", text: "揃ったらガチャで決定！")
    ]

    /// 説明のアイコンの一辺
    private static let featureIconSize: CGFloat = 22

    @State private var model: OnboardingModel
    @ScaledMetric(relativeTo: .body) private var featureIconSize = OnboardingView.featureIconSize

    /// - Parameter model: 画面の状態（最初の 1 回だけ使う）
    init(model: OnboardingModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpacing.s24) {
                DGLogo()
                featureList
                DGTextField(
                    label: "表示名",
                    placeholder: "例：ゆい",
                    text: $model.displayName,
                    count: model.characterCount,
                    limit: model.characterLimit,
                    hint: "ルームのメンバーに表示されます",
                    errorMessage: issueMessage,
                    identifier: Identifier.displayName
                )
                .submitLabel(.done)
                .onSubmit { model.submitTapped() }
                .disabled(model.isSubmitting || model.didRegister)
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s24)
            .padding(.bottom, DGSpacing.s16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("はじめる") {
                model.submitTapped()
            }
            .disabled(!model.canSubmit)
            .accessibilityIdentifier(Identifier.start)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s12)
            .padding(.bottom, DGSpacing.s14)
            .background(Color.dgBgBase)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
    }

    /// 説明 3 行を白いカードに並べる
    private var featureList: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            ForEach(Self.features) { feature in
                HStack(spacing: DGSpacing.s10) {
                    Image(feature.icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: featureIconSize, height: featureIconSize)
                        .foregroundStyle(Color.dgAccentText)
                        .accessibilityHidden(true)
                    Text(feature.text)
                        .font(.dg(.bodyTitle))
                        .foregroundStyle(Color.dgInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DGSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: DGRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: DGRadius.lg)
                .strokeBorder(Color.dgInk, lineWidth: DGBorder.regular)
        }
    }

    /// 入力が正しくないときの文言
    private var issueMessage: LocalizedStringKey? {
        switch model.inputIssue {
        case let .tooLong(limit):
            "\(limit)文字以内で入力してください"
        case .forbiddenCharacter:
            "使えない文字が含まれています"
        case nil:
            nil
        }
    }
}

#Preview("S-01 空") {
    OnboardingView(model: OnboardingModel(auth: InMemoryServer.demo(.firstLaunch), toasts: DGToastCenter()))
}

#Preview("S-01 文字を最大") {
    OnboardingView(model: OnboardingModel(auth: InMemoryServer.demo(.firstLaunch), toasts: DGToastCenter()))
        .dynamicTypeSize(.accessibility5)
}
