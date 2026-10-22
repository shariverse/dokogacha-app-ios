//
//  JoinConfirmView.swift
//  Dokogacha
//

import SwiftUI

/// S-06 参加確認（シートの中で S-05 の上に積む。F-04）。03 の S-06 のとおり、ルーム名・作成者名・メンバー数・候補数・状態チップを
/// カードに並べ、下に「参加する」とテキストボタン「やめる」を置く。
///
/// ヘッダーの戻るは S-05 に戻る（コードを直す）。「やめる」は参加をやめてシートを閉じる。
/// 参加できたら `onJoined` でルームの ID を親に渡す（親がシートを閉じてルームを開く）。
struct JoinConfirmView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 画面
        static let screen = "joinConfirm.screen"
        /// ルームのカード
        static let card = "joinConfirm.card"
        /// 「参加する」
        static let join = "joinConfirm.join"
        /// 「やめる」
        static let cancel = "joinConfirm.cancel"
    }

    /// 項目の名前の文字の大きさ（本文 13。S-04 の「招待コード」と同じ）
    private static let itemLabelSize: CGFloat = 13
    /// 「やめる」の文字の大きさ（本文 Bold 15。SecondaryButton と同じ）
    private static let cancelSize: CGFloat = 15
    /// カードの上下の余白（S-04 の招待コードカードと同じ 24）
    private static let cardVerticalPadding: CGFloat = 24

    @State private var model: JoinConfirmModel
    /// 「やめる」を押したときの処理（シートを閉じる）
    private let onCancel: () -> Void
    /// 参加したときの処理（値はルームの ID）
    private let onJoined: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - onCancel: 「やめる」を押したときの処理
    ///   - onJoined: 参加したときの処理
    init(model: JoinConfirmModel, onCancel: @escaping () -> Void, onJoined: @escaping (String) -> Void) {
        _model = State(initialValue: model)
        self.onCancel = onCancel
        self.onJoined = onJoined
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("参加確認"), onBack: { dismiss() })
                .padding(.horizontal, DGSpacing.s4)
                .disabled(model.locksNavigation)
            ScrollView {
                roomCard
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.top, DGSpacing.s8)
                    .padding(.bottom, DGSpacing.s16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: DGSpacing.s4) {
                DGButton("参加する") {
                    model.joinTapped()
                }
                .disabled(!model.canJoin)
                .accessibilityIdentifier(Identifier.join)
                cancelButton
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s12)
            .padding(.bottom, DGSpacing.s14)
            .background(Color.dgBgBase)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .onChange(of: model.joinedRoomID) { _, roomID in
            if let roomID {
                onJoined(roomID)
            }
        }
        // 送っている途中は、端からのスワイプで S-05 に戻る・シートを下スワイプで閉じるのを止める
        .lockNavigation(while: model.locksNavigation)
        // 戻った・閉じた・ルームに進んだら、送っている途中の参加を止める（Task が Model を持ち続けないように）
        .onDisappear { model.cancelJoin() }
    }

    /// ルームのカード（状態チップ・ルーム名・作成者・メンバー数・候補数）。VoiceOver では 1 つにまとめて読む
    private var roomCard: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        let preview = model.preview
        return VStack(alignment: .leading, spacing: DGSpacing.s16) {
            VStack(alignment: .leading, spacing: DGSpacing.s8) {
                DGStatusChip(status: DGStatusChip.Status(preview.status))
                Text(verbatim: preview.name)
                    .font(.dg(.displayL))
                    .foregroundStyle(Color.dgInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            DGDashedLine()
            VStack(alignment: .leading, spacing: DGSpacing.s10) {
                if let ownerName = preview.ownerName {
                    item("作成者", value: Text(verbatim: ownerName))
                }
                item("メンバー", value: Text("\(preview.memberCount)人"))
                item("候補", value: Text("\(preview.candidateCount)件"))
            }
        }
        .padding(.horizontal, DGSpacing.s16)
        .padding(.vertical, Self.cardVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.strong) }
        .dgHardShadow(.hard, cornerRadius: DGRadius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Identifier.card)
    }

    /// 項目の名前と値を 1 行に並べる。文字が大きくて入らないときは縦に並べる
    private func item(_ label: LocalizedStringKey, value: Text) -> some View {
        let labelText = Text(label)
            .font(.dgBody(Self.itemLabelSize, relativeTo: .subheadline))
            .foregroundStyle(Color.dgTextSecondary)
        let valueText = value
            .font(.dg(.bodyTitle))
            .foregroundStyle(Color.dgInk)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s8) {
                labelText
                Spacer(minLength: DGSpacing.s8)
                valueText
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                labelText
                valueText
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// テキストボタン「やめる」（参加をやめてシートを閉じる）
    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("やめる")
                .font(.dgBody(Self.cancelSize, weight: .bold, relativeTo: .body))
                .foregroundStyle(Color.dgTextSecondary)
                .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .disabled(model.locksNavigation)
        .accessibilityIdentifier(Identifier.cancel)
    }
}

#Preview("S-06 参加確認") {
    NavigationStack {
        JoinConfirmView(model: JoinConfirmView.previewModel(), onCancel: {}, onJoined: { _ in })
    }
}

#Preview("S-06 文字を最大") {
    NavigationStack {
        JoinConfirmView(model: JoinConfirmView.previewModel(), onCancel: {}, onJoined: { _ in })
    }
    .dynamicTypeSize(.accessibility5)
}

extension JoinConfirmView {
    /// プレビュー用の画面の状態（`joinable` のデモの「夏の花火大会」）
    static func previewModel() -> JoinConfirmModel {
        let preview = RoomPreview(
            roomId: DemoScenario.joinableRoomID,
            name: "夏の花火大会",
            ownerName: "はるか",
            memberCount: 3,
            candidateCount: 2,
            status: .open,
            alreadyMember: false
        )
        let code = InviteCode(DemoScenario.joinableInviteCode) ?? InviteCode.generate { _ in 0 }
        return JoinConfirmModel(
            destination: JoinConfirmDestination(preview: preview, inviteCode: code),
            functions: InMemoryServer.demo(.joinable),
            toasts: DGToastCenter()
        )
    }
}
