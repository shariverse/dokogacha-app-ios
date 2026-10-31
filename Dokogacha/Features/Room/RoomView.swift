//
//  RoomView.swift
//  Dokogacha
//

import SwiftUI

/// S-07 ルーム（プッシュ）。03 の S-07 の上から順に、ヘッダー（戻る・ルーム名・状態チップ・作成者だけ設定）、
/// ルームパネル（行き先の黒帯・準備OKの人数とメンバー・あなたの投稿）、候補の見出し行、NEW の案内、候補カードをスクロールで並べ、
/// 下に「ガチャを回す」を固定する。
///
/// 標準のナビゲーションバーは使わない（03 の §3）。画面の行き先（S-08・S-10・S-11・S-12・S-13）は `navigate` で親に渡す。
/// ルームパネルは `RoomPanel`（準備OKのボタン・ヒント文言・強制解禁 F-30〜32 を含む。強制解禁の確認のダイアログもそのボタンに付く）。
/// 強制解禁を送っている途中はヘッダー（戻る・設定）を押せなくする。バナー広告（F-50）は下部のボタンの下に置く（`BannerAdSlot`。購入者がいるルームでは出さず、代わりに「◯◯さんのおかげで、このルームは広告なし」（`AdFreeNoticeSlot`。F-51）を出す）。
/// `drawn`・`closed` のルームを開いたときは結果（S-14）を自動で出す（03 の §2）。下部のボタンは `RoomGachaBar`。
struct RoomView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// ルームの画面
        static let screen = "room.screen"
        /// ヘッダーの設定（作成者だけ）
        static let settings = "room.settings"
        /// ルームパネルのメンバー（押すとメンバー一覧）
        static let members = "room.members"
        /// ルームパネルのアバターの並びの招待の「＋」（満員のときは押せない「満員」の表示）
        static let invite = "room.invite"
        /// 「準備OK n/m」の人数
        static let readyCount = "room.readyCount"
        /// ルームパネルのヒント文言（「全員OKで解禁 · あと N人」など）
        static let readyHint = "room.readyHint"
        /// 「準備OK」「準備OKを取り消す」
        static let ready = "room.ready"
        /// 「強制解禁（作成者）」
        static let forceUnlock = "room.forceUnlock"
        /// 見出し行の「候補を追加」
        static let addCandidate = "room.addCandidate"
        /// 「前回見たあとに N件の候補が増えました」
        static let newNotice = "room.newNotice"
        /// 候補が無いときの表示
        static let empty = "room.empty"
        /// 候補が無いときの表示の「候補を追加」
        static let emptyAddCandidate = "room.empty.addCandidate"
        /// 下部の「ガチャを回す」（`RoomGachaBar.Identifier.gacha`）
        static let gacha = RoomGachaBar.Identifier.gacha
        /// ルームが見つからないときの案内
        static let missing = "room.missing"
        /// ルームが見つからないときの「ホームに戻る」
        static let missingBack = "room.missing.back"

        /// 候補のカード
        static func candidate(_ candidateID: String) -> String {
            "room.candidate.\(candidateID)"
        }
    }

    /// NEW の案内の文字の大きさ（03 の S-07「12pt bold」）
    private static let newNoticeSize: CGFloat = 12
    /// 設定の歯車の大きさ
    private static let settingsIconSize: CGFloat = 22
    /// 空の表示のカプセルの直径
    private static let emptyCapsuleSize: CGFloat = 56
    /// 空の表示の点線（`DGButton` の `dashed` と同じ刻み）
    private static let emptyDash: [CGFloat] = [6, 4]

    @State private var model: RoomModel
    /// 行き先を開く（親の `NavigationStack` に積む・シートやフルスクリーンカバーで出す）
    private let navigate: (AppRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var settingsIconSize = RoomView.settingsIconSize

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - navigate: 行き先を開く処理
    init(model: RoomModel, navigate: @escaping (AppRoute) -> Void) {
        _model = State(initialValue: model)
        self.navigate = navigate
    }

    var body: some View {
        // iPad の広い画面では、左にルームパネルとガチャのボタン、右に候補の一覧を並べる（`RoomLayout`）
        RoomLayout(allowsSplit: model.loadState != .missing) {
            header
        } content: {
            content
        } sidePane: {
            sidePaneContent
        } mainPane: {
            candidatesPaneContent
        } bottomBar: {
            bottomBar
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .onChange(of: model.canForceUnlock) {
            model.closeUnavailableConfirmation()
        }
        // 強制解禁を送っている途中は、端からのスワイプでも戻らせない
        .lockNavigation(while: model.isSendingForceUnlock)
        .task {
            await model.observe()
        }
        // 02 の §3.3「ルーム画面を離れたときに lastSeenAt を更新する」
        .onDisappear {
            model.leftRoom()
        }
        // ほかの人が回したら、S-13 を開いて同じ演出を再生する（F-41）。
        // このルームの S-13・S-14 のカバーを出しているときは開き直さない（カバーの中の S-13 が再生する。`AppPresentation.open`）
        .onChange(of: model.drawToReplay) { _, drawID in
            guard drawID != nil else {
                return
            }
            model.replayOpened()
            navigate(.gacha(roomID: model.roomID))
        }
        // 開いたときに行き先が決まっていたら、S-14 を出す（03 の §2。closed は閲覧のみ）
        .onChange(of: model.resultToOpen) { _, drawID in
            guard let drawID else {
                return
            }
            model.resultOpened()
            navigate(.result(roomID: model.roomID, drawID: drawID))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.leftRoom()
            }
        }
    }

    // MARK: - 下部

    /// 下部に固定する「ガチャを回す」とバナー広告（または広告なしの案内）
    private var bottomBar: some View {
        VStack(spacing: 0) {
            RoomGachaBar(state: model.gachaButtonState) {
                navigate(.gacha(roomID: model.roomID))
            } onResult: { drawID in
                navigate(.result(roomID: model.roomID, drawID: drawID))
            }
            BannerAdSlot(screen: .room, room: model.room)
            AdFreeNoticeSlot(screen: .room, room: model.room)
        }
    }

    // MARK: - ヘッダー

    /// 戻る・ルーム名・状態チップ・（作成者だけ）設定。
    ///
    /// アクセシビリティの文字サイズでは、チップを横に並べるとルーム名の幅が 1 文字ほどに潰れるので、
    /// チップはヘッダーから外してスクロールの先頭に置く（`statusChipRow`）
    private var header: some View {
        DGHeader(Text(verbatim: model.room?.name ?? ""), onBack: { dismiss() }, trailing: {
            HStack(spacing: DGSpacing.s4) {
                if !dynamicTypeSize.isAccessibilitySize {
                    statusChip
                }
                if model.isOwner {
                    settingsButton
                }
            }
            .padding(.trailing, model.isOwner ? 0 : DGSpacing.s8)
        })
        // 強制解禁を送っている途中は戻らせない（失敗のトーストをこの画面で出し、もう一度押せるようにするため）
        .disabled(model.isSendingForceUnlock)
    }

    /// 状態チップ（ルームが届くまでは出さない）
    @ViewBuilder private var statusChip: some View {
        if let status = model.room?.status {
            DGStatusChip(status: DGStatusChip.Status(status))
                .fixedSize()
        }
    }

    /// ルーム設定（S-12）の入口。作成者だけに出す
    private var settingsButton: some View {
        Button {
            navigate(.roomSettings(roomID: model.roomID))
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: settingsIconSize))
                .fontWeight(.bold)
                .foregroundStyle(Color.dgInk)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityLabel(Text("ルーム設定"))
        .accessibilityIdentifier(Identifier.settings)
    }

    // MARK: - 中身

    /// 読み込みの状態ごとの中身（1 列のとき）
    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading:
            RoomLoadingPlaceholder.content
        case .missing:
            missingContent
        case .loaded:
            VStack(alignment: .leading, spacing: DGSpacing.s14) {
                if dynamicTypeSize.isAccessibilitySize {
                    statusChip
                }
                roomPanel
                candidatesHeader
                    .padding(.top, DGSpacing.s6)
                candidatesBody
            }
        }
    }

    /// 2 列のときの左の列（ルームパネル）。読み込み中はパネルの形を保つ
    @ViewBuilder private var sidePaneContent: some View {
        if model.loadState == .loaded {
            VStack(alignment: .leading, spacing: DGSpacing.s14) {
                if dynamicTypeSize.isAccessibilitySize {
                    statusChip
                }
                roomPanel
            }
        } else {
            RoomLoadingPlaceholder.sidePane
        }
    }

    /// 2 列のときの右の列（候補の見出し行・NEW の案内・候補）。読み込み中は候補カードの形を保つ
    @ViewBuilder private var candidatesPaneContent: some View {
        if model.loadState == .loaded {
            VStack(alignment: .leading, spacing: DGSpacing.s14) {
                candidatesHeader
                candidatesBody
            }
        } else {
            RoomLoadingPlaceholder.mainPane
        }
    }

    /// ルームパネル（行き先の黒帯・準備OKの人数とメンバー・あなたの投稿）。メンバーを押すとメンバー一覧（S-11）
    private var roomPanel: some View {
        RoomPanel(
            capsuleCount: model.capsuleCount,
            readyCount: model.readyCount,
            memberCount: model.memberCount,
            members: model.displayedMembers,
            myPostCount: model.myPostCount,
            postLimit: model.room?.settings.postLimit ?? 0,
            likeMode: model.room?.settings.likeMode ?? .boost,
            readiness: RoomPanel.Readiness(
                hint: model.readyHint,
                isReady: model.isReady,
                showsButton: model.showsReadyButton,
                canForceUnlock: model.canForceUnlock,
                isForceUnlocking: model.isSendingForceUnlock,
                isConfirmingForceUnlock: $model.isConfirmingForceUnlock,
                onToggleReady: { model.readyTapped() },
                onForceUnlock: { model.forceUnlockTapped() },
                onConfirmForceUnlock: { model.confirmForceUnlockTapped() }
            ),
            invite: memberInvite
        ) {
            navigate(.members(roomID: model.roomID))
        }
    }

    /// 見出し行の下の、NEW の案内と候補カード（0 件なら空の表示）
    @ViewBuilder private var candidatesBody: some View {
        if model.newCount > 0 {
            Text("前回見たあとに \(model.newCount)件の候補が増えました")
                .font(.dgBody(Self.newNoticeSize, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Color.dgAccentText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Identifier.newNotice)
        }
        if model.isEmpty {
            emptyState
        } else {
            candidateList
        }
    }

    /// ルームが無い・読めなくなった（削除された・退出した・作成者に削除された）ときの案内と「ホームに戻る」。
    ///
    /// 自動ではホームに戻さない（自分で退出したときは S-11 がホームに戻すので、ここで重ねて戻したり案内のトーストを出したりしない）
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
            DGButton("ホームに戻る", kind: .secondary) {
                dismiss()
            }
            .accessibilityIdentifier(Identifier.missingBack)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DGSpacing.s16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.missing)
    }
}

