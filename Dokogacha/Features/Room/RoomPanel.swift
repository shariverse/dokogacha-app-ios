//
//  RoomPanel.swift
//  Dokogacha
//

import SwiftUI

/// S-07 のルームパネル（03 の S-07 の 1）。線 2.5・ハードシャドウ・角丸 20 の枠に、上から
/// 行き先の黒帯（`DGDestinationBoard`）・「準備OK n/m」・メンバーのアバター・ヒント文言（F-31）・
/// 「準備OK」「準備OKを取り消す」（F-30）と「強制解禁（作成者）」（F-32）・「あなたの投稿 n/上限件 · いいねの効き方」を並べる。
///
/// メンバーのアバターは 44＋名前 11 で、準備OKの人にはチェックのバッジを付ける。7 人以上は 6 人＋「+N」（`DGAvatarOverflow`）。
/// 押すとメンバー一覧（S-11）を開く。横には並べきれないので、幅に合わせて折り返す（横スクロールにしない。端からのスワイプで戻る操作とぶつけないため）。
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

    /// 並べるアバターの上限（03 の S-07「7人以上は6人＋「+N」」）
    private static let maxVisibleAvatars = 6
    /// メンバーの列の幅（プロトタイプの 56。アバター 44 と名前）
    private static let memberColumnWidth: CGFloat = 56
    /// メンバーの名前の大きさ（03 の S-07「名前11pt」）
    private static let memberNameSize: CGFloat = 11
    /// 「+N」の文字の大きさ
    private static let overflowTextSize: CGFloat = 15
    /// 「+N」を大きくする上限（円の大きさは変えないので、2〜3 文字が円に収まる大きさで止める）
    private static let overflowMaxTypeSize = DynamicTypeSize.xxxLarge
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
    /// メンバーを押したときの処理（メンバー一覧を開く）
    let onOpenMembers: () -> Void

    @ScaledMetric(relativeTo: .caption) private var memberColumnWidth = RoomPanel.memberColumnWidth
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        VStack(spacing: 0) {
            DGDestinationBoard(capsuleCount: capsuleCount, placement: .cardTop)
            VStack(alignment: .leading, spacing: DGSpacing.s12) {
                readyHeader
                memberAvatars
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

    /// メンバーのアバター。押すとメンバー一覧（S-11）
    private var memberAvatars: some View {
        let overflow = DGAvatarOverflow(total: members.count, limit: Self.maxVisibleAvatars)
        return Button(action: onOpenMembers) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: memberColumnWidth), spacing: DGSpacing.s8, alignment: .top)],
                alignment: .leading,
                spacing: DGSpacing.s8
            ) {
                ForEach(members.prefix(overflow.visible)) { member in
                    memberColumn(member)
                }
                if overflow.hidden > 0 {
                    Text(verbatim: "+\(overflow.hidden)")
                        .font(.dgBody(Self.overflowTextSize, weight: .black, relativeTo: .caption))
                        .lineLimit(1)
                        .dynamicTypeSize(...Self.overflowMaxTypeSize)
                        .foregroundStyle(Color.dgInk)
                        .frame(width: DGAvatar.Size.large.diameter, height: DGAvatar.Size.large.diameter)
                        .background(Color.dgSurfaceMuted, in: Circle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("メンバー"))
        .accessibilityValue(Text("\(memberCount)人"))
        .accessibilityHint(Text("メンバー一覧を開きます"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(RoomView.Identifier.members)
    }

    /// メンバー 1 人分（アバターと名前）
    private func memberColumn(_ member: Identified<Member>) -> some View {
        VStack(spacing: DGSpacing.s4) {
            DGAvatar(
                name: member.displayName,
                color: AvatarPalette.index(of: member.avatarColor).map(Color.dgAvatar(at:)) ?? Color.dgAvatarNotReadyBg,
                size: .large,
                readiness: member.ready ? .ready : .notReady
            )
            Text(verbatim: member.displayName)
                .font(.dgBody(Self.memberNameSize, relativeTo: .caption2))
                .foregroundStyle(Color.dgTextSecondary)
                .lineLimit(1)
        }
        .frame(width: memberColumnWidth)
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
