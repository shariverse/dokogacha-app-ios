//
//  CandidateDetailView.swift
//  Dokogacha
//

import MapKit
import SwiftUI

/// S-10 候補の詳細（シート）。03 の S-10 のとおり、S-07 の候補カードと同じ情報（カテゴリ・場所名・エリア・ひとこと・
/// 投稿者と経過時間・いいね・出やすさ）に、地図（高さ 200pt）・参考 URL（タップで Safari）・いいねした人の名前を足し、
/// 「マップで開く」と、投稿した本人か作成者なら「この候補を削除」（確認のダイアログ）を並べる。
/// 右上の「…」のメニューには、他人の投稿でまだ報告していなければ「この投稿を報告」（F-14）を置き、理由を選ばせて送る
/// （`CandidateDetailView+Report.swift`）。報告した候補は、ひとことと参考 URL を出さない（02 の §3.5）。
///
/// 地図を押すと、シートの中で S-17 場所の地図へ進む（Discussion #193。S-09 と同じく、シートの中に `NavigationStack` を持つ）。
/// 購読・閉じる判定・送っている途中の取り消しはスタックの外で持つ（S-17 を積んでいる間も候補の削除などに気づいて閉じるため）。
///
/// 標準のナビゲーションバーは使わず、ヘッダー（タイトルと右端の閉じる）を置く（03 の §3）。
/// トーストの窓口はシートの中で持ち、シートの根元に重ねる（アプリの根元のトーストはシートの後ろに隠れるため）。
/// 削除・報告を送っている間は、閉じるボタンと下スワイプで閉じられないようにする。
/// 確認のダイアログは押したボタン（「この候補を削除」・「…」）に付ける（iPad と iOS 26 以降の iPhone では、ボタンを指して出る）。
struct CandidateDetailView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 候補の詳細の画面
        static let screen = "candidateDetail.screen"
        /// 候補カード
        static let card = "candidateDetail.card"
        /// 地図（押すと S-17 へ進む）
        static let map = "candidateDetail.map"
        /// 参考 URL
        static let url = "candidateDetail.url"
        /// いいねした人の名前
        static let likers = "candidateDetail.likers"
        /// 「マップで開く」
        static let openInMaps = "candidateDetail.openInMaps"
        /// 「この候補を削除」
        static let delete = "candidateDetail.delete"
        /// 「…」のメニュー
        static let more = "candidateDetail.more"
        /// 「…」のメニューの「この投稿を報告」
        static let report = "candidateDetail.report"
        /// 閉じるボタン
        static let close = "candidateDetail.close"
    }

    /// 地図の高さ（03 の S-10「地図（高さ200pt）」）
    private static let mapHeight: CGFloat = 200
    /// 「この候補を削除」の文字の大きさ（S-06 の「やめる」と同じテキストボタン）
    private static let deleteSize: CGFloat = 15
    /// 「…」のアイコンの大きさ
    private static let moreIconSize: CGFloat = 20

    @State private var model: CandidateDetailModel
    @State private var toasts: DGToastCenter
    /// 積んでいる S-17 の行き先
    @State private var mapPath: [PlaceMapDestination] = []
    /// 送っている途中なら、端からのスワイプで S-17 から戻るのも止める
    @State private var navigationLock = NavigationLock()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .headline) private var moreIconSize = CandidateDetailView.moreIconSize

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - toasts: 失敗を出すトーストの窓口（`model` に渡したもの。シートの根元に重ねる）
    init(model: CandidateDetailModel, toasts: DGToastCenter) {
        _model = State(initialValue: model)
        _toasts = State(initialValue: toasts)
    }

    var body: some View {
        NavigationStack(path: $mapPath) {
            detail
                // ナビゲーションバーを隠しても、S-17 から端のスワイプで S-10 に戻れるようにする
                .background(InteractivePopGesture(lock: navigationLock))
                .navigationDestination(for: PlaceMapDestination.self) { destination in
                    PlaceMapView(place: destination.place, category: destination.category)
                }
        }
        .environment(\.navigationLock, navigationLock)
        .dgToast(toasts)
        .task {
            await model.observe()
        }
        // 削除できた・候補が消えた・ルームが無くなったら、S-17 を積んでいてもシートを閉じて S-07 に戻る
        .onChange(of: model.shouldClose, initial: true) { _, shouldClose in
            if shouldClose {
                dismiss()
            }
        }
        // 閉じたら、送っている途中の削除・報告を止める（Task が Model を持ち続けないように）
        .onDisappear { model.cancelSending() }
    }

    /// S-10 の中身（スタックの根元）
    private var detail: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, DGSpacing.screenX)
                    .dgContentColumn()
                    .padding(.top, DGSpacing.s4)
                    .padding(.bottom, DGSpacing.s24)
            }
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        // 削除・報告を送っている間は、下スワイプで閉じさせない（申し送り「送信中は戻る・シートの下スワイプを止める」）
        .lockNavigation(while: model.isSending)
        .onChange(of: model.canDelete) {
            model.closeUnavailableConfirmation()
        }
    }

    // MARK: - ヘッダー

    /// タイトルと、右端の「…」（他人の投稿のとき）と閉じるボタン
    private var header: some View {
        DGHeader(Text("候補の詳細"), onBack: nil) {
            HStack(spacing: DGSpacing.s4) {
                if model.canReport {
                    moreMenu
                }
                JoinSheetCloseButton { dismiss() }
                    .disabled(model.isSending)
                    .accessibilityIdentifier(Identifier.close)
            }
        }
        .padding(.leading, DGSpacing.s12)
        .dgContentColumn()
    }

    /// 右上の「…」のメニュー（「この投稿を報告」）
    private var moreMenu: some View {
        Menu {
            Button {
                model.reportTapped()
            } label: {
                Text("この投稿を報告")
            }
            .accessibilityIdentifier(Identifier.report)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: moreIconSize))
                .fontWeight(.bold)
                .foregroundStyle(Color.dgInk)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .disabled(model.isSending)
        .accessibilityLabel(Text("その他の操作"))
        .accessibilityIdentifier(Identifier.more)
        .candidateReportDialog(model)
    }

    // MARK: - 中身

    /// 候補が届くまでは読み込み中の形、届いたら詳細を出す
    @ViewBuilder private var content: some View {
        if let row = model.row, let place = model.place {
            VStack(alignment: .leading, spacing: DGSpacing.s16) {
                TimelineView(.everyMinute) { context in
                    card(row, now: context.date)
                }
                mapButton(place, category: row.category)
                if let url = model.referenceURL {
                    referenceLink(url)
                }
                likersSection
                DGButton("マップで開く", icon: "ui-pin") {
                    model.openInMapsTapped()
                }
                .accessibilityIdentifier(Identifier.openInMaps)
                if model.canDelete {
                    deleteButton
                }
            }
        } else {
            loadingContent
        }
    }

    /// 最初の候補が届くまでの、部品の形を保った読み込み中の表示（03 の §3）
    private var loadingContent: some View {
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
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }

    /// 候補カード（S-07 と同じ部品・同じ値。押しても開かない）
    private func card(_ row: RoomCandidateRow, now: Date) -> some View {
        let style = DGCategoryStyle.of(row.category)
        return DGCandidateCard(
            name: row.name,
            meta: "\(row.area) · \(String(localized: style.label))",
            category: style,
            author: row.author,
            elapsed: RelativeTime.text(since: row.createdAt, now: now, calendar: calendar),
            note: row.note,
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
            onOpen: nil,
            onLike: {
                model.likeTapped()
            }
        )
        .accessibilityIdentifier(Identifier.card)
    }

    /// 場所に 1 本のピンを立てた地図（高さ 200pt。スクロールの邪魔をしないよう、地図そのものは動かせない）のボタン。
    /// 押すとシートの中で S-17 へ進む。S-09 と同じく、右上に拡大のアイコンを重ねて押せることを示す。
    /// 削除・報告を送っている間は押せない（送った結果を見せる S-10 を隠さないため）
    private func mapButton(_ place: Place, category: PlaceCategory) -> some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return Button {
            mapPath.append(PlaceMapDestination(place: place, category: category))
        } label: {
            map(place)
                .frame(maxWidth: .infinity)
                .frame(height: Self.mapHeight)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
                .overlay(alignment: .topTrailing) {
                    PlaceMapExpandBadge()
                        .padding(DGSpacing.s8)
                }
                .contentShape(shape)
        }
        .buttonStyle(.dgBare)
        .disabled(model.isSending)
        .accessibilityLabel(Text("\(place.name)の地図を開く"))
        .accessibilityIdentifier(Identifier.map)
    }

    /// ピン 1 つの地図（最初の範囲は S-17 と同じ。押すのはボタンが受ける）
    private func map(_ place: Place) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        return Map(initialPosition: .region(PlaceMapCamera.initialRegion(for: place)), interactionModes: []) {
            Marker(place.name, coordinate: coordinate)
                .tint(Color.dgAccentPrimary)
        }
        // 地図の上のタップも、地図ではなくボタンに渡す
        .allowsHitTesting(false)
    }

    /// 参考 URL（タップで Safari が開く）
    private func referenceLink(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: DGSpacing.s4) {
            Text("参考URL")
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
            Link(destination: url) {
                Text(verbatim: url.absoluteString)
                    .font(.dgBody(Self.deleteSize, weight: .bold, relativeTo: .body))
                    .foregroundStyle(Color.dgAccentText)
                    .underline()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint(Text("Safari で開きます"))
            .accessibilityIdentifier(Identifier.url)
        }
    }

    /// いいねした人の名前の一覧（いいねが無ければ出さない。カードの「まだいいねはありません」で足りる）
    @ViewBuilder private var likersSection: some View {
        let names = model.likerNames
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                Text("いいねした人")
                    .font(.dg(.displaySection))
                    .foregroundStyle(Color.dgInk)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: names.joined(separator: "、"))
                    .font(.dg(.bodyRegular))
                    .foregroundStyle(Color.dgInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.likers)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// テキストボタン「この候補を削除」（赤文字。押すと確認のダイアログ）
    private var deleteButton: some View {
        Button {
            model.deleteTapped()
        } label: {
            Text("この候補を削除")
                .font(.dgBody(Self.deleteSize, weight: .bold, relativeTo: .body))
                .foregroundStyle(Color.dgAccentText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .disabled(model.isDeleting)
        .accessibilityIdentifier(Identifier.delete)
        .confirmationDialog(
            Text("この候補を削除しますか？"),
            isPresented: $model.isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                model.confirmDeleteTapped()
            } label: {
                Text("削除する")
            }
            Button(role: .cancel) {} label: {
                Text("キャンセル")
            }
        } message: {
            Text("いいねも一緒に消えます。元に戻せません。")
        }
    }
}

#Preview("S-10 自分の候補") {
    let toasts = DGToastCenter()
    let server = InMemoryServer.demo(.roomWithCandidates)
    return Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            CandidateDetailView(
                model: CandidateDetailModel(
                    roomID: DemoScenario.roomID,
                    candidateID: "demo-candidate-3",
                    userID: DemoScenario.myUserID,
                    repository: server,
                    functions: server,
                    toasts: toasts
                ),
                toasts: toasts
            )
        }
}

#Preview("S-10 文字を最大") {
    let toasts = DGToastCenter()
    let server = InMemoryServer.demo(.roomWithCandidates)
    return Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            CandidateDetailView(
                model: CandidateDetailModel(
                    roomID: DemoScenario.roomID,
                    candidateID: "demo-candidate-1",
                    userID: DemoScenario.myUserID,
                    repository: server,
                    functions: server,
                    toasts: toasts
                ),
                toasts: toasts
            )
            .dynamicTypeSize(.accessibility5)
        }
}
