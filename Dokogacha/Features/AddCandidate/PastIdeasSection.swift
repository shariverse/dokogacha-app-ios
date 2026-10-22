//
//  PastIdeasSection.swift
//  Dokogacha
//

import SwiftUI

/// S-08 の「過去のアイデア」のタブの中身（03 の S-08 の「過去のアイデア」・02 の §3.4 F-13）。
///
/// 1. 補足「このとき当たらなかった候補です。今回もう一度入れられます」（ルームが複数あっても一覧の上に 1 回だけ出す）
/// 2. ルームごとの見出し（黒帯）「{ルーム名} {M/D}」＋右に「{当選場所} ゆき」
/// 3. `DGPlaceRow`（「エリア · カテゴリ · 前回 Nいいね」、前回のいいねが 3 以上で「前回惜しかった」）、右に「持ち込む」→ S-09
/// 4. 0 件:「過去のアイデアはまだありません。ルームが終わると、外れた候補がここに貯まります」
///
/// 行の「持ち込む」「追加済み」「上限」は「場所を探す」と同じ判定（`AddCandidateModel.availability(of:)`）
struct PastIdeasSection: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 0 件の表示
        static let empty = AddCandidateView.Identifier.pastIdeas
        /// 補足の文言
        static let note = "addCandidate.pastIdeas.note"

        /// ルームの見出し
        static func group(_ roomID: String) -> String {
            "addCandidate.pastIdeas.group.\(roomID)"
        }

        /// 過去のアイデアの行
        static func idea(_ ideaID: String) -> String {
            "addCandidate.pastIdea.\(ideaID)"
        }

        /// 過去のアイデアの行の「持ち込む」ボタン
        static func bring(_ ideaID: String) -> String {
            "addCandidate.pastIdea.\(ideaID).bring"
        }
    }

    /// 見出しのルーム名の大きさ（プロトタイプの 15）
    private static let groupTitleSize: CGFloat = 15
    /// 見出しの日付・「◯◯ ゆき」の大きさ（プロトタイプの 12）
    private static let groupDetailSize: CGFloat = 12
    /// 見出しの角丸（プロトタイプは 14 だが、トークンに無い値なので、下に並べる PlaceRow と同じ `radius.m` にそろえる。PR #83 の持ち越し）
    private static let groupRadius: CGFloat = DGRadius.md
    /// 0 件の文言の大きさ（「場所を探す」の「見つかりませんでした」と同じ 13）
    private static let messageSize: CGFloat = 13
    /// 読み込み中に出す行の数
    private static let placeholderRows = 3

    /// 画面の状態（S-08 と同じもの）
    let model: AddCandidateModel

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        if !model.hasLoadedPastIdeas {
            loadingPlaceholder
        } else if model.isPastIdeasEmpty {
            Text("過去のアイデアはまだありません。ルームが終わると、外れた候補がここに貯まります")
                .font(.dgBody(Self.messageSize, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DGSpacing.s24)
                .accessibilityIdentifier(Identifier.empty)
        } else {
            LazyVStack(alignment: .leading, spacing: DGSpacing.s10) {
                Text("このとき当たらなかった候補です。今回もう一度入れられます")
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Identifier.note)
                ForEach(model.pastIdeaGroups) { group in
                    groupHeader(group)
                    ForEach(group.ideas) { idea in
                        ideaRow(idea)
                    }
                }
            }
        }
    }

    // MARK: - 見出し

    /// ルームの見出し（黒帯）。文字を大きくして横に収まらなければ、「◯◯ ゆき」を下の行に回す
    private func groupHeader(_ group: PastIdeaGroup) -> some View {
        let date = DGDateText.monthDay(group.closedAt, timeZone: timeZone)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s10) {
                groupTitle(group, date: date)
                    .frame(maxWidth: .infinity, alignment: .leading)
                groupWinner(group)
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                groupTitle(group, date: date)
                groupWinner(group)
            }
        }
        .padding(.vertical, DGSpacing.s10)
        .padding(.horizontal, DGSpacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dgInk, in: RoundedRectangle(cornerRadius: Self.groupRadius))
        .padding(.top, DGSpacing.s6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groupAccessibilityLabel(group))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(Identifier.group(group.id))
    }

    /// 見出しの「{ルーム名} {M/D}」
    private func groupTitle(_ group: PastIdeaGroup, date: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s6) {
            Text(verbatim: group.roomName)
                .font(.dgDisplay(Self.groupTitleSize, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextOnAccent)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: date)
                .font(.dgDisplay(Self.groupDetailSize, relativeTo: .caption))
                .foregroundStyle(Color.dgTextOnInk)
                .fixedSize()
        }
    }

    /// 見出しの「{当選場所} ゆき」（当選の場所が分からなければ出さない）
    @ViewBuilder private func groupWinner(_ group: PastIdeaGroup) -> some View {
        if !group.winnerName.isEmpty {
            Text("\(group.winnerName) ゆき")
                .font(.dgBody(Self.groupDetailSize, weight: .bold, relativeTo: .caption))
                .foregroundStyle(Color.dgAccentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 見出しの読み上げ（日付は「8月24日」の形で読む。「8/24」は数字の並びとして読まれるため）
    private func groupAccessibilityLabel(_ group: PastIdeaGroup) -> Text {
        let date = DGDateText.monthDayJapanese(group.closedAt, timeZone: timeZone)
        if group.winnerName.isEmpty {
            return Text("\(group.roomName)、\(date)")
        }
        return Text("\(group.roomName)、\(date)、\(group.winnerName) ゆき")
    }

    // MARK: - 行

    /// 過去のアイデアの行（03 の S-08 の 3）。「持ち込む」「追加済み」「上限」
    private func ideaRow(_ idea: Identified<PastIdea>) -> some View {
        let style = DGCategoryStyle.of(idea.category)
        let availability = model.availability(of: idea)
        let categoryLabel = String(localized: style.label)
        let likes = String(localized: "前回 \(idea.prevLikeCount)いいね")
        let meta = [idea.place.area, categoryLabel, likes].filter { !$0.isEmpty }.joined(separator: " · ")
        return DGPlaceRow(
            name: idea.place.name,
            meta: meta,
            category: style,
            badge: PastIdeaList.isCloseCall(idea.value) ? "前回惜しかった" : nil,
            actionTitle: Self.actionTitle(availability),
            isActionEnabled: availability.isEnabled,
            actionHint: availability.isEnabled ? Text("\(idea.place.name)を今回のルームに持ち込みます") : nil,
            actionIdentifier: Identifier.bring(idea.id)
        ) {
            model.bringTapped(idea)
        }
        .accessibilityIdentifier(Identifier.idea(idea.id))
    }

    /// 行のボタンの文言
    private static func actionTitle(_ availability: PlaceAddAvailability) -> LocalizedStringKey {
        switch availability {
        case .addable, .duplicate, .unavailable:
            "持ち込む"
        case .added:
            "追加済み"
        case .limitReached:
            "上限"
        }
    }

    /// 読み込み中の、行の形を保った表示（03 の §3）
    private var loadingPlaceholder: some View {
        VStack(spacing: DGSpacing.s10) {
            ForEach(0..<Self.placeholderRows, id: \.self) { _ in
                DGPlaceRow(
                    name: String(localized: "読み込み中"),
                    meta: String(localized: "読み込み中"),
                    category: .town,
                    actionTitle: "持ち込む",
                    isActionEnabled: false
                ) {}
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("過去のアイデアを読み込んでいます"))
    }
}
