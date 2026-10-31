//
//  MembersView.swift
//  Dokogacha
//

import SwiftUI

/// S-11 メンバー一覧（シート）。03 の S-11 のとおり、メンバーごとにアバター・名前・準備OKの状態・投稿数を並べ、作成者に「作成者」の印を付ける。
/// 作成者は自分以外のメンバーを行のスワイプで削除でき（確認のダイアログ）、下部には「招待する」（S-04 と同じ共有）と、
/// 自分が作成者以外なら「ルームから退出」（確認のダイアログ）を置く（02 の F-05）。
///
/// 標準のナビゲーションバーは使わず、ヘッダー（タイトルと右端の閉じる）を置く（03 の §3）。
/// トーストの窓口はシートの中で持ち、シートの根元に重ねる（アプリの根元のトーストはシートの後ろに隠れるため）。
/// 退出・削除を送っている間は、閉じるボタンと下スワイプで閉じられないようにする。退出できたら `onLeft` で親がホームへ戻す。
struct MembersView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// メンバー一覧の画面
        static let screen = "members.screen"
        /// 人数の表示
        static let count = "members.count"
        /// 「招待する」
        static let invite = "members.invite"
        /// 「ルームから退出」
        static let leave = "members.leave"
        /// 閉じるボタン
        static let close = "members.close"

        /// メンバーの行
        static func row(_ memberID: String) -> String {
            "members.row.\(memberID)"
        }
    }

    /// 「ルームから退出」の文字の大きさ（S-10 の「この候補を削除」と同じテキストボタン）
    private static let leaveSize: CGFloat = 15
    /// 「作成者」の印の文字の大きさ
    private static let ownerLabelSize: CGFloat = 11
    /// 共有のアイコンの一辺（主ボタンのアイコン）
    private static let shareIconSize: CGFloat = DGButtonKind.primary.iconSize

    @State private var model: MembersModel
    @State private var toasts: DGToastCenter
    /// 退出できたときの処理（シートを閉じてホームへ戻る）
    private let onLeft: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var shareIconSize = MembersView.shareIconSize

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - toasts: 失敗を出すトーストの窓口（`model` に渡したもの。シートの根元に重ねる）
    ///   - onLeft: 退出できたときの処理
    init(model: MembersModel, toasts: DGToastCenter, onLeft: @escaping () -> Void) {
        _model = State(initialValue: model)
        _toasts = State(initialValue: toasts)
        self.onLeft = onLeft
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .dgToast(toasts)
        // 送っている間は、下スワイプで閉じさせない（S-09・S-10 と同じ）
        .lockNavigation(while: model.locksNavigation)
        .confirmationDialog(
            Text("ルームから退出しますか？"),
            isPresented: $model.isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                model.confirmLeaveTapped()
            } label: {
                Text("退出する")
            }
            Button(role: .cancel) {} label: {
                Text("キャンセル")
            }
        } message: {
            Text("投稿した候補は残り、いいねは取り消されます。")
        }
        .confirmationDialog(
            removalTitle,
            isPresented: isConfirmingRemoval,
            titleVisibility: .visible,
            presenting: model.memberPendingRemoval
        ) { row in
            Button(role: .destructive) {
                model.confirmRemoveTapped(row)
            } label: {
                Text("削除する")
            }
            Button(role: .cancel) {} label: {
                Text("キャンセル")
            }
        } message: { _ in
            Text("投稿した候補は残り、いいねは取り消されます。")
        }
        .task {
            await model.observe()
        }
        // ルームが無くなった・自分が外されたら、シートを閉じる（S-07 が「ルームが見つかりません」を出す）
        .onChange(of: model.shouldClose, initial: true) { _, shouldClose in
            if shouldClose {
                dismiss()
            }
        }
        .onChange(of: model.didLeave) { _, didLeave in
            if didLeave {
                onLeft()
            }
        }
        // 閉じたら、送っている途中の退出・削除を止める（Task が Model を持ち続けないように）
        .onDisappear { model.cancelSending() }
    }

    // MARK: - ヘッダー

    /// タイトルと、右端の閉じるボタン
    private var header: some View {
        DGHeader(Text("メンバー"), onBack: nil) {
            JoinSheetCloseButton { dismiss() }
                .disabled(model.locksNavigation)
                .accessibilityIdentifier(Identifier.close)
        }
        .padding(.leading, DGSpacing.s12)
        .dgContentColumn()
    }

    // MARK: - 一覧

    /// ルームが届くまでは読み込み中の形、届いたらメンバーの一覧（作成者はスワイプで削除できる）
    @ViewBuilder private var content: some View {
        if model.room.room == nil {
            loadingContent
        } else {
            List {
                Text("\(model.memberCount)人 · 最大\(model.maxMembers)人")
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.count)
                    .listRowStyle()
                ForEach(model.rows) { row in
                    memberRow(row)
                        .listRowStyle()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if row.canRemove {
                                Button(role: .destructive) {
                                    model.removeTapped(row)
                                } label: {
                                    Text("削除")
                                }
                                .tint(Color.dgAccentPrimary)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dgContentColumn()
            .disabled(model.isSending)
        }
    }

    /// メンバー 1 人分の行（アバター・名前・作成者の印・準備OK・投稿数）。VoiceOver では 1 つにまとめて読む
    private func memberRow(_ row: MembersModel.Row) -> some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return HStack(alignment: .center, spacing: DGSpacing.s12) {
            DGAvatar(
                name: row.name,
                color: row.avatarColorIndex.map(Color.dgAvatar(at:)) ?? Color.dgAvatarNotReadyBg,
                size: .large,
                readiness: row.isReady ? .ready : .notReady
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                nameLine(row)
                Text("\(readinessText(row)) · 投稿 \(row.postCount)件")
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DGSpacing.cardPadding)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
        .accessibilityElement(children: .combine)
        // VoiceOver ではスワイプの代わりに、ローターの「アクション」から削除する（ヒントで操作の仕方を読まない。PR #65 の持ち越し）
        .accessibilityActions {
            if row.canRemove {
                Button {
                    model.removeTapped(row)
                } label: {
                    Text("削除")
                }
            }
        }
        .accessibilityIdentifier(Identifier.row(row.id))
    }

    /// 準備OKの状態（準備OKなら墨色の太字にして目立たせる）
    private func readinessText(_ row: MembersModel.Row) -> Text {
        if row.isReady {
            return Text("準備OK").bold().foregroundStyle(Color.dgInk)
        }
        return Text("未準備")
    }

    /// 名前と「作成者」の印・「あなた」。入らなければ印を下の行に回す
    private func nameLine(_ row: MembersModel.Row) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s6) {
                nameText(row)
                badges(row)
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                nameText(row)
                badges(row)
            }
        }
    }

    /// 名前（自分なら後ろに「（あなた）」）
    private func nameText(_ row: MembersModel.Row) -> some View {
        Group {
            if row.isMe {
                Text("\(row.name)（あなた）")
            } else {
                Text(verbatim: row.name)
            }
        }
        .font(.dg(.bodyTitle))
        .foregroundStyle(Color.dgInk)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 「作成者」の印（作成者だけ）
    @ViewBuilder private func badges(_ row: MembersModel.Row) -> some View {
        if row.isOwner {
            Text("作成者")
                .font(.dgBody(Self.ownerLabelSize, weight: .black, relativeTo: .caption2))
                .foregroundStyle(Color.dgInk)
                .padding(.horizontal, DGSpacing.s8)
                .padding(.vertical, DGSpacing.s4)
                .background(Color.dgAccentSecondary, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
                .fixedSize()
        }
    }

    /// 最初のルームが届くまでの、行の形を保った読み込み中の表示（03 の §3）
    private var loadingContent: some View {
        VStack(spacing: DGSpacing.s8) {
            ForEach(0..<3, id: \.self) { index in
                memberRow(MembersModel.Row(
                    id: "loading-\(index)",
                    name: String(localized: "読み込み中"),
                    avatarColorIndex: nil,
                    isReady: false,
                    postCount: 0,
                    isOwner: false,
                    isMe: false,
                    canRemove: false
                ))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpacing.screenX)
        .dgContentColumn()
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }

    // MARK: - 下部

    /// 「招待する」と、作成者以外なら「ルームから退出」
    private var bottomBar: some View {
        VStack(spacing: DGSpacing.s8) {
            inviteButton
            if model.canLeave {
                leaveButton
            }
        }
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.top, DGSpacing.s12)
        .padding(.bottom, DGSpacing.s14)
        .dgContentColumn()
        .background(Color.dgBgBase)
        .disabled(model.isSending)
    }

    /// 「招待する」（S-04 と同じ文面を共有シートで送る）。参加できない状態・満員・ルームが届くまでは押せない（満員は上の「20人 · 最大20人」で分かる）
    @ViewBuilder private var inviteButton: some View {
        if let message = model.shareMessage {
            ShareLink(item: message) {
                inviteLabel
            }
            .buttonStyle(.dg(.primary))
            .accessibilityIdentifier(Identifier.invite)
        } else {
            Button {} label: {
                inviteLabel
            }
            .buttonStyle(.dg(.primary))
            .disabled(true)
            .accessibilityIdentifier(Identifier.invite)
        }
    }

    /// 「招待する」の中身（共有のアイコンと文言）
    private var inviteLabel: some View {
        HStack(spacing: DGSpacing.s8) {
            Image("ui-share")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: shareIconSize, height: shareIconSize)
                .accessibilityHidden(true)
            Text("招待する")
        }
    }

    /// テキストボタン「ルームから退出」（赤文字。押すと確認のダイアログ）
    private var leaveButton: some View {
        Button {
            model.leaveTapped()
        } label: {
            Text("ルームから退出")
                .font(.dgBody(Self.leaveSize, weight: .bold, relativeTo: .body))
                .foregroundStyle(Color.dgAccentText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityIdentifier(Identifier.leave)
    }

    // MARK: - 削除の確認

    /// 削除の確認のダイアログを出しているか（閉じたら確認中のメンバーを消す）
    private var isConfirmingRemoval: Binding<Bool> {
        Binding {
            model.memberPendingRemoval != nil
        } set: { isPresented in
            if !isPresented {
                model.memberPendingRemoval = nil
            }
        }
    }

    /// 削除の確認のダイアログの見出し
    private var removalTitle: Text {
        Text("\(model.memberPendingRemoval?.name ?? "")さんをルームから削除しますか？")
    }
}

private extension View {
    /// 一覧の行の並べ方（区切り線を出さず、背景を透かし、左右を画面の余白にそろえる）
    func listRowStyle() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: DGSpacing.s4, leading: DGSpacing.screenX, bottom: DGSpacing.s4, trailing: DGSpacing.screenX))
    }
}

#Preview("S-11 作成者") {
    let toasts = DGToastCenter()
    let server = InMemoryServer.demo(.roomWithCandidates)
    return Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            MembersView(
                model: MembersModel(
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

#Preview("S-11 メンバー") {
    let toasts = DGToastCenter()
    let server = InMemoryServer.demo(.severalRooms)
    return Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            MembersView(
                model: MembersModel(
                    roomID: DemoScenario.othersRoomID,
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
