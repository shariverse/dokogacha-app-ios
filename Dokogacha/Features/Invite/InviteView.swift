//
//  InviteView.swift
//  Dokogacha
//

import SwiftUI

/// S-04 招待。03 の S-04 の上から順に、「ルームを作成しました」＋ルーム名・招待コードカード・「招待リンクを送る」を並べる。
///
/// 開き方は 2 つ（`Context`）:
/// - ルームを作った直後（プッシュ。作成したルームの上に積み、戻るとルーム）。「ルームへ進む」を下に固定する。
///   03 の S-04 とプロトタイプにはヘッダーが無いので置かない（戻るのは「ルームへ進む」か端からのスワイプで、どちらもルームに出る）
/// - S-07 のアバターの並びの招待の「＋」から（シート）。ヘッダー（「メンバーを招待」と右端の閉じる）を置き、
///   「ルームを作成しました」と「ルームへ進む」は出さない（作った直後ではなく、閉じればルームに戻るため）。
///   「招待リンクを送る」と「前回のメンバーを招待」は下部に固定する。トーストはシートの中に重ねる（アプリの根元のトーストはシートの後ろに隠れるため）
///
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
        /// シートの閉じるボタン
        static let close = "invite.close"
    }

    /// 開き方
    enum Context {
        /// ルームを作った直後（プッシュ）。値は「ルームへ進む」を押したときの処理（招待の画面を閉じてルームを出す）
        case created(onOpenRoom: () -> Void)
        /// S-07 の招待の「＋」から（シート）。値はシートの中に重ねるトーストの窓口（`InviteModel`・`LastMembersInviteModel` に渡したもの）
        case sheet(toasts: DGToastCenter)
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
    /// 開き方
    private let context: Context

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var shareIconSize = InviteView.shareIconSize

    /// - Parameters:
    ///   - model: 画面の値（最初の 1 回だけ使う）
    ///   - lastMembers: 前回のメンバーへの招待（最初の 1 回だけ使う。nil ならボタンを出さない）
    ///   - context: 開き方
    init(model: InviteModel, lastMembers: LastMembersInviteModel? = nil, context: Context) {
        _model = State(initialValue: model)
        _lastMembers = State(initialValue: lastMembers)
        self.context = context
    }

    /// ルームを作った直後の S-04（プッシュ）
    /// - Parameters:
    ///   - model: 画面の値（最初の 1 回だけ使う）
    ///   - lastMembers: 前回のメンバーへの招待（最初の 1 回だけ使う。nil ならボタンを出さない）
    ///   - onOpenRoom: 「ルームへ進む」を押したときの処理
    init(model: InviteModel, lastMembers: LastMembersInviteModel? = nil, onOpenRoom: @escaping () -> Void) {
        self.init(model: model, lastMembers: lastMembers, context: .created(onOpenRoom: onOpenRoom))
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .sheet = context {
                sheetHeader
            }
            ScrollView {
                VStack(spacing: DGSpacing.s24) {
                    titleBlock
                    codeCard
                    if case .created = context {
                        inviteActions
                    }
                }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.top, contentTopPadding)
                .padding(.bottom, DGSpacing.s16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .modifier(SheetToast(context: context))
        .task {
            await lastMembers?.observe()
        }
    }

    /// 内容の上の余白。作った直後はヘッダーのある画面と内容の始まりの高さをそろえ（プロトタイプの上の余白 56）、シートではヘッダーの下に続ける
    private var contentTopPadding: CGFloat {
        switch context {
        case .created: DGHeader<EmptyView>.height
        case .sheet: DGSpacing.s8
        }
    }

    /// 下部に固定するもの。作った直後は「ルームへ進む」、シートでは「招待リンクを送る」と「前回のメンバーを招待」
    /// （シートは閉じるとルームに戻るので「ルームへ進む」が無く、送るボタンを指の届く下に置く。S-11 の「招待する」と同じ位置）
    @ViewBuilder private var bottomBar: some View {
        Group {
            switch context {
            case let .created(onOpenRoom):
                DGButton("ルームへ進む", kind: .dark, action: onOpenRoom)
                    .accessibilityIdentifier(Identifier.openRoom)
            case .sheet:
                inviteActions
            }
        }
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.top, DGSpacing.s12)
        .padding(.bottom, DGSpacing.s14)
        .background(Color.dgBgBase)
    }

    /// 「招待リンクを送る」と、前回のメンバーがいれば「前回のメンバー（{前回ルーム名}・N人）を招待」（03 の S-04 の 3・4）
    private var inviteActions: some View {
        VStack(spacing: DGSpacing.s12) {
            shareButton
            if let lastMembers, let invitation = lastMembers.invitation {
                lastMembersButton(lastMembers, invitation: invitation)
            }
        }
    }

    /// シートのヘッダー（「メンバーを招待」と右端の閉じる。S-11 と同じ形）
    private var sheetHeader: some View {
        DGHeader(Text("メンバーを招待"), onBack: nil) {
            JoinSheetCloseButton { dismiss() }
                .accessibilityIdentifier(Identifier.close)
        }
        .padding(.leading, DGSpacing.s12)
    }

    /// 「前回のメンバー（{前回ルーム名}・N人）を招待」（03 の S-04 の 4）。送っている途中と送った後は押せない
    private func lastMembersButton(_ lastMembers: LastMembersInviteModel, invitation: LastMembersInvitation) -> some View {
        DGButton("前回のメンバー（\(invitation.sourceRoomName)・\(invitation.count)人）を招待", kind: .secondary) {
            lastMembers.inviteTapped()
        }
        .disabled(!lastMembers.canInvite)
        .accessibilityIdentifier(Identifier.lastMembers)
    }

    /// 「ルームを作成しました」＋ルーム名（03 の S-04 の 1）。シートではルーム名だけ（作った直後ではないため）
    private var titleBlock: some View {
        VStack(spacing: DGSpacing.s8) {
            if case .created = context {
                Text("ルームを作成しました")
                    .font(.dgBody(Self.captionSize, relativeTo: .subheadline))
                    .foregroundStyle(Color.dgTextSecondary)
            }
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

/// シートで開いたときだけ、シートの中にトーストを重ねる（作った直後はアプリの根元のトーストに出す）
private struct SheetToast: ViewModifier {
    let context: InviteView.Context

    func body(content: Content) -> some View {
        if case let .sheet(toasts) = context {
            content.dgToast(toasts)
        } else {
            content
        }
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

#Preview("S-04 ルームから（シート）") {
    let toasts = DGToastCenter()
    Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            InviteView(
                model: InviteModel(
                    destination: InviteDestination(
                        roomID: DemoScenario.roomID,
                        roomName: "年末の旅行",
                        inviteCode: InviteCode(DemoScenario.inviteCode) ?? InviteCode.generate { _ in 0 }
                    ),
                    toasts: toasts
                ),
                context: .sheet(toasts: toasts)
            )
        }
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
