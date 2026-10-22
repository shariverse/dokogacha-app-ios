//
//  RoomPanel.swift
//  Dokogacha
//

import SwiftUI

/// S-07 のルームパネル（03 の S-07 の 1）。線 2.5・ハードシャドウ・角丸 20 の枠に、上から
/// 行き先の黒帯（`DGDestinationBoard`）・「準備OK n/m」・メンバーのアバター・「あなたの投稿 n/上限件 · いいねの効き方」を並べる。
///
/// メンバーのアバターは 44＋名前 11 で、準備OKの人にはチェックのバッジを付ける。7 人以上は 6 人＋「+N」（`DGAvatarOverflow`）。
/// 押すとメンバー一覧（S-11）を開く。横には並べきれないので、幅に合わせて折り返す（横スクロールにしない。端からのスワイプで戻る操作とぶつけないため）。
///
/// ヒント文言（F-31）・「準備OK」「準備OKを取り消す」のボタン（F-30）・「強制解禁（作成者）」（F-32）は、タスク 24 でメンバーの下に足す。
struct RoomPanel: View {
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
    /// メンバーを押したときの処理（メンバー一覧を開く）
    let onOpenMembers: () -> Void

    @ScaledMetric(relativeTo: .caption) private var memberColumnWidth = RoomPanel.memberColumnWidth

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        VStack(spacing: 0) {
            DGDestinationBoard(capsuleCount: capsuleCount, placement: .cardTop)
            VStack(alignment: .leading, spacing: DGSpacing.s12) {
                readyHeader
                memberAvatars
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

    /// 「あなたの投稿 n/上限件 · 共感ブースト（みんな平等）」
    private var myPostsText: some View {
        let mode: Text = likeMode == .equal ? Text("みんな平等") : Text("共感ブースト")
        return Text("あなたの投稿 \(myPostCount)/\(postLimit)件 · \(mode)")
            .font(.dg(.bodyCaption))
            .foregroundStyle(Color.dgTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
