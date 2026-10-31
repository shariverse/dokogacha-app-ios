//
//  RoomMemberAvatars.swift
//  Dokogacha
//

import SwiftUI

/// S-07 のルームパネルのメンバーのアバターの並び（03 の S-07 の 1）と、末尾の招待の「＋」。
///
/// アバターは 44＋名前 11 で、準備OKの人にはチェックのバッジを付ける。7 人以上は 6 人＋「+N」（`DGAvatarOverflow`）。
/// 押すとメンバー一覧（S-11）を開く。横には並べきれないので、幅に合わせて折り返す（横スクロールにしない。端からのスワイプで戻る操作とぶつけないため）。
///
/// 並びの末尾（「+N」の後）に招待の「＋」（`DGAvatarInviteButton`）を置き、アバターと同じく幅に入らなければ折り返す。
/// 「＋」はメンバーのボタンの中に入れ子にせず、並びの中には場所だけを取って、その場所にボタンを重ねる
/// （押すと招待、ほかの場所を押すとメンバー一覧。VoiceOver でも「メンバー」の次に別の要素として読む）。
struct RoomMemberAvatars: View {
    /// 末尾の招待の「＋」（02 の F-04）
    struct Invite {
        /// 押せるか（満員なら押せない「満員」の表示）
        var status: DGAvatarInviteButton.Status
        /// 押したときの処理（招待の画面を開く）
        var onInvite: () -> Void = {}
    }

    /// 並べるアバターの上限（03 の S-07「7人以上は6人＋「+N」」）
    private static let maxVisibleAvatars = 6
    /// メンバーの列の幅（プロトタイプの 56。アバター 44 と名前）
    private static let memberColumnWidth: CGFloat = 56
    /// メンバーの名前の大きさ（03 の S-07「名前11pt」）
    private static let memberNameSize: CGFloat = 11
    /// メンバーの名前を列の幅に収めるときに縮める下限
    private static let memberNameMinimumScale: CGFloat = 0.7
    /// 「+N」の文字の大きさ
    private static let overflowTextSize: CGFloat = 15
    /// 「+N」を大きくする上限（円の大きさは変えないので、2〜3 文字が円に収まる大きさで止める）
    private static let overflowMaxTypeSize = DynamicTypeSize.xxxLarge

    /// メンバー（参加の早い順）
    let members: [Identified<Member>]
    /// メンバーの人数（VoiceOver で読む）
    let memberCount: Int
    /// 末尾の招待の「＋」（nil なら出さない。`drawn`・`closed`・読み込み中）
    var invite: Invite?
    /// メンバーを押したときの処理（メンバー一覧を開く）
    let onOpenMembers: () -> Void

    @ScaledMetric(relativeTo: .caption) private var memberColumnWidth = RoomMemberAvatars.memberColumnWidth

    var body: some View {
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
                if let invite {
                    // 招待の「＋」の場所だけを取る（ボタンは `inviteButton` で上に重ねる。同じ部品を隠して置き、大きさをそろえる）
                    DGAvatarInviteButton(status: invite.status) {}
                        .frame(width: memberColumnWidth)
                        .hidden()
                        .anchorPreference(key: InviteSlotKey.self, value: .bounds) { $0 }
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
        .overlayPreferenceValue(InviteSlotKey.self) { slot in
            if let invite, let slot {
                inviteButton(invite, in: slot)
            }
        }
    }

    /// 並びの中に取った場所（`slot`）に重ねる招待の「＋」
    private func inviteButton(_ invite: Invite, in slot: Anchor<CGRect>) -> some View {
        GeometryReader { proxy in
            let frame = proxy[slot]
            DGAvatarInviteButton(status: invite.status, action: invite.onInvite)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .accessibilityIdentifier(RoomView.Identifier.invite)
        }
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
                // 文字を大きくしても、列の幅で名前が「…」で切れにくいように少しだけ縮める
                .minimumScaleFactor(Self.memberNameMinimumScale)
        }
        .frame(width: memberColumnWidth)
    }
}

/// アバターの並びの中に取った、招待の「＋」の場所（`RoomMemberAvatars`）
nonisolated private struct InviteSlotKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? {
        nil
    }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
