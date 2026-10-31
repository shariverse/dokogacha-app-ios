//
//  ResultRevealSettingView.swift
//  Dokogacha
//

import SwiftUI

/// S-16 結果の演出（S-15 設定の「結果の演出」から積む画面。Issue #158）。
///
/// 上に選んでいる演出の見本（`ResultRevealStage` を見本のきっぷで流す。「もう一度見る」で流し直す）、下に演出の選択肢を並べる。
/// 選ぶとすぐに端末に覚え（`ResultRevealSetting`）、見本をその演出で流し直す。次にガチャを回したときから、S-14 でその演出を流す。
/// 「視差効果を減らす」がオンのときは、見本も動きを控えた流れになることを書き添える。
/// VoiceOver では見本は読まず（動きを見せるためのもの）、選択肢を「名前、説明」と選択中かどうかで読む。
struct ResultRevealSettingView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 結果の演出の画面
        static let screen = "resultReveal.screen"
        /// 見本
        static let preview = "resultReveal.preview"
        /// 「もう一度見る」
        static let replay = "resultReveal.replay"

        /// 選択肢 1 つ（`ResultRevealStyle` の rawValue ごと）
        static func option(_ style: ResultRevealStyle) -> String {
            "resultReveal.option.\(style.rawValue)"
        }
    }

    /// 選択の印の直径
    private static let markSize: CGFloat = 26
    /// 選択の印のチェックの大きさ
    private static let checkSize: CGFloat = 16
    /// 「標準」の文字の大きさ
    private static let standardTagSize: CGFloat = 11
    /// 「標準」の上下の余白
    private static let standardTagVerticalPadding: CGFloat = 2

    /// 選んでいる演出（端末に覚える）
    let setting: ResultRevealSetting

    /// 見本を流し直した回数（変わるたびに見本を作り直して最初から流す）
    @State private var replayCount = 0
    /// 見本のきっぷの抽選日（画面を開いた日。描き直すたびに変えない）
    @State private var sampleDate = Date.now

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var markSize = ResultRevealSettingView.markSize
    @ScaledMetric(relativeTo: .body) private var checkSize = ResultRevealSettingView.checkSize

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("結果の演出"), onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpacing.s16) {
                    Text("ガチャを回した後に、この演出で行き先きっぷが出ます")
                        .font(.dg(.bodyRegular))
                        .foregroundStyle(Color.dgTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    preview
                    options
                    if reduceMotion {
                        Text("「視差効果を減らす」がオンのため、動きを控えた演出になります")
                            .font(.dg(.bodyCaption))
                            .foregroundStyle(Color.dgTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.top, DGSpacing.s8)
                .padding(.bottom, DGSpacing.s24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .sensoryFeedback(.selection, trigger: setting.style)
    }

    /// 選んでいる演出の見本と「もう一度見る」
    private var preview: some View {
        VStack(spacing: DGSpacing.s12) {
            ResultRevealStage(
                style: setting.style,
                ticket: ResultRevealSample.ticket(drawnAt: sampleDate),
                capsuleColor: .dgCapsule(at: ResultRevealSample.capsuleColorIndex),
                flapNames: ResultRevealSample.candidateNames,
                capsuleCount: ResultRevealSample.candidateNames.count
            ) { _ in }
            // 演出を替えたとき・流し直したときは、作り直して最初から流す
            .id("\(setting.style.rawValue)-\(replayCount)")
            .accessibilityHidden(true)
            .accessibilityIdentifier(Identifier.preview)
            DGButton("もう一度見る", kind: .secondary) {
                replayCount += 1
            }
            .accessibilityHint(Text("見本の演出を最初から流します"))
            .accessibilityIdentifier(Identifier.replay)
        }
    }

    /// 演出の選択肢（標準を先頭に、名前と説明。選んでいるものに印）
    private var options: some View {
        SettingsSection {
            ForEach(Array(ResultRevealStyle.settingsOrder.enumerated()), id: \.element) { index, style in
                if index > 0 {
                    DGDashedLine()
                }
                option(style)
            }
        }
    }

    /// 選択肢 1 つ
    private func option(_ style: ResultRevealStyle) -> some View {
        let isSelected = setting.style == style
        return Button {
            guard !isSelected else {
                return
            }
            setting.select(style)
        } label: {
            HStack(alignment: .center, spacing: DGSpacing.s12) {
                VStack(alignment: .leading, spacing: DGSpacing.s4) {
                    HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s6) {
                        Text(style.title)
                            .font(.dg(.bodyTitle))
                            .foregroundStyle(Color.dgInk)
                        if style == .standard {
                            standardTag
                        }
                    }
                    Text(style.summary)
                        .font(.dg(.bodyRegular))
                        .foregroundStyle(Color.dgTextSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                selectionMark(isSelected: isSelected)
            }
            .padding(.horizontal, DGSpacing.cardPadding)
            .padding(.vertical, DGSpacing.s12)
            .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(Identifier.option(style))
    }

    /// 「標準」（名前の右に添える小さな札）
    private var standardTag: some View {
        Text("標準")
            .font(.dgBody(Self.standardTagSize, weight: .bold, relativeTo: .caption))
            .foregroundStyle(Color.dgAccentPaleText)
            .padding(.horizontal, DGSpacing.s6)
            .padding(.vertical, Self.standardTagVerticalPadding)
            .background(Color.dgAccentPale, in: RoundedRectangle(cornerRadius: DGRadius.xs))
    }

    /// 選択の印（選んでいれば朱色の丸に白いチェック、選んでいなければ墨色の線の丸）
    private func selectionMark(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.dgAccentPrimary : Color.dgSurfaceCard)
            Circle()
                .strokeBorder(Color.dgInk, lineWidth: DGBorder.regular)
            if isSelected {
                Image("ui-check")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: checkSize, height: checkSize)
                    .foregroundStyle(Color.dgTextOnAccent)
            }
        }
        .frame(width: markSize, height: markSize)
        .accessibilityHidden(true)
    }
}

/// S-16 の見本のきっぷ（どの演出でも同じものを流す）
enum ResultRevealSample {
    /// 見本の当たりのカプセルの色の番号
    static let capsuleColorIndex = 0
    /// 見本の候補の名前（パタパタ行き先表示でめくる）
    static let candidateNames = ["高尾山", "サンシャイン水族館", "横浜中華街"]

    /// 見本のきっぷ（抽選日は今日にする）
    static func ticket(drawnAt: Date) -> ResultTicket {
        ResultTicket(
            roomName: String(localized: "見本のルーム"),
            destinationName: "サンシャイン水族館",
            area: "東京・豊島区",
            category: .aquarium,
            note: "ペンギンが空を飛ぶ水槽が見たい",
            author: .member("みさき"),
            likeCount: 3,
            percent: 42,
            drawnAt: drawnAt,
            isRare: false
        )
    }
}

#Preview("S-16 結果の演出") {
    NavigationStack {
        ResultRevealSettingView(setting: ResultRevealSetting(defaults: nil))
    }
}

#Preview("S-16 文字を最大") {
    NavigationStack {
        ResultRevealSettingView(setting: ResultRevealSetting(defaults: nil, initial: .issue))
    }
    .dynamicTypeSize(.accessibility5)
}
