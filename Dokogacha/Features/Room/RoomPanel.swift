//
//  RoomPanel.swift
//  Dokogacha
//

import SwiftUI

/// S-07 のルームパネル（03 の S-07 の 1）。線 2.5・ハードシャドウ・角丸 20 の枠に、上から
/// 行き先の黒帯（`DGDestinationBoard`）・「準備OK n/m」・メンバーのアバター・ヒント文言（F-31）・
/// 「準備OK」「準備OKを取り消す」（F-30）と「強制解禁（作成者）」（F-32）・「あなたの投稿 n/上限件 · いいねの効き方」を並べる。
///
/// メンバーのアバターの並び（押すとメンバー一覧）と末尾の招待の「＋」は `RoomMemberAvatars`。
///
/// 「準備OK」はオフのとき黄色（`accent.secondary`）、オンのとき白の「準備OKを取り消す」（03 の S-07）。
/// 「強制解禁（作成者）」は下線付きの文字だけのボタンで、準備OKのボタンの横に置く。文字を大きくして横に入らなければ縦に並べる。
struct RoomPanel: View {
    /// 準備OKまわりの表示（ボタンを出すか・押したときの処理）
    struct Readiness {
        /// ヒント（抽選の後は nil）
        var hint: ReadyHint?
        /// 自分が準備OKか
        var isReady = false
        /// 「準備OK」「準備OKを取り消す」を出すか（`open`・`unlocked`）
        var showsButton = false
        /// 「強制解禁（作成者）」を出すか（作成者・`open`）
        var canForceUnlock = false
        /// 強制解禁を送っている途中か（ボタンを押せなくする）
        var isForceUnlocking = false
        /// 準備OKのボタンを押したときの処理
        var onToggleReady: () -> Void = {}
        /// 「強制解禁（作成者）」を押したときの処理
        var onForceUnlock: () -> Void = {}
    }

    /// 「準備OK」の文字の大きさ（プロトタイプの 14 の太字）
    private static let readyTitleSize: CGFloat = 14
    /// 「/m」の文字の大きさ
    private static let readyTotalSize: CGFloat = 13
    /// ヒント文言の文字の大きさ（プロトタイプの 13）
    private static let hintSize: CGFloat = 13
    /// 「強制解禁（作成者）」の文字の大きさ（プロトタイプの 13 の太字）
    private static let forceUnlockSize: CGFloat = 13

    /// 行き先表示の「カプセル N個」
    let capsuleCount: Int
    /// 準備OKの人数
    let readyCount: Int
    /// メンバーの人数
    let memberCount: Int
    /// メンバー（参加の早い順）
    let members: [Identified<Member>]
    /// 自分の投稿の数
    let myPostCount: Int
    /// 1 人あたりの投稿数
    let postLimit: Int
    /// いいねの効き方
    let likeMode: LikeMode
    /// 準備OKまわり（ヒント・準備OK・強制解禁）
    var readiness = Readiness()
    /// アバターの並びの末尾の招待の「＋」（nil なら出さない）
    var invite: RoomMemberAvatars.Invite?
    /// メンバーを押したときの処理（メンバー一覧を開く）
    let onOpenMembers: () -> Void

    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        VStack(spacing: 0) {
            DGDestinationBoard(capsuleCount: capsuleCount, placement: .cardTop)
            VStack(alignment: .leading, spacing: DGSpacing.s12) {
                readyHeader
                RoomMemberAvatars(members: members, memberCount: memberCount, invite: invite, onOpenMembers: onOpenMembers)
                if let hint = readiness.hint {
                    hintText(hint)
                }
                if readiness.showsButton || readiness.canForceUnlock {
                    readyActions
                }
                myPostsText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DGSpacing.s16)
            .padding(.top, DGSpacing.s14)
            .padding(.bottom, DGSpacing.s16)
        }
        .background(Color.dgSurfaceCard)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.strong))
        .dgHardShadow(cornerRadius: DGRadius.lg)
    }

    /// 「準備OK」と右端の「n/m」（n は見出し 20、「/m」は 13）
    private var readyHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s8) {
            Text("準備OK")
                .font(.dgBody(Self.readyTitleSize, weight: .black, relativeTo: .subheadline))
                .foregroundStyle(Color.dgInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 右の人数を「準備OK n/m人」と読むので、ここでは読まない（同じ語を 2 回読まない）
                .accessibilityHidden(true)
            let total = Text(verbatim: "/\(memberCount)")
                .font(.dgDisplay(Self.readyTotalSize, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextSecondary)
            Text("\(Text(verbatim: "\(readyCount)"))\(total)")
                .font(.dg(.displayS))
                .foregroundStyle(Color.dgInk)
                .accessibilityLabel(Text("準備OK \(readyCount)/\(memberCount)人"))
                .accessibilityIdentifier(RoomView.Identifier.readyCount)
        }
    }

    /// ヒント文言（02 の §5.2）
    private func hintText(_ hint: ReadyHint) -> some View {
        Group {
            switch hint {
            case .unlocked:
                Text("条件を満たしました。誰が回してもOK！")
            case .forcedUnlocked:
                Text("作成者が解禁しました。いつでも回せます")
            case let .waitingForAll(remaining):
                Text("全員OKで解禁 · あと \(remaining)人")
            case let .waitingForMajority(remaining):
                Text("過半数OKで解禁 · あと \(remaining)人")
            case let .waitingForDeadline(deadlineAt):
                Text("締切 \(ReadyHint.deadlineText(deadlineAt, timeZone: timeZone, locale: locale)) に解禁されます")
            }
        }
        .font(.dgBody(Self.hintSize, relativeTo: .footnote))
        .foregroundStyle(Color.dgTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(RoomView.Identifier.readyHint)
    }

    /// 「準備OK」「準備OKを取り消す」と「強制解禁（作成者）」。横に入らなければ縦に並べる
    private var readyActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s8) {
                readyButtons
            }
            VStack(alignment: .leading, spacing: DGSpacing.s8) {
                readyButtons
            }
        }
    }

    /// 準備OKのボタンと強制解禁のボタン（並べ方は `readyActions`）
    @ViewBuilder private var readyButtons: some View {
        if readiness.showsButton {
            Group {
                if readiness.isReady {
                    DGButton("準備OKを取り消す", kind: .secondary, fillsWidth: false, action: readiness.onToggleReady)
                } else {
                    DGButton("準備OK", kind: .yellow, action: readiness.onToggleReady)
                }
            }
            .accessibilityIdentifier(RoomView.Identifier.ready)
        }
        if readiness.canForceUnlock {
            Button(action: readiness.onForceUnlock) {
                Text("強制解禁（作成者）")
                    .font(.dgBody(Self.forceUnlockSize, weight: .bold, relativeTo: .footnote))
                    .underline()
                    .foregroundStyle(Color.dgAccentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DGSpacing.s12)
                    .frame(minHeight: DGMetrics.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dgBare)
            .disabled(readiness.isForceUnlocking)
            .accessibilityHint(Text("確認のあと、準備OKが揃っていなくてもガチャを解禁します"))
            .accessibilityIdentifier(RoomView.Identifier.forceUnlock)
        }
    }

    /// 「あなたの投稿 n/上限件 · 共感ブースト（みんな平等）」
    private var myPostsText: some View {
        let mode: Text = likeMode == .equal ? Text("みんな平等") : Text("共感ブースト")
        return Text("あなたの投稿 \(myPostCount)/\(postLimit)件 · \(mode)")
            .font(.dg(.bodyCaption))
            .foregroundStyle(Color.dgTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
