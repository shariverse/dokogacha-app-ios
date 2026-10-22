//
//  DGCandidateCard.swift
//  Dokogacha
//
//  候補カード（`04_design_system.md` の §4 の CandidateCard・03 の S-07・02 の F-20〜F-23）。
//

import SwiftUI

/// ルーム画面（S-07）に並べる候補 1 件分のカード。
///
/// 上から、カテゴリタイル 52・NEW バッジ・候補名・エリアとカテゴリ・ひとことの吹き出し・投稿者と経過時間、右上にいいねボタン。
/// その下に LikeRow、点線の区切り、出やすさのメーター。白・線 2・角丸 18・余白 14。
/// 人気カード（F-23）は背景 `surface.highlight`・線 2.5・ハードシャドウ・上の余白 20 にし、左上にリボン（「みんな推し」「全員いいね」）を重ねる。
///
/// ドメインのモデルには依存させず、表示に要る値だけを受け取る（人気・レベル・表示 % などの判定は呼び出し側で行う）。
/// カードを押したときの処理（S-10 を開く）は `onOpen` で受け取る。カードのどこを押しても開き（いいねボタンを除く）、
/// VoiceOver では候補の情報の列を 1 つのボタンとして読む。
///
/// リボンはカードの上の縁に中心をそろえて上にはみ出すので、はみ出す分（リボンの高さの半分）をカードの上に余白として取る。
/// 余白を取らないと、並べたときに上のカードや見出しに重なる（文字を大きくするとリボンも高くなり、一覧の間隔 14 を超える）。
///
/// 引き直しで抽選の対象から外れた候補（`isExcludedFromDraw`）は、出やすさのメーターの代わりに外れたことを出す（表示 % を出さない）。
struct DGCandidateCard: View {
    /// 候補の投稿者
    nonisolated enum Author: Equatable, Sendable {
        /// 自分の投稿
        case me
        /// ほかのメンバーの投稿（表示名）
        case member(String)
        /// 退出したメンバーの投稿（02 の F-06・F-05 で投稿は残る）
        case departed
    }

    /// 人気の強調（F-23）の種類
    nonisolated enum Highlight: CaseIterable, Sendable {
        /// 投稿者以外のメンバーの 6 割以上がいいね（「みんな推し」）
        case popular
        /// 投稿者以外のメンバー全員がいいね（「全員いいね」）
        case allLiked

        /// リボンの文言
        var title: LocalizedStringResource {
            switch self {
            case .popular: "みんな推し"
            case .allLiked: "全員いいね"
            }
        }
    }

    /// カードの角丸（04 の §4 の値。`radius.l` の幅 18〜20 の下の端）
    private static let cornerRadius: CGFloat = 18
    /// ピンのアイコンの一辺
    private static let pinSize: CGFloat = 12
    /// ピンと文言の間（プロトタイプの値）
    private static let pinSpacing: CGFloat = 3
    /// ひとことの文字の大きさ
    private static let noteSize: CGFloat = 13
    /// ひとことの吹き出しの左上の角丸（ほかの角は `radius.s`）
    private static let noteTailRadius: CGFloat = 4
    /// NEW バッジの文字の大きさ
    private static let newBadgeSize: CGFloat = 11
    /// NEW バッジの左右の余白
    private static let newBadgeHorizontalPadding: CGFloat = 7
    /// NEW バッジの上下の余白（プロトタイプの値）
    private static let newBadgeVerticalPadding: CGFloat = 1
    /// NEW バッジの字間（em）
    private static let newBadgeTracking: CGFloat = 0.06
    /// リボンの星の一辺
    private static let ribbonStarSize: CGFloat = 13
    /// リボンの上下の余白
    private static let ribbonVerticalPadding: CGFloat = 3
    /// リボンの角丸
    private static let ribbonCornerRadius: CGFloat = 8
    /// リボンの左端の位置（カードの左端から）
    private static let ribbonLeading: CGFloat = 14
    /// 抽選の対象から外れた候補の文言の大きさ（メーターの代わりに出す）
    private static let excludedTextSize: CGFloat = 12

