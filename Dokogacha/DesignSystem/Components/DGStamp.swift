//
//  DGStamp.swift
//  Dokogacha
//
//  ハンコ（`04_design_system.md` の §4 の Stamp・§5 の `stamp`）。思い出のきっぷの「済」と、行き先きっぷの「決定」。
//

import SwiftUI

/// 朱色の円の縁に文字を入れ、−14° 傾けたハンコ。
///
/// 線 3 の `accent.text`、文字は見出しフォントの `accent.text`。
/// 大きさは 2 つ: 思い出のきっぷの「済」（直径 50）と、行き先きっぷの「決定」（直径 70・19pt ＋日付 `M.DD` 9pt Black・背景は白 85%）。
/// `animatesIn` を付けると、表示したときに 0.5 秒遅れて押す動き（2.2 倍・透明 → 0.92 倍 → 等倍）をする（S-14）。
/// 演出の時刻に合わせて外から押し具合を決めるときは、`pressProgress`（0〜1）を渡す（S-14 の演出の案。`ResultRevealStage`）。
/// 「視差効果を減らす」がオンのときは、大きさを変えずにフェード（0.2 秒）だけにする。
/// 飾りなので VoiceOver では読まない（意味は隣の文言で伝える）。円の大きさは置き場所で決まっているので Dynamic Type では変えず、文字を縮めて収める。
struct DGStamp: View {
    /// ハンコの大きさ
    nonisolated enum Size: CaseIterable, Sendable {
        /// 思い出のきっぷ（直径 50）
        case small
        /// 行き先きっぷ（直径 70・日付付き）
        case large

        /// 円の直径
        var diameter: CGFloat {
            switch self {
            case .small: 50
            case .large: 70
            }
        }

        /// 文字の大きさ
        var textSize: CGFloat {
            switch self {
            case .small: 18
            case .large: 19
            }
        }

        /// 大きいハンコの背景の不透明度（04 の §4「白85%」）
        private static let largeBackgroundOpacity: Double = 0.85

        /// 円の中の背景（行き先きっぷでは文字の下が透けないよう白 85%）
        var background: Color {
            switch self {
            case .small: .clear
            case .large: Color.dgSurfaceCard.opacity(Self.largeBackgroundOpacity)
            }
        }
    }

    /// 線の太さ
    private static let lineWidth: CGFloat = 3
    /// 傾き（04 の §4「rotationEffect(-14°)」）
    private static let angle = Angle.degrees(-14)
    /// 日付の文字の大きさ
    private static let dateSize: CGFloat = 9
    /// 文字と日付の間（プロトタイプの値）
    private static let dateSpacing: CGFloat = 3
    /// 円に収まらないときに文字を縮める下限
    private static let minimumScale: CGFloat = 0.5
    /// 押す前の大きさ（04 の §5「2.2倍」）
    private static let startScale: CGFloat = 2.2
    /// 押し込んだときの大きさ（04 の §5「0.92倍」）
    private static let pressedScale: CGFloat = 0.92
    /// 押し込むまでの時間の、`motion.stamp` の時間に対する割合（プロトタイプの keyframes の 70%）
    private static let pressPortion: Double = 0.7

    /// ハンコの文字（「済」「決定」）
    let text: LocalizedStringKey
    /// 大きさ
    var size: Size = .small
    /// 文字の下に出す日付（大きいハンコだけ）。無ければ `nil`
    var date: Date?
    /// 表示したときに押す動きをするか
    var animatesIn = false
    /// 押し具合（0〜1。外から決めるとき。nil なら `animatesIn` に従って自分で動かす）
    var pressProgress: Double?