extension RoomView {
    // MARK: - 招待

    /// アバターの並びの招待の「＋」（02 の F-04。`drawn`・`closed` では出さず、満員なら押せない「満員」）。押すと招待のシート（S-04）
    private var memberInvite: RoomMemberAvatars.Invite? {
        switch model.inviteAvailability {
        case .available:
            RoomMemberAvatars.Invite(status: .available) {
                if let room = model.inviteDestination {
                    navigate(.inviteMembers(room))
                }
            }
        case .full:
            RoomMemberAvatars.Invite(status: .full)
        case .unavailable:
            nil
        }
    }

    // MARK: - 候補

    /// 「候補」「N件 · 新しい順」と右端の「＋ 候補を追加」。入らなければボタンを下の行に回す
    private var candidatesHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DGSpacing.s8) {
                candidatesTitle
                Spacer(minLength: 0)
                addCandidateButton(identifier: Identifier.addCandidate)
            }
            VStack(alignment: .leading, spacing: DGSpacing.s8) {
                candidatesTitle
                addCandidateButton(identifier: Identifier.addCandidate)
            }
        }
    }

    /// 「候補」と「N件 · 新しい順」
    private var candidatesTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s8) {
            Text("候補")
                .font(.dg(.displaySection))
                .foregroundStyle(Color.dgInk)
                .accessibilityAddTraits(.isHeader)
            Text("\(model.candidates.count)件 · 新しい順")
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
        }
        .fixedSize()
    }

    /// 「＋ 候補を追加」（S-08 へ。投稿できない状態では押せない）
    private func addCandidateButton(identifier: String) -> some View {
        DGButton("候補を追加", icon: "ui-plus", kind: .yellow) {
            navigate(.addCandidate(roomID: model.roomID))
        }
        .disabled(!model.acceptsCandidates)
        .accessibilityIdentifier(identifier)
    }

    /// 候補カードの一覧（新しい順）。経過時間は 1 分ごとに描き直す
    private var candidateList: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: DGSpacing.s14) {
                ForEach(model.rows) { row in
                    candidateCard(row, now: context.date)
                }
            }
        }
    }

    /// 候補カード 1 枚。押すと候補の詳細（S-10）、いいねボタンでいいねを付ける・外す
    private func candidateCard(_ row: RoomCandidateRow, now: Date) -> some View {
        let style = DGCategoryStyle.of(row.category)
        return DGCandidateCard(
            name: row.name,
            meta: "\(row.area) · \(String(localized: style.label))",
            category: style,
            author: row.author,
            elapsed: RelativeTime.text(since: row.createdAt, now: now, calendar: calendar),
            note: row.note,
            isNew: row.isNew,
            highlight: row.highlight.map(DGCandidateCard.Highlight.init),
            likeStatus: row.likeStatus,
            likers: row.likers.map { liker in
                DGLikeRow.Liker(
                    id: liker.id,
                    name: liker.name,
                    color: liker.avatarColorIndex.map(Color.dgAvatar(at:)) ?? Color.dgAvatarNotReadyBg
                )
            },
            level: DGLevelStyle.of(row.odds?.level ?? .flat),
            percent: row.odds?.displayPercent ?? 0,
            maxPercent: row.maxPercent,
            isExcludedFromDraw: row.odds == nil,
            onOpen: {
                navigate(.candidateDetail(roomID: model.roomID, candidateID: row.id))
            },
            onLike: {
                model.likeTapped(row.id)
            }
        )
        .accessibilityIdentifier(Identifier.candidate(row.id))
    }

    /// 候補が 0 件のとき（カプセルのイラスト・案内・「候補を追加」）
    private var emptyState: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        return VStack(spacing: DGSpacing.s12) {
            CapsuleBall(color: .dgCapsule(at: 0))
                .frame(width: Self.emptyCapsuleSize, height: Self.emptyCapsuleSize)
                .accessibilityHidden(true)
            Text("まだ候補がありません。行きたい場所を投稿しよう！")
                .font(.dg(.bodyRegular))
                .foregroundStyle(Color.dgTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Identifier.empty)
            addCandidateButton(identifier: Identifier.emptyAddCandidate)
        }
        .frame(maxWidth: .infinity)
        .padding(DGSpacing.s24)
        .overlay {
            shape.strokeBorder(Color.dgLineDashedStrong, style: StrokeStyle(lineWidth: DGBorder.regular, dash: Self.emptyDash))
        }
    }
}

#Preview("S-07 候補あり") {
    let server = InMemoryServer.demo(.roomWithCandidates)
    NavigationStack {
        RoomView(
            model: RoomModel(
                roomID: DemoScenario.roomID,
                userID: DemoScenario.myUserID,
                repository: server,
                functions: server,
                toasts: DGToastCenter()
            )
        ) { _ in }
    }
}

#Preview("S-07 空") {
    let server = InMemoryServer.demo(.oneRoom)
    NavigationStack {
        RoomView(
            model: RoomModel(
                roomID: DemoScenario.roomID,
                userID: DemoScenario.myUserID,
                repository: server,
                functions: server,
                toasts: DGToastCenter()
            )
        ) { _ in }
    }
}

#Preview("S-07 文字を最大") {
    let server = InMemoryServer.demo(.roomWithCandidates)
    NavigationStack {
        RoomView(
            model: RoomModel(
                roomID: DemoScenario.roomID,
                userID: DemoScenario.myUserID,
                repository: server,
                functions: server,
                toasts: DGToastCenter()
            )
        ) { _ in }
    }
    .dynamicTypeSize(.accessibility5)
}