    /// 候補名（場所名）
    let name: String
    /// 「エリア · カテゴリ」
    let meta: String
    /// カテゴリ（タイルの色とアイコン）
    let category: DGCategoryStyle
    /// 投稿者
    let author: Author
    /// 経過時間の文言（F-12 の「3日前」など。呼び出し側で作る）
    let elapsed: String
    /// ひとこと。無ければ `nil`
    var note: String?
    /// NEW バッジを付けるか（F-12）
    var isNew = false
    /// 人気の強調。強調しないなら `nil`
    var highlight: Highlight?
    /// いいねボタンの状態
    let likeStatus: DGLikeButton.Status
    /// いいねした人
    let likers: [DGLikeRow.Liker]
    /// 出やすさのレベル（F-22）
    let level: DGLevelStyle
    /// 表示 %（F-21）
    let percent: Int
    /// 全候補の中で最大の表示 %（メーターの長さに使う）
    let maxPercent: Int
    /// 引き直しで抽選の対象から外れた候補か（メーターの代わりに外れたことを出し、`level`・`percent` は使わない）
    var isExcludedFromDraw = false
    /// カードを押したときの処理（S-10 の候補の詳細を開く）。nil なら押せない
    var onOpen: (() -> Void)?
    /// いいねボタンを押したときの処理
    let onLike: () -> Void

    /// リボンの高さ（はみ出す分の余白に使う。リボンが無ければ 0）
    @State private var ribbonHeight: CGFloat = 0

