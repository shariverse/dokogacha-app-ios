//
//  RoomMemberAvatars.swift
//  Dokogacha
//

import SwiftUI

/// S-07 のルームパネルのメンバーのアバターの並び（03 の S-07 の 1）。
///
/// アバターは 44＋名前 11 で、準備OKの人にはチェックのバッジを付ける。7 人以上は 6 人＋「+N」（`DGAvatarOverflow`）。
/// 押すとメンバー一覧（S-11）を開く。横には並べきれないので、幅に合わせて折り返す（横スクロールにしない。端からのスワイプで戻る操作とぶつけないため）。
struct RoomMemberAvatars: View {
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
                // 文字を大きくしても、列の幅で名前が「…」で切れにくいように少しだけ縮める
                .minimumScaleFactor(Self.memberNameMinimumScale)
        }
        .frame(width: memberColumnWidth)
    }
}
