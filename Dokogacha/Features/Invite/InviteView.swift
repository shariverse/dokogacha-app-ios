//
//  InviteView.swift
//  Dokogacha
//

import SwiftUI

/// S-04 招待（プッシュ。作成したルームの上に積み、戻るとルーム）。03 の S-04 の上から順に、
/// 「ルームを作成しました」＋ルーム名・招待コードカード・「招待リンクを送る」を並べ、「ルームへ進む」を下に固定する。
///
/// 03 の S-04 とプロトタイプにはヘッダーが無いので置かない（戻るのは「ルームへ進む」か端からのスワイプで、どちらもルームに出る）。
/// 「前回のメンバー（{前回ルーム名}・N人）を招待」（03 の S-04 の 4）は、前回のルームがあり招待する人がいるときだけ
/// 「招待リンクを送る」の下に出す（`LastMembersInviteModel`。プレビューなどで渡さなければ出さない）。
struct InviteView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 画面
        static let screen = "invite.screen"
        /// 招待コード（長押しでコピー）
        static let code = "invite.code"
        /// 「招待リンクを送る」
        static let share = "invite.share"
        /// 「ルームへ進む」
        static let openRoom = "invite.openRoom"
        /// 「前回のメンバー（{前回ルーム名}・N人）を招待」
        static let lastMembers = "invite.lastMembers"
    }

    /// 「ルームを作成しました」「招待コード」の文字の大きさ（03 の S-04「13pt」）
    private static let captionSize: CGFloat = 13
    /// 招待コードの文字の大きさ（03 の S-04「見出し36pt」・04 の §2）
    private static let codeSize: CGFloat = 36
    /// 招待コードカードの上下の余白（プロトタイプの 24）
    private static let cardVerticalPadding: CGFloat = 24
    /// 共有のアイコンの一辺（`DGButtonKind.primary.iconSize`）
    private static let shareIconSize: CGFloat = DGButtonKind.primary.iconSize

    @State private var model: InviteModel
    /// 前回のメンバーへの招待（無ければボタンを出さない）
    @State private var lastMembers: LastMembersInviteModel?
    /// 「ルームへ進む」を押したときの処理（招待の画面を閉じてルームを出す）
    private let onOpenRoom: () -> Void

    @ScaledMetric(relativeTo: .body) private var shareIconSize = InviteView.shareIconSize

    /// - Parameters:
    ///   - model: 画面の値（最初の 1 回だけ使う）
    ///   - lastMembers: 前回のメンバーへの招待（最初の 1 回だけ使う。nil ならボタンを出さない）
    ///   - onOpenRoom: 「ルームへ進む」を押したときの処理
    init(model: InviteModel, lastMembers: LastMembersInviteModel? = nil, onOpenRoom: @escaping () -> Void) {
        _model = State(initialValue: model)
        _lastMembers = State(initialValue: lastMembers)
        self.onOpenRoom = onOpenRoom
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DGSpacing.s24) {
                titleBlock
                codeCard
                VStack(spacing: DGSpacing.s12) {
                    shareButton
                    if let lastMembers, let invitation = lastMembers.invitation {
                        lastMembersButton(lastMembers, invitation: invitation)
                    }
                }
            }
            .padding(.horizontal, DGSpacing.screenX)
            .dgContentColumn()
            // ヘッダーのある画面と、内容の始まりの高さをそろえる（プロトタイプの上の余白 56）
            .padding(.top, DGHeader<EmptyView>.height)
            .padding(.bottom, DGSpacing.s16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dgCentersContentOnTallScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DGButton("ルームへ進む", kind: .dark, action: onOpenRoom)
                .accessibilityIdentifier(Identifier.openRoom)
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.top, DGSpacing.s12)
                .padding(.bottom, DGSpacing.s14)
                .dgContentColumn()
                .background(Color.dgBgBase)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .task {
            await lastMembers?.observe()
        }
    }

    /// 「前回のメンバー（{前回ルーム名}・N人）を招待」（03 の S-04 の 4）。送っている途中と送った後は押せない
    private func lastMembersButton(_ lastMembers: LastMembersInviteModel, invitation: LastMembersInvitation) -> some View {
        DGButton("前回のメンバー（\(invitation.sourceRoomName)・\(invitation.count)人）を招待", kind: .secondary) {
            lastMembers.inviteTapped()
        }
        .disabled(!lastMembers.canInvite)
        .accessibilityIdentifier(Identifier.lastMembers)
    }

    /// 「ルームを作成しました」＋ルーム名（03 の S-04 の 1）
    private var titleBlock: some View {
        VStack(spacing: DGSpacing.s8) {
            Text("ルームを作成しました")
                .font(.dgBody(Self.captionSize, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextSecondary)
            Text(verbatim: model.roomName)
                .font(.dg(.displayL))
                .foregroundStyle(Color.dgInk)
                .accessibilityAddTraits(.isHeader)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// 招待コードカード（03 の S-04 の 2）。コードを長押しするとコピーする。
    ///
    /// VoiceOver では、カード全体を 1 つのボタンとして読み（「招待コード、D K 7 - 2 9 Q、最大20人まで参加できます」）、
    /// ダブルタップでコピーする（長押しの操作を VoiceOver から使えるようにする）。
    /// ヒントは操作の仕方（「ダブルタップで」）ではなく結果だけを読む（操作の仕方は VoiceOver が読む。PR #43 の持ち越し）
    private var codeCard: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        return VStack(spacing: DGSpacing.s10) {
            Text("招待コード")
                .font(.dgBody(Self.captionSize, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextSecondary)
            Text(verbatim: model.codeText)
                .speechSpellsOutCharacters()
                .font(.dgDisplay(Self.codeSize, relativeTo: .title2))
                .tracking(DGTracking.points(DGTracking.inviteCode, fontSize: Self.codeSize))
                .foregroundStyle(Color.dgInk)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("最大\(model.maxMembers)人まで参加できます")
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DGSpacing.s16)
        .padding(.vertical, Self.cardVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.strong) }
        .dgHardShadow(.hard, cornerRadius: DGRadius.lg)
        .contentShape(shape)
        .onLongPressGesture {
            model.copyCode()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("招待コードをコピーします"))
        .accessibilityAction {
            model.copyCode()
        }
        .accessibilityIdentifier(Identifier.code)
    }

    /// 「招待リンクを送る」（03 の S-04 の 3）。共有シートで文面と招待リンクを送る
    private var shareButton: some View {
        ShareLink(item: model.shareMessage) {
            HStack(spacing: DGSpacing.s8) {
                Image("ui-share")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: shareIconSize, height: shareIconSize)
                    .accessibilityHidden(true)
                Text("招待リンクを送る")
            }
        }
        .buttonStyle(.dg(.primary))
        .accessibilityIdentifier(Identifier.share)
    }
}

#Preview("S-04 招待") {
    InviteView(
        model: InviteModel(
            destination: InviteDestination(
                roomID: DemoScenario.roomID,
                roomName: "年末の旅行",
                inviteCode: InviteCode(DemoScenario.inviteCode) ?? InviteCode.generate { _ in 0 }
            ),
            toasts: DGToastCenter()
        )
    ) {}
}

#Preview("S-04 文字を最大") {
    InviteView(
        model: InviteModel(
            destination: InviteDestination(
                roomID: DemoScenario.roomID,
                roomName: "年末の旅行",
                inviteCode: InviteCode(DemoScenario.inviteCode) ?? InviteCode.generate { _ in 0 }
            ),
            toasts: DGToastCenter()
        )
    ) {}
    .dynamicTypeSize(.accessibility5)
}
