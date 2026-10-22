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
/// ルームパネルは `RoomPanel`（準備OKのボタン・ヒント文言・強制解禁 F-30〜32 を含む）。強制解禁の確認のダイアログはこの画面で出し、
/// 送っている途中はヘッダー（戻る・設定）を押せなくする。バナー広告（F-50）はタスク 36 で下部に足す。
/// `drawn` のルームを開いたときに結果を自動で出す（03 の §2）のはタスク 28。
struct RoomView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// ルームの画面
        static let screen = "room.screen"
        /// ヘッダーの設定（作成者だけ）
        static let settings = "room.settings"
        /// ルームパネルのメンバー（押すとメンバー一覧）
        static let members = "room.members"
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
        /// 下部の「ガチャを回す」
        static let gacha = "room.gacha"
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
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, DGSpacing.screenX)
                    .padding(.top, DGSpacing.s4)
                    .padding(.bottom, DGSpacing.s16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            gachaBar
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .confirmationDialog(
            Text("まだ準備OKしていない人がいます。ガチャを解禁しますか？"),
            isPresented: $model.isConfirmingForceUnlock,
            titleVisibility: .visible
        ) {
            Button("解禁する") {
                model.confirmForceUnlockTapped()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .task {
            await model.observe()
        }
        // 02 の §3.3「ルーム画面を離れたときに lastSeenAt を更新する」
        .onDisappear {
            model.leftRoom()
        }
        // ほかの人が回したら、S-13 を開いて同じ演出を再生する（F-41）
        .onChange(of: model.drawToReplay) { _, drawID in
            guard drawID != nil else {
                return
            }
            model.replayOpened()
            navigate(.gacha(roomID: model.roomID))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.leftRoom()
            }
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
        .disabled(model.isForceUnlocking)
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

    /// 読み込みの状態ごとの中身
    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading:
            loadingContent
        case .missing:
            missingContent
        case .loaded:
            VStack(alignment: .leading, spacing: DGSpacing.s14) {
                if dynamicTypeSize.isAccessibilitySize {
                    statusChip
                }
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
                        isForceUnlocking: model.isForceUnlocking,
                        onToggleReady: { model.readyTapped() },
                        onForceUnlock: { model.forceUnlockTapped() }
                    )
                ) {
                    navigate(.members(roomID: model.roomID))
                }
                candidatesHeader
                    .padding(.top, DGSpacing.s6)
                if model.newCount > 0 {
                    Text("前回見たあとに \(model.newCount)件の候補が増えました")
                        .font(.dgBody(Self.newNoticeSize, weight: .black, relativeTo: .caption))
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

    /// 最初のルームが届くまでの、部品の形を保った読み込み中の表示（03 の §3）
    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s14) {
            RoomPanel(
                capsuleCount: 0,
                readyCount: 0,
                memberCount: 0,
                members: [],
                myPostCount: 0,
                postLimit: 0,
                likeMode: .boost
            ) {}
            DGCandidateCard(
                name: String(localized: "読み込み中"),
                meta: String(localized: "読み込み中"),
                category: .town,
                author: .departed,
                elapsed: "",
                likeStatus: .locked,
                likers: [],
                level: .flat,
                percent: 0,
                maxPercent: 0
            ) {}
        }
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }
}

extension RoomView {
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

extension RoomView {
    // MARK: - 下部

    /// 下部に固定する「ガチャを回す」（03 の S-07 の GachaCTA）。`drawn`・`closed` と読み込み中は出さない
    @ViewBuilder private var gachaBar: some View {
        if let state = model.gachaButtonState {
            Group {
                switch state {
                case .ready:
                    DGButton("ガチャを回す") {
                        navigate(.gacha(roomID: model.roomID))
                    }
                case .waiting:
                    DGButton("準備OKが揃うと回せます") {}
                        .disabled(true)
                }
            }
            .accessibilityIdentifier(Identifier.gacha)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.vertical, DGSpacing.s10)
            .frame(maxWidth: .infinity)
            .background(Color.dgBgBase)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.dgInk)
                    .frame(height: DGBorder.regular)
            }
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
