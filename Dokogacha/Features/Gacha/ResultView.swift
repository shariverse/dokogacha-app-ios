//
//  ResultView.swift
//  Dokogacha
//

import SwiftUI

/// S-14 結果（行き先きっぷ。フルスクリーンカバー）。03 の S-14 の上から順に、「行き先が決まりました」、レア当選のバッジ、
/// 行き先きっぷ、「マップで開く」「きっぷを共有」の 2 列のボタン、引き直しの欄（F-43。`ResultRerollSection`）を並べる。
///
/// 03 の S-14 には閉じる操作が無いが、S-13 と同じヘッダー（戻る矢印・ルーム名）を置き、ルーム（S-07）に戻れるようにする
/// （作成者以外と閲覧のみの画面には「この行き先で決定」（F-44。`ResultCloseSection`）が無く、ほかに抜ける操作が無いため）。
/// 引き直しが可決したら、欄の「ガチャを回す」で `onPlayAgain` を呼び、同じカバーの中で S-13 に戻る（`GachaFlowView`）。
/// 可決の後にほかの人が先に回し直したら、欄の「結果を見る」で同じく S-13 に戻り、新しい抽選の演出を見てから S-14 に進む。
/// 下部には「この行き先で決定」（作成者のみ。作成者以外は説明文）を固定する（03 の S-14 の 6）。押しても何もしないボタンは置かない。
/// `closed` のルームは閲覧のみで、引き直しの欄と下部の「この行き先で決定」・説明のどちらも出さない。
///
/// 表示したときに、きっぷがポップインし（04 の §5 の `pop`。0.45 秒）、0.5 秒後にハンコを押す（`stamp`）。
/// 「視差効果を減らす」ではフェード（0.2 秒）だけにする。撮影モード・UI テストでは `animatesIn` を false にして止める。
/// 文字を大きくしたときは、全体をスクロールし、2 列のボタンを縦に並べる。
struct ResultView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 結果の画面
        static let screen = "result.screen"
        /// 「行き先が決まりました」
        static let title = "result.title"
        /// 「レア当選」
        static let rare = "result.rare"
        /// 行き先きっぷ
        static let ticket = "result.ticket"
        /// 「マップで開く」
        static let openInMaps = "result.openInMaps"
        /// 「きっぷを共有」
        static let share = "result.share"
        /// ルームが見つからないときの案内
        static let missing = "result.missing"
        /// きっぷを作れないときの案内
        static let unavailable = "result.unavailable"
    }

    /// 「レア当選」の文字の大きさ（プロトタイプの値）
    private static let rareBadgeSize: CGFloat = 13
    /// ポップインの前のきっぷの大きさ（04 の §5 の `pop`「0.7倍・透明 → 等倍」）
    private static let popStartScale: CGFloat = 0.7

    @State private var model: ResultModel
    /// トーストの窓口（フルスクリーンカバーの中に重ねる。親が描き直しても最初のものを使い続ける）
    @State private var toasts: DGToastCenter
    /// 表示したときにきっぷとハンコを動かすか
    private let animatesIn: Bool
    /// 引き直しの可決の後に「ガチャを回す」・「結果を見る」が押された（S-13 に戻る）
    private let onPlayAgain: () -> Void
    /// きっぷを出し終えたか（ポップインの後の状態）
    @State private var hasPopped = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 共有のアイコンを文字の大きさに合わせる倍率（`DGButton` と同じ）
    @ScaledMetric(relativeTo: .body) private var iconScale: CGFloat = 1

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - toasts: トーストの窓口（最初の 1 回だけ使う）
    ///   - animatesIn: 表示したときにきっぷとハンコを動かすか（撮影・UI テストでは false）
    ///   - onPlayAgain: 引き直しの可決の後に「ガチャを回す」・「結果を見る」が押された（S-13 に戻る）
    init(model: ResultModel, toasts: DGToastCenter, animatesIn: Bool = true, onPlayAgain: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        _toasts = State(initialValue: toasts)
        self.animatesIn = animatesIn
        self.onPlayAgain = onPlayAgain
        _hasPopped = State(initialValue: !animatesIn)
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text(verbatim: model.room.room?.name ?? ""), onBack: { dismiss() })
                .padding(.leading, DGSpacing.s4)
            ScrollView {
                content
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.top, DGSpacing.s8)
                    .padding(.bottom, DGSpacing.s24)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 下部に固定する「この行き先で決定」（作成者）・説明（作成者以外）。F-44
            ResultCloseSection(result: model)
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .dgToast(toasts)
        .task {
            await model.observe()
        }
        .onDisappear {
            model.cancelSending()
        }
    }

    /// 読み込みの状態ごとの中身
    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loaded:
            if let ticket = model.ticket {
                loadedContent(ticket)
            }
        case .loading:
            loadingContent
        case .missing:
            missingContent
        case .unavailable:
            unavailableContent
        }
    }

    /// 見出し・レア当選・きっぷ・ボタン
    private func loadedContent(_ ticket: ResultTicket) -> some View {
        VStack(spacing: DGSpacing.s16) {
            title
            if ticket.isRare {
                rareBadge
            }
            ResultTicketView(ticket: ticket, stampAnimatesIn: animatesIn)
                .scaleEffect(hasPopped || reduceMotion ? 1 : Self.popStartScale)
                .opacity(hasPopped ? 1 : 0)
                .onAppear(perform: popIn)
                .accessibilityIdentifier(Identifier.ticket)
            actions(ticket)
                .padding(.top, DGSpacing.s4)
            ResultRerollSection(
                state: model.rerollPanel,
                isSending: model.isSendingReroll,
                onPropose: model.proposeRerollTapped,
                onVote: { model.voteTapped(approve: $0) },
                onPlayAgain: onPlayAgain
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// 「行き先が決まりました」（見出し 22pt）
    private var title: some View {
        Text("行き先が決まりました")
            .font(.dg(.displayM))
            .foregroundStyle(Color.dgInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(Identifier.title)
    }

    /// 「レア当選」のバッジ（黒地に黄色の文字。プロトタイプの見た目）
    private var rareBadge: some View {
        Text("レア当選")
            .font(.dgBody(Self.rareBadgeSize, weight: .black, relativeTo: .footnote))
            .foregroundStyle(Color.dgAccentSecondary)
            .padding(.vertical, DGSpacing.s4)
            .padding(.horizontal, DGSpacing.s14)
            .background(Color.dgInk, in: RoundedRectangle(cornerRadius: DGRadius.xs))
            .accessibilityIdentifier(Identifier.rare)
    }

    /// 「マップで開く」「きっぷを共有」。横に収まらなければ縦に並べる
    private func actions(_ ticket: ResultTicket) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s10) {
                mapButton
                shareButton(ticket)
            }
            VStack(spacing: DGSpacing.s10) {
                mapButton
                shareButton(ticket)
            }
        }
    }

    /// 「マップで開く」（PrimaryButton。当選した候補を読めるまでは押せない）
    private var mapButton: some View {
        DGButton("マップで開く", icon: "ui-pin") {
            model.openInMapsTapped()
        }
        .disabled(!model.canOpenMap)
        .accessibilityIdentifier(Identifier.openInMaps)
    }

    /// 「きっぷを共有」（SecondaryButton の見た目の `ShareLink`。画像は共有するときに作る）
    private func shareButton(_ ticket: ResultTicket) -> some View {
        ShareLink(item: TicketShareImage(ticket: ticket), preview: SharePreview(Text("行き先きっぷ"))) {
            HStack(spacing: DGSpacing.s6) {
                Image("ui-share")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: DGButtonKind.secondary.iconSize * iconScale, height: DGButtonKind.secondary.iconSize * iconScale)
                    .accessibilityHidden(true)
                Text("きっぷを共有")
            }
        }
        .buttonStyle(.dg(.secondary))
        // `ShareLink` は押したときの処理を持てないので、押したことを同時のタップで受けて `ticket_share` を送る
        .simultaneousGesture(TapGesture().onEnded { model.shareTapped() })
        .accessibilityIdentifier(Identifier.share)
    }

    /// 抽選の記録・候補が届くまでの、部品の形を保った読み込み中の表示（03 の §3）
    private var loadingContent: some View {
        VStack(spacing: DGSpacing.s16) {
            title
            ResultTicketView(ticket: ResultTicket(
                roomName: String(localized: "読み込み中"),
                destinationName: String(localized: "読み込み中"),
                area: String(localized: "読み込み中"),
                category: .town,
                note: nil,
                author: .departed,
                likeCount: 0,
                percent: 0,
                drawnAt: Date(timeIntervalSince1970: 0),
                isRare: false
            ))
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }

    /// ルームが無い・読めなくなったときの案内（戻るはヘッダーから）
    private var missingContent: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            Text("ルームが見つかりません")
                .font(.dg(.displaySection))
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("ルームが削除されたか、メンバーから外れました")
                .font(.dg(.bodyRegular))
                .foregroundStyle(Color.dgTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DGSpacing.s16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.missing)
    }

    /// 抽選の記録・当選した候補が読めず、きっぷを作れないときの案内（戻るはヘッダーから）
    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            Text("行き先きっぷを読み込めませんでした")
                .font(.dg(.displaySection))
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("抽選の記録が見つかりません")
                .font(.dg(.bodyRegular))
                .foregroundStyle(Color.dgTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DGSpacing.s16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.unavailable)
    }

    /// きっぷをポップインさせる（`animatesIn` のときだけ。視差効果を減らすならフェードだけ）
    private func popIn() {
        guard !hasPopped else {
            return
        }
        withAnimation(reduceMotion ? DGMotion.reducedFade : DGMotion.popSpring) {
            hasPopped = true
        }
    }
}

#Preview("S-14 結果") {
    let server = InMemoryServer.demo(.severalRooms)
    let toasts = DGToastCenter()
    let response = try? server.drawGacha(RoomRequest(roomId: DemoScenario.unlockedRoomID), by: DemoScenario.myUserID)
    ResultView(
        model: ResultModel(
            roomID: DemoScenario.unlockedRoomID,
            drawID: response?.drawId ?? "",
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: toasts
        ),
        toasts: toasts
    )
}

#Preview("S-14 文字を最大") {
    let server = InMemoryServer.demo(.severalRooms)
    let toasts = DGToastCenter()
    let response = try? server.drawGacha(RoomRequest(roomId: DemoScenario.unlockedRoomID), by: DemoScenario.myUserID)
    ResultView(
        model: ResultModel(
            roomID: DemoScenario.unlockedRoomID,
            drawID: response?.drawId ?? "",
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: toasts
        ),
        toasts: toasts,
        animatesIn: false
    )
    .dynamicTypeSize(.accessibility5)
}