    @State private var scale: CGFloat
    @State private var opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.timeZone) private var timeZone

    /// - Parameters:
    ///   - text: ハンコの文字
    ///   - size: 大きさ
    ///   - date: 文字の下に出す日付（大きいハンコだけ）
    ///   - animatesIn: 表示したときに押す動きをするか
    ///   - pressProgress: 押し具合（0〜1。外から決めるとき）
    init(_ text: LocalizedStringKey, size: Size = .small, date: Date? = nil, animatesIn: Bool = false, pressProgress: Double? = nil) {
        self.text = text
        self.size = size
        self.date = date
        self.animatesIn = animatesIn
        self.pressProgress = pressProgress
        _scale = State(initialValue: animatesIn ? Self.startScale : 1)
        _opacity = State(initialValue: animatesIn ? 0 : 1)
    }

    var body: some View {
        VStack(spacing: Self.dateSpacing) {
            Text(text)
                .font(.dgDisplay(size.textSize, relativeTo: .title3))
            if size == .large, let date {
                Text(verbatim: DGDateText.stampDate(date, timeZone: timeZone))
                    .font(.dgBody(Self.dateSize, weight: .black, relativeTo: .caption2))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Self.minimumScale)
        .foregroundStyle(Color.dgAccentText)
        .padding(Self.lineWidth * 2)
        .frame(width: size.diameter, height: size.diameter)
        .background(size.background, in: Circle())
        .overlay(Circle().strokeBorder(Color.dgAccentText, lineWidth: Self.lineWidth))
        .rotationEffect(Self.angle)
        .scaleEffect(pressProgress.map { Self.pressPose($0, reduceMotion: reduceMotion).scale } ?? scale)
        .opacity(pressProgress.map { Self.pressPose($0, reduceMotion: reduceMotion).opacity } ?? opacity)
        .onAppear(perform: press)
        .accessibilityHidden(true)
    }

    /// 押し具合 `progress`（0〜1）のときの大きさと不透明度（`animatesIn` の動きと同じ形。前の 7 割で押し込み、残りで等倍に戻る）
    static func pressPose(_ progress: Double, reduceMotion: Bool) -> (scale: CGFloat, opacity: Double) {
        let clamped = min(max(progress, 0), 1)
        if reduceMotion {
            return (1, clamped)
        }
        if clamped < pressPortion {
            let pressed = easeOut(clamped / pressPortion)
            return (startScale + (pressedScale - startScale) * pressed, pressed)
        }
        let settled = easeOut((clamped - pressPortion) / (1 - pressPortion))
        return (pressedScale + (1 - pressedScale) * settled, 1)
    }

    /// だんだん遅く（3 次）
    private static func easeOut(_ value: Double) -> Double {
        let rest = 1 - value
        return 1 - rest * rest * rest
    }

    /// 押す動きを始める（`animatesIn` のときだけ）
    private func press() {
        guard animatesIn, opacity == 0 else {
            return
        }
        if reduceMotion {
            scale = 1
            withAnimation(DGMotion.reducedFade) {
                opacity = 1
            }
            return
        }
        let spec = DGMotion.stamp
        withAnimation(.easeOut(duration: spec.duration * Self.pressPortion).delay(spec.delay)) {
            scale = Self.pressedScale
            opacity = 1
        } completion: {
            withAnimation(.easeOut(duration: spec.duration * (1 - Self.pressPortion))) {
                scale = 1
            }
        }
    }
}

#Preview("Stamp 大きさごと") {
    HStack(spacing: DGSpacing.s24) {
        DGStamp("済")
        DGStamp("決定", size: .large, date: Date(timeIntervalSince1970: 1_792_540_800))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("Stamp 押す動き") {
    @Previewable @State var round = 0
    VStack(spacing: DGSpacing.s24) {
        DGStamp("決定", size: .large, date: Date(timeIntervalSince1970: 1_792_540_800), animatesIn: true)
            .id(round)
        DGButton("もう一度押す", kind: .secondary) {
            round += 1
        }
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("Stamp 文字を最大") {
    HStack(spacing: DGSpacing.s24) {
        DGStamp("済")
        DGStamp("決定", size: .large, date: Date(timeIntervalSince1970: 1_792_540_800))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
    .dynamicTypeSize(.accessibility5)
}
