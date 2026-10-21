//
//  DGDestinationTicket.swift
//  Dokogacha
//
//  行き先きっぷ（`04_design_system.md` の §4 の DestinationTicket・03 の S-14・02 の F-42）。
//

import SwiftUI

/// ガチャで決まった行き先を、きっぷに見立てて出す部品。
///
/// 白・線 2.5・角丸 18・ハードシャドウ（y5）。上から、朱色の帯（「行き先きっぷ」とルーム名）、カテゴリタイル 52・「◯◯ ゆき」（27 / 15）・
/// エリアとカテゴリ・ひとことの吹き出し、左右に半円の切り欠きのある切り取り線、下段 3 列（投稿／いいね／当選確率）。
/// 右上に「決定」のハンコ（直径 70・抽選日 `M.DD`）を押す。本文の右の余白は 86 にして、ハンコと文字が重ならないようにする。
///
/// ドメインのモデルには依存させず、表示に要る値だけを受け取る（当選確率の % は呼び出し側で決める）。
/// 表示したときのポップインとハンコを押す動き（04 の §5 の `pop`・`stamp`）は画面の側（S-14）で付ける。
/// VoiceOver では、帯から下段までを 1 つにまとめて上から読む。文字が大きくて横に収まらないときは、帯と下段を縦に組み替える。
struct DGDestinationTicket: View {
    /// きっぷの角丸
    private static let cornerRadius: CGFloat = 18
    /// きっぷの影（04 の §4「hard 影（y5）」。`shadow.hard` より 1 深い）
    private static let shadow = DGShadow(x: 0, y: 5, blur: 0, color: .dgInk)
    /// 帯の「行き先きっぷ」の文字の大きさ
    private static let bandTitleSize: CGFloat = 15
    /// 「ゆき」の文字の大きさ
    private static let suffixSize: CGFloat = 15
    /// エリアとカテゴリ・ひとことの文字の大きさ
    private static let metaSize: CGFloat = 13
    /// ひとことの吹き出しの左上の角丸（ほかの角は `radius.s`。CandidateCard と同じ）
    private static let noteTailRadius: CGFloat = 4
    /// 本文の上の余白
    private static let detailsTopPadding: CGFloat = 20
    /// 本文の左の余白
    private static let detailsLeadingPadding: CGFloat = 18
    /// 本文の右の余白（ハンコの直径 70 ＋右 12 ＋間 4。文字がハンコに重ならない）
    private static let detailsTrailingPadding: CGFloat = 86
    /// ハンコの右からの距離
    private static let stampTrailing: CGFloat = 12
    /// ハンコの上端の、本文の上端からの距離（04 の §4「上54」は帯込みの位置。帯の高さ（約 42）を引いた値）
    private static let stampTopInDetails: CGFloat = 12
    /// 切り取り線の段の高さ（切り欠きの直径と同じ）
    private static let perforationHeight: CGFloat = 22
    /// 切り欠きの半円の直径
    private static let notchDiameter: CGFloat = 22
    /// 切り取り線の左右の余白
    private static let perforationInset: CGFloat = 18
    /// 下段のラベルの文字の大きさ
    private static let statLabelSize: CGFloat = 11
    /// 下段の投稿者の名前の文字の大きさ
    private static let statNameSize: CGFloat = 14
    /// 下段の数値の文字の大きさ
    private static let statNumberSize: CGFloat = 17
    /// 下段のラベルと値の間（プロトタイプの値）
    private static let statSpacing: CGFloat = 2