    /// 人気カードの上の余白。リボンが文字の大きさで伸びても中身に重ならないよう、Dynamic Type に合わせて広げる
    @ScaledMetric(relativeTo: .caption) private var popularTopPadding = DGSpacing.popularCardTopPadding
    /// ピンのアイコンを Dynamic Type に合わせて大きくする倍率
    @ScaledMetric(relativeTo: .caption) private var iconScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            header
            DGLikeRow(likers: likers, isPopular: highlight != nil, cardBackground: background)
            DGDashedLine()
            if isExcludedFromDraw {
                excludedNotice
            } else {
                DGProbabilityMeter(level: level, percent: percent, maxPercent: maxPercent)
            }
        }
        .padding(DGSpacing.cardPadding)
        .padding(.top, highlight != nil ? popularTopPadding - DGSpacing.cardPadding : 0)
        .background(background, in: shape)
        .overlay(shape.strokeBorder(Color.dgInk, lineWidth: highlight != nil ? DGBorder.strong : DGBorder.regular))
        .modifier(PopularShadow(isOn: highlight != nil, cornerRadius: Self.cornerRadius))
        .contentShape(shape)
        .onTapGesture {
            onOpen?()
        }
        .overlay(alignment: .topLeading) {
            if let highlight {
                ribbon(highlight)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        ribbonHeight = height
                    }
            }
        }
        // リボンが上にはみ出す分（高さの半分）を、カードの上に余白として取る
        .padding(.top, highlight != nil ? ribbonHeight / 2 : 0)
        .accessibilityElement(children: .contain)
    }

    /// 引き直しで抽選の対象から外れた候補の、メーターの代わりの文言
    private var excludedNotice: some View {
        Text("引き直しで抽選の対象から外れました")
            .font(.dgBody(Self.excludedTextSize, weight: .bold, relativeTo: .caption))
            .foregroundStyle(Color.dgTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// カテゴリタイル・候補の情報・いいねボタン。
    ///
    /// アクセシビリティの文字サイズでは、横に 3 つ並べると候補の情報の列が細くなりすぎるので、
    /// タイルといいねボタンを上の行に置き、候補の情報をカードの幅いっぱいに出す。
    @ViewBuilder private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DGSpacing.s12) {
                HStack(alignment: .top, spacing: DGSpacing.s12) {
                    DGCategoryTile(category: category, size: .large)
                    Spacer(minLength: 0)
                    DGLikeButton(state: likeStatus, action: onLike)
                }
                details
            }
        } else {
            HStack(alignment: .top, spacing: DGSpacing.s12) {
                DGCategoryTile(category: category, size: .large)
                details
                    .frame(maxWidth: .infinity, alignment: .leading)
                DGLikeButton(state: likeStatus, action: onLike)
            }
        }
    }

    /// カードの背景（人気カードは `surface.highlight`）
    private var background: Color {
        highlight != nil ? .dgSurfaceHighlight : .dgSurfaceCard
    }

    /// 候補名からひとこと・投稿者までの列。押せるときは、VoiceOver で 1 つのボタン（候補の詳細を開く）として読む
    private var details: some View {
        detailsColumn
            .modifier(OpenableDetails(onOpen: onOpen))
    }

    /// 候補名からひとこと・投稿者までの列の中身
    private var detailsColumn: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s4) {
            HStack(spacing: DGSpacing.s6) {
                if isNew {
                    newBadge
                }
                Text(verbatim: name)
                    .font(.dg(.bodyTitle))
                    .foregroundStyle(Color.dgInk)
            }
            HStack(alignment: .firstTextBaseline, spacing: Self.pinSpacing) {
                Image("ui-pin")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.pinSize * iconScale, height: Self.pinSize * iconScale)
                    .accessibilityHidden(true)
                Text(verbatim: meta)
                    .font(.dg(.bodyCaption))
            }
            .foregroundStyle(Color.dgTextSecondary)
            if let note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.dgBody(Self.noteSize, relativeTo: .subheadline))
                    .foregroundStyle(Color.dgInk)
                    .padding(.horizontal, DGSpacing.s10)
                    .padding(.vertical, DGSpacing.s6)
                    .background(
                        Color.dgSurfaceSubtle,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: Self.noteTailRadius,
                            bottomLeadingRadius: DGRadius.sm,
                            bottomTrailingRadius: DGRadius.sm,
                            topTrailingRadius: DGRadius.sm
                        )
                    )
            }
            Text("\(authorText) · \(elapsed)")
                .font(.dg(.bodyCaption))
                .foregroundStyle(Color.dgTextSecondary)
        }
    }

    /// 「◯◯さんの投稿」「あなたの投稿」
    private var authorText: Text {
        switch author {
        case .me: Text("あなたの投稿")
        case let .member(name): Text("\(name)さんの投稿")
        case .departed: Text("退出したメンバーの投稿")
        }
    }

    /// NEW バッジ
    private var newBadge: some View {
        Text(verbatim: "NEW")
            .font(.dgDisplay(Self.newBadgeSize, relativeTo: .caption))
            .tracking(DGTracking.points(Self.newBadgeTracking, fontSize: Self.newBadgeSize))
            .foregroundStyle(Color.dgTextOnAccent)
            .padding(.horizontal, Self.newBadgeHorizontalPadding)
            .padding(.vertical, Self.newBadgeVerticalPadding)
            .background(Color.dgAccentText, in: RoundedRectangle(cornerRadius: DGRadius.xs))
    }

    /// 左上のリボン（上の縁に中心をそろえて重ねる）
    private func ribbon(_ highlight: Highlight) -> some View {
        HStack(spacing: DGSpacing.s4) {
            Image("ui-star")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: Self.ribbonStarSize * iconScale, height: Self.ribbonStarSize * iconScale)
                .accessibilityHidden(true)
            Text(highlight.title)
                .font(.dg(.displayTag))
        }
        .foregroundStyle(Color.dgAccentSecondary)
        .padding(.horizontal, DGSpacing.s10)
        .padding(.vertical, Self.ribbonVerticalPadding)
        .background(Color.dgInk, in: RoundedRectangle(cornerRadius: Self.ribbonCornerRadius))
        .padding(.leading, Self.ribbonLeading)
        // リボンの縦の中心をカードの上の縁にそろえる（04 の §4「y−13」。文字が大きくなっても縁にかかる位置を保つ）。
        // overlay の中では alignmentGuide が効かなかったので、自分の高さの半分だけ上にずらす
        .visualEffect { content, proxy in
            content.offset(y: -proxy.size.height / 2)
        }
    }
}

/// 押せる候補の情報の列を、VoiceOver で 1 つのボタンとして読ませる（押すと候補の詳細を開く）。押せないときは 1 つの要素として読ませる。
///
/// カードの中にいいねボタンがあるので、カード全体を `Button` にはできない（ボタンの入れ子になる）。
/// 見た目の上の「押す」はカードの `onTapGesture` で受け、VoiceOver の操作はこの列で受ける。
private struct OpenableDetails: ViewModifier {
    let onOpen: (() -> Void)?

    func body(content: Content) -> some View {
        if let onOpen {
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("候補の詳細を開きます"))
                .accessibilityAction(.default) { onOpen() }
        } else {
            // 押せないカード（S-10）でも、名前・メタ情報・ひとこと・投稿者をばらばらに読まず 1 つにまとめる
            content
                .accessibilityElement(children: .combine)
        }
    }
}

