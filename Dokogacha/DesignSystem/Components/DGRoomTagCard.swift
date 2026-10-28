//
//  DGRoomTagCard.swift
//  Dokogacha
//
//  ホームの進行中のルームのカード（`04_design_system.md` の §4 の RoomTagCard・03 の S-02）。
//

import SwiftUI

/// 荷札に見立てた、進行中のルーム 1 件分のカード。押すとルーム画面へ進む。
///
/// 白・線 2.5・角丸 20・ハードシャドウ・余白 16。右上に荷札の穴（直径 14・線 2.5・中は `bg.base`）。
/// 中身は上から、状態チップ・ルーム名（18 Black）・行き先表示（`DGDestinationBoard`）・メンバーのアバター（28）と「準備OK n/m人」。
/// 20 人まで入るので、アバターは `DGAvatarOverflow` で 6 人＋「+N」にまとめる（S-07 のルームパネルと同じ数え方）。
struct DGRoomTagCard: View {
    /// メンバー 1 人分（アバターに要る値だけ）
    struct Member: Identifiable {
        /// メンバーを区別する値（ユーザー ID など）
        let id: String
        /// 表示名（アバターの 1 文字目）
        let name: String
        /// 割り当てた色（`Color.dgAvatars` のどれか）
        let color: Color
        /// 準備OKか
        let isReady: Bool
    }

    /// 並べるアバターの上限（S-07 の「7人以上は6人＋「+N」」と同じ数）
    static let maxVisibleAvatars = 6
    /// カードの角丸
    private static let cornerRadius: CGFloat = DGRadius.lg
    /// 荷札の穴の直径
    private static let holeDiameter: CGFloat = 14
    /// 荷札の穴の位置（カードの右端・上端から）
    private static let holeInset: CGFloat = 16
    /// ルーム名の大きさ（03 の S-02「本文18pt」）
    private static let nameSize: CGFloat = 18
    /// 「+N」の文字の大きさ（アバターの 1 文字と同じ割合）
    private static let overflowTextSize: CGFloat = 12
    /// 「+N」が円に収まらないときに縮める下限（`DGAvatar` と同じ）
    private static let overflowMinimumScale: CGFloat = 0.5
    /// 「+N」の文字を大きくする上限
    private static let overflowMaxTypeSize = DynamicTypeSize.xxxLarge

    /// ルームの状態（ホームに出るのは「候補募集中」「ガチャ解禁！」）
    let status: DGStatusChip.Status
    /// ルーム名
    let roomName: String
    /// ルームにあるカプセル（候補）の数
    let capsuleCount: Int
    /// メンバー（参加した順）
    let members: [Member]
    /// 押したときの処理（ルーム画面へ進む）
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        Button(action: action) {
            VStack(alignment: .leading, spacing: DGSpacing.s10) {
                DGStatusChip(status: status)
                Text(verbatim: roomName)
                    .font(.dgBody(Self.nameSize, weight: .black, relativeTo: .body))
                    .foregroundStyle(Color.dgInk)
                    .multilineTextAlignment(.leading)
                DGDestinationBoard(capsuleCount: capsuleCount)
                membersRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DGSpacing.s16)
            .background(Color.dgSurfaceCard, in: shape)
            .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.strong))
            .overlay(alignment: .topTrailing) { hole }
            .dgHardShadow(cornerRadius: Self.cornerRadius)
            .contentShape(shape)
        }
        .buttonStyle(.dgBare)
    }

    /// 荷札の穴（飾り）
    private var hole: some View {
        Circle()
            .fill(Color.dgBgBase)
            .overlay(Circle().strokeBorder(Color.dgInk, lineWidth: DGBorder.strong))
            .frame(width: Self.holeDiameter, height: Self.holeDiameter)
            .padding([.top, .trailing], Self.holeInset)
            .accessibilityHidden(true)
    }

    /// アバターと「準備OK n/m人」。1 行に収まらないときは 2 行にする
    private var membersRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s10) {
                avatars
                readyText
            }
            VStack(alignment: .leading, spacing: DGSpacing.s6) {
                avatars
                readyText
            }
        }
    }

    /// メンバーのアバター（6 人まで＋「+N」）。名前は読まず、人数を「準備OK n/m人」で読む
    private var avatars: some View {
        let overflow = DGAvatarOverflow(total: members.count, limit: Self.maxVisibleAvatars)
        return HStack(spacing: DGSpacing.s4) {
            ForEach(members.prefix(overflow.visible)) { member in
                DGAvatar(
                    name: member.name,
                    color: member.color,
                    size: .medium,
                    readiness: member.isReady ? .ready : .notReady
                )
            }
            if overflow.hidden > 0 {
                Text(verbatim: "+\(overflow.hidden)")
                    .font(.dgBody(Self.overflowTextSize, weight: .black, relativeTo: .caption))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.overflowMinimumScale)
                    // 円の大きさは変えないので、2〜3 文字の「+N」が円に収まる大きさで止める
                    .dynamicTypeSize(...Self.overflowMaxTypeSize)
                    .foregroundStyle(Color.dgInk)
                    .padding(DGSpacing.s4)
                    .frame(width: DGAvatar.Size.medium.diameter, height: DGAvatar.Size.medium.diameter)
                    .background(Color.dgSurfaceMuted, in: Circle())
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// 「準備OK n/m人」
    private var readyText: some View {
        let readyCount = members.filter(\.isReady).count
        return Text("準備OK \(readyCount)/\(members.count)人")
            .font(.dg(.bodyCaption))
            .foregroundStyle(Color.dgTextSecondary)
    }
}

/// アバターを並べる数と、「+N」にまとめる数を決める（03 の S-07「7人以上は6人＋「+N」」）。
nonisolated struct DGAvatarOverflow: Equatable, Sendable {
    /// 並べるアバターの数
    let visible: Int
    /// 「+N」にまとめる数（0 なら「+N」を出さない）
    let hidden: Int

    /// - Parameters:
    ///   - total: メンバーの人数
    ///   - limit: 並べるアバターの上限。人数がこれを超えたら、上限の数だけ並べて残りを「+N」にする
    init(total: Int, limit: Int) {
        let total = max(total, 0)
        let limit = max(limit, 0)
        visible = min(total, limit)
        hidden = total - visible
    }
}

/// Preview 用のメンバー
private func previewMembers(_ count: Int, ready: Int) -> [DGRoomTagCard.Member] {
    let names = ["ゆい", "けんた", "みさき", "そうま", "りこ", "はる", "なお", "あおい", "たくみ", "めい"]
    return (0..<count).map { index in
        DGRoomTagCard.Member(
            id: "member-\(index)",
            name: names[index % names.count],
            color: .dgAvatar(at: index),
            isReady: index < ready
        )
    }
}

#Preview("RoomTagCard 状態ごと") {
    ScrollView {
        VStack(spacing: DGSpacing.s16) {
            DGRoomTagCard(status: .open, roomName: "11月の日帰り旅行", capsuleCount: 8, members: previewMembers(5, ready: 3)) {}
            DGRoomTagCard(status: .unlocked, roomName: "年末の旅行", capsuleCount: 12, members: previewMembers(4, ready: 4)) {}
            DGRoomTagCard(status: .open, roomName: "サークルの合宿", capsuleCount: 0, members: previewMembers(9, ready: 2)) {}
        }
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
}

#Preview("RoomTagCard 文字を最大") {
    ScrollView {
        DGRoomTagCard(status: .open, roomName: "11月の日帰り旅行", capsuleCount: 8, members: previewMembers(7, ready: 3)) {}
            .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