    /// ルーム名（帯の右に出す）
    let roomName: String
    /// 当選した場所の名前
    let destinationName: String
    /// 「エリア · カテゴリ」
    let meta: String
    /// カテゴリ（タイルの色とアイコン）
    let category: DGCategoryStyle
    /// ひとこと。無ければ `nil`
    var note: String?
    /// 候補の投稿者（CandidateCard と同じ区別）
    let author: DGCandidateCard.Author
    /// いいねの数
    let likeCount: Int
    /// 当選確率（%。抽選記録の確率を呼び出し側で丸めた値）
    let percent: Int
    /// 抽選した日時（ハンコの `M.DD`）
    let drawnAt: Date
    /// 切り欠きの中の色（きっぷを置く画面の背景と同じ色にする）
    var notchColor: Color = .dgBgBase

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        VStack(spacing: 0) {
            band
            details
            perforation
            stats
        }
        .background(Color.dgSurfaceCard)
        // 帯の角・切り欠きを角丸の形で切り抜き、その上に縁を描く（切り欠きの上にも縁の線が通る。プロトタイプと同じ）
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.strong))
        .dgHardShadow(Self.shadow, cornerRadius: Self.cornerRadius)
        .accessibilityElement(children: .combine)
    }

    // MARK: 帯

    /// 朱色の帯（「行き先きっぷ」とルーム名）
    private var band: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s8) {
                bandTitle
                Spacer(minLength: 0)
                bandRoomName
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                bandTitle
                bandRoomName
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.dgTextOnAccent)
        .padding(.vertical, DGSpacing.s10)
        .padding(.horizontal, DGSpacing.s16)
        .background(Color.dgAccentPrimary)
    }

    /// 帯の「行き先きっぷ」
    private var bandTitle: some View {
        Text("行き先きっぷ")
            .font(.dgDisplay(Self.bandTitleSize, relativeTo: .headline))
    }

    /// 帯のルーム名
    private var bandRoomName: some View {
        Text(verbatim: roomName)
            .font(.dgBody(DGTypeScale.bodyCaption.size, weight: .bold, relativeTo: .caption))
    }

    // MARK: 本文

    /// カテゴリタイル・「◯◯ ゆき」・エリアとカテゴリ・ひとこと。右上にハンコを重ねる
    private var details: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s10) {
            DGCategoryTile(category: category, size: .large)
            destination
            Text(verbatim: meta)
                .font(.dgBody(Self.metaSize, relativeTo: .subheadline))
                .foregroundStyle(Color.dgTextSecondary)
            if let note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.dgBody(Self.metaSize, relativeTo: .subheadline))
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Self.detailsTopPadding)
        .padding(.leading, Self.detailsLeadingPadding)
        .padding(.trailing, Self.detailsTrailingPadding)
        .padding(.bottom, DGSpacing.s16)
        .overlay(alignment: .topTrailing) {
            DGStamp("決定", size: .large, date: drawnAt)
                .padding(.top, Self.stampTopInDetails)
                .padding(.trailing, Self.stampTrailing)
        }
    }

    /// 「◯◯ ゆき」（場所名は見出し 27、「ゆき」は 15）
    private var destination: some View {
        let name = Text(verbatim: destinationName)
            .font(.dg(.displayTicket))
        return Text("\(name) ゆき")
            .font(.dgDisplay(Self.suffixSize, relativeTo: .title))
            .foregroundStyle(Color.dgInk)
    }

    // MARK: 切り取り線

    /// 左右に半円の切り欠きを入れた切り取り線（飾りなので VoiceOver では読まない）
    private var perforation: some View {
        DGDashedLine(color: .dgLineDashedStrong)
            .padding(.horizontal, Self.perforationInset)
            .frame(maxWidth: .infinity)
            .frame(height: Self.perforationHeight)
            .overlay(alignment: .leading) {
                notch
                    .offset(x: -Self.notchDiameter / 2)
            }
            .overlay(alignment: .trailing) {
                notch
                    .offset(x: Self.notchDiameter / 2)
            }
            .accessibilityHidden(true)
    }

    /// 切り欠きの円（中心をきっぷの縁に置き、外側の半分はきっぷの形で切り抜かれる）
    private var notch: some View {
        Circle()
            .fill(notchColor)
            .overlay(Circle().strokeBorder(Color.dgInk, lineWidth: DGBorder.strong))
            .frame(width: Self.notchDiameter, height: Self.notchDiameter)
    }

    // MARK: 下段

    /// 投稿／いいね／当選確率の 3 列。横に収まらないときは縦に並べる
    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DGSpacing.s8) {
                statColumns
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: DGSpacing.s8) {
                statColumns
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, DGSpacing.s8)
        .padding(.horizontal, Self.perforationInset)
        .padding(.bottom, DGSpacing.s16)
    }

    /// 下段の 3 つの欄
    @ViewBuilder private var statColumns: some View {
        stat(label: "投稿") {
            authorText
                .font(.dgBody(Self.statNameSize, weight: .black, relativeTo: .subheadline))
        }
        stat(label: "いいね") {
            Text(verbatim: "\(likeCount)")
                .font(.dgDisplay(Self.statNumberSize, relativeTo: .headline))
        }
        stat(label: "当選確率") {
            Text(verbatim: "\(percent)%")
                .font(.dgDisplay(Self.statNumberSize, relativeTo: .headline))
        }
    }

    /// 下段の 1 欄（ラベル 11 と値）。横に並べたときは等幅になるよう、それぞれが幅いっぱいに広がる
    private func stat(label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Self.statSpacing) {
            Text(label)
                .font(.dgBody(Self.statLabelSize, relativeTo: .caption))
                .foregroundStyle(Color.dgTextSecondary)
            value()
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「みさきさん」「あなた」「退出したメンバー」
    private var authorText: Text {
        switch author {
        case .me: Text("あなた")
        case let .member(name): Text("\(name)さん")
        case .departed: Text("退出したメンバー")
        }
    }
}