/// 人気カードのときだけハードシャドウを付ける。
private struct PopularShadow: ViewModifier {
    let isOn: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isOn {
            content.dgHardShadow(cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}

/// Preview 用のいいねした人
private let previewLikers: [DGLikeRow.Liker] = [
    DGLikeRow.Liker(id: "kenta", name: "けんた", color: .dgAvatar(at: 1)),
    DGLikeRow.Liker(id: "misaki", name: "みさき", color: .dgAvatar(at: 2)),
    DGLikeRow.Liker(id: "soma", name: "そうま", color: .dgAvatar(at: 3)),
    DGLikeRow.Liker(id: "me", name: "あなた", color: .dgAvatar(at: 4))
]

#Preview("CandidateCard 状態ごと") {
    ScrollView {
        VStack(spacing: DGSpacing.s22) {
            DGCandidateCard(
                name: "高尾山",
                meta: "東京・八王子市 · 自然",
                category: .nature,
                author: .member("みさき"),
                elapsed: "3日前",
                note: "紅葉シーズンにちょうどいい",
                highlight: .allLiked,
                likeStatus: .liked,
                likers: previewLikers,
                level: .high,
                percent: 16,
                maxPercent: 16
            ) {}
            DGCandidateCard(
                name: "チームラボプラネッツ TOKYO",
                meta: "東京・江東区 · アート・美術館",
                category: .art,
                author: .member("けんた"),
                elapsed: "2日前",
                note: "水に入るやつ",
                highlight: .popular,
                likeStatus: .notLiked,
                likers: Array(previewLikers.prefix(3)),
                level: .high,
                percent: 15,
                maxPercent: 16
            ) {}
            DGCandidateCard(
                name: "長瀞ライン下り",
                meta: "埼玉・秩父郡 · アクティビティ",
                category: .activity,
                author: .member("そうま"),
                elapsed: "3時間前",
                note: "川下り！",
                isNew: true,
                likeStatus: .notLiked,
                likers: [],
                level: .low,
                percent: 5,
                maxPercent: 16
            ) {}
            DGCandidateCard(
                name: "東京ディズニーシー",
                meta: "千葉・浦安市 · テーマパーク",
                category: .park,
                author: .me,
                elapsed: "5時間前",
                likeStatus: .mine,
                likers: Array(previewLikers.prefix(2)),
                level: .mid,
                percent: 13,
                maxPercent: 16
            ) {}
        }
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
}

#Preview("CandidateCard みんな平等") {
    VStack(spacing: DGSpacing.s14) {
        DGCandidateCard(
            name: "横浜中華街",
            meta: "神奈川・横浜市 · グルメ",
            category: .food,
            author: .departed,
            elapsed: "10/12",
            note: "食べ歩きしたい",
            likeStatus: .notLiked,
            likers: Array(previewLikers.prefix(1)),
            level: .flat,
            percent: 13,
            maxPercent: 13
        ) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("CandidateCard 抽選の対象外") {
    VStack(spacing: DGSpacing.s14) {
        DGCandidateCard(
            name: "高尾山",
            meta: "東京・八王子市 · 自然",
            category: .nature,
            author: .member("みさき"),
            elapsed: "昨日",
            highlight: .popular,
            likeStatus: .notLiked,
            likers: Array(previewLikers.prefix(3)),
            level: .mid,
            percent: 0,
            maxPercent: 0,
            isExcludedFromDraw: true
        ) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("CandidateCard 文字を最大") {
    ScrollView {
        VStack(spacing: DGSpacing.s22) {
            DGCandidateCard(
                name: "高尾山",
                meta: "東京・八王子市 · 自然",
                category: .nature,
                author: .member("みさき"),
                elapsed: "3日前",
                note: "紅葉シーズンにちょうどいい",
                highlight: .popular,
                likeStatus: .liked,
                likers: previewLikers,
                level: .high,
                percent: 16,
                maxPercent: 16
            ) {}
            DGCandidateCard(
                name: "長瀞ライン下り",
                meta: "埼玉・秩父郡 · アクティビティ",
                category: .activity,
                author: .me,
                elapsed: "3時間前",
                isNew: true,
                likeStatus: .mine,
                likers: [],
                level: .low,
                percent: 5,
                maxPercent: 16
            ) {}
        }
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
