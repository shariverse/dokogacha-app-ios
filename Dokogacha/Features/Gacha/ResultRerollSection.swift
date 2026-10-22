//
//  ResultRerollSection.swift
//  Dokogacha
//

import SwiftUI

/// S-14 の引き直し（F-43）の欄（03 の S-14 の 5。文言は 02 の §6.4 の表示）。
///
/// - 提案前: 点線のボタン「引き直しを提案（過半数の賛成で1回まで）」
/// - 投票中: 点線の「賛成を集めています…（N/M人）」（押せない）と、その下に賛成／反対のボタン。自分の票は濃いボタンにして選んだことを示し、
///   もう一方を押すと票を変えられる
/// - 可決: 「過半数が賛成。もう一度引けます」と「ガチャを回す」（S-13 に進む。03 の §2「S-14 → 引き直し可決 → S-13」）
/// - 可決の後にほかの人が回し直した: 「新しい行き先が決まりました」と「結果を見る」（S-13 に進み、新しい抽選の演出を見てから S-14 に進む）
/// - 使用済み: 点線の「引き直しは使用済みです」（押せない）
///
/// 送っている途中は押せない。文字を大きくして賛成／反対が横に収まらなければ縦に並べる。
struct ResultRerollSection: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 「引き直しを提案（過半数の賛成で1回まで）」
        static let propose = "result.reroll.propose"
        /// 投票中の「賛成を集めています…（N/M人）」・使用済みの「引き直しは使用済みです」
        static let status = "result.reroll.status"
        /// 「賛成」
        static let approve = "result.reroll.approve"
        /// 「反対」
        static let reject = "result.reroll.reject"
        /// 「過半数が賛成。もう一度引けます」
        static let passed = "result.reroll.passed"
        /// 可決の後の「ガチャを回す」
        static let playAgain = "result.reroll.playAgain"
        /// 可決の後にほかの人が回し直したときの「新しい行き先が決まりました」
        static let redrawn = "result.reroll.redrawn"
        /// 可決の後にほかの人が回し直したときの「結果を見る」
        static let showNewResult = "result.reroll.showNewResult"
    }

    /// 欄に出すもの
    let state: RerollPanelState
    /// 送っている途中か
    let isSending: Bool
    /// 「引き直しを提案」が押された
    let onPropose: () -> Void
    /// 賛成（true）・反対（false）が押された
    let onVote: (Bool) -> Void
    /// 可決の後の「ガチャを回す」・ほかの人が回し直した後の「結果を見る」が押された（どちらも S-13 に進む）
    let onPlayAgain: () -> Void

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .proposable:
            DGButton("引き直しを提案（過半数の賛成で1回まで）", kind: .dashed, action: onPropose)
                .disabled(isSending)
                .accessibilityIdentifier(Identifier.propose)
        case let .voting(approvals, memberCount, myVote):
            VStack(spacing: DGSpacing.s10) {
                DGButton("賛成を集めています…（\(approvals)/\(memberCount)人）", kind: .dashed) {}
                    .disabled(true)
                    .accessibilityIdentifier(Identifier.status)
                voteButtons(myVote)
            }
        case .passed:
            VStack(spacing: DGSpacing.s10) {
                Text("過半数が賛成。もう一度引けます")
                    .font(.dg(.bodyTitle))
                    .foregroundStyle(Color.dgInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.passed)
                DGButton("ガチャを回す", action: onPlayAgain)
                    .accessibilityIdentifier(Identifier.playAgain)
            }
        case .redrawn:
            VStack(spacing: DGSpacing.s10) {
                Text("新しい行き先が決まりました")
                    .font(.dg(.bodyTitle))
                    .foregroundStyle(Color.dgInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.redrawn)
                DGButton("結果を見る", action: onPlayAgain)
                    .accessibilityIdentifier(Identifier.showNewResult)
            }
        case .used:
            DGButton("引き直しは使用済みです", kind: .dashed) {}
                .disabled(true)
                .accessibilityIdentifier(Identifier.status)
        }
    }

    /// 賛成／反対。横に収まらなければ縦に並べる
    private func voteButtons(_ myVote: RerollVote?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s10) {
                approveButton(myVote)
                rejectButton(myVote)
            }
            VStack(spacing: DGSpacing.s10) {
                approveButton(myVote)
                rejectButton(myVote)
            }
        }
    }

    /// 「賛成」（自分の票なら濃いボタン）
    private func approveButton(_ myVote: RerollVote?) -> some View {
        voteButton("賛成", label: "引き直しに賛成", isSelected: myVote == .approve, approve: true)
            .accessibilityIdentifier(Identifier.approve)
    }

    /// 「反対」（自分の票なら濃いボタン）
    private func rejectButton(_ myVote: RerollVote?) -> some View {
        voteButton("反対", label: "引き直しに反対", isSelected: myVote == .reject, approve: false)
            .accessibilityIdentifier(Identifier.reject)
    }

    /// 投票のボタン。VoiceOver では何への票か分かるラベルで読み、自分の票は「選択済み」と読む
    private func voteButton(_ title: LocalizedStringKey, label: LocalizedStringKey, isSelected: Bool, approve: Bool) -> some View {
        DGButton(title, kind: isSelected ? .dark : .secondary) {
            onVote(approve)
        }
        .disabled(isSending)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("S-14 引き直しの欄") {
    ScrollView {
        VStack(spacing: DGSpacing.s24) {
            ResultRerollSection(state: .proposable, isSending: false, onPropose: {}, onVote: { _ in }, onPlayAgain: {})
            ResultRerollSection(
                state: .voting(approvals: 1, memberCount: 3, myVote: .approve),
                isSending: false,
                onPropose: {},
                onVote: { _ in },
                onPlayAgain: {}
            )
            ResultRerollSection(state: .passed, isSending: false, onPropose: {}, onVote: { _ in }, onPlayAgain: {})
            ResultRerollSection(state: .redrawn, isSending: false, onPropose: {}, onVote: { _ in }, onPlayAgain: {})
            ResultRerollSection(state: .used, isSending: false, onPropose: {}, onVote: { _ in }, onPlayAgain: {})
        }
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
}