// MARK: - Preview

/// Preview の抽選日（2026/10/21 の日本時間 13 時）
private let previewDrawnAt = Date(timeIntervalSince1970: 1_792_555_200)

#Preview("DestinationTicket ひとことあり") {
    DGDestinationTicket(
        roomName: "11月の日帰り旅行",
        destinationName: "高尾山",
        meta: "東京・八王子市 · 自然",
        category: .nature,
        note: "紅葉シーズンにちょうどいい",
        author: .member("みさき"),
        likeCount: 4,
        percent: 16,
        drawnAt: previewDrawnAt
    )
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("DestinationTicket 長い名前・ひとことなし") {
    DGDestinationTicket(
        roomName: "サークルの合宿の行き先をみんなで決めるルーム",
        destinationName: "チームラボプラネッツ TOKYO DMM",
        meta: "東京・江東区 · アート・美術館",
        category: .art,
        author: .me,
        likeCount: 0,
        percent: 5,
        drawnAt: previewDrawnAt
    )
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("DestinationTicket カテゴリ違い") {
    ScrollView {
        VStack(spacing: DGSpacing.s24) {
            DGDestinationTicket(
                roomName: "夏の日帰り",
                destinationName: "城ヶ島",
                meta: "神奈川・三浦市 · 海",
                category: .sea,
                note: "磯遊びしたい",
                author: .member("けんた"),
                likeCount: 3,
                percent: 15,
                drawnAt: previewDrawnAt
            )
            DGDestinationTicket(
                roomName: "ごはん会",
                destinationName: "横浜中華街",
                meta: "神奈川・横浜市 · グルメ",
                category: .food,
                author: .departed,
                likeCount: 2,
                percent: 13,
                drawnAt: previewDrawnAt
            )
        }
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
}

#Preview("DestinationTicket 文字を最大") {
    ScrollView {
        DGDestinationTicket(
            roomName: "11月の日帰り旅行",
            destinationName: "高尾山",
            meta: "東京・八王子市 · 自然",
            category: .nature,
            note: "紅葉シーズンにちょうどいい",
            author: .member("みさき"),
            likeCount: 4,
            percent: 16,
            drawnAt: previewDrawnAt
        )
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
