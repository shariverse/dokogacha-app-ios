//
//  DGProbabilityMeter.swift
//  Dokogacha
//
//  出やすさのメーター（`04_design_system.md` の §4 の CandidateCard の ProbabilityMeter・02 の F-22）。
//

import SwiftUI

/// 出やすさのレベルのチップ・メーターのバー・表示 % を 1 行に並べた部品。
///
/// レベルチップ（最小幅 56・12 Black・角丸 8）＋溝（高さ 12・角丸 6・`surface.muted`）＋バー（レベルの色）＋ %（見出し 24 ＋「%」13・最小幅 58・右寄せ）。
/// レベル（F-22 の判定）と表示 %（F-21）は呼び出し側で決めて渡す。バーの長さは `DGProbabilityMeterRule` で決める。
/// 表示 % が変わるとバーの幅を 0.35 秒で動かし（`motion.meter`）、「視差効果を減らす」がオンのときは即時に切り替える。
/// 文字が大きくて 1 行に収まらないときは、バーを下の行に回す。
struct DGProbabilityMeter: View {
    /// レベルチップの最小の幅
    private static let chipMinWidth: CGFloat = 56
    /// レベルチップの角丸（04 の §4 の値。`radius.xs` の幅 6〜8 の上の端）
    private static let chipCornerRadius: CGFloat = 8
    /// 溝の高さ
    private static let grooveHeight: CGFloat = 12
    /// 溝とバーの角丸
    private static let grooveCornerRadius: CGFloat = 6
    /// % の欄の最小の幅
    private static let percentMinWidth: CGFloat = 58
    /// 溝の最小の幅（これより狭くなるなら、バーを下の行に回す）
    private static let grooveMinWidth: CGFloat = 64
    /// %（記号）の文字の大きさ
    private static let percentSignSize: CGFloat = 13

    /// 出やすさのレベル（ラベルと色）
    let level: DGLevelStyle
    /// この候補の表示 %（F-21 の `round(確率 × 100)`）
    let percent: Int
    /// ルームの全候補の中で最大の表示 %（この候補の表示 % をこれで割った長さがバーになる）
    let maxPercent: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DGSpacing.s10) {
                chip
                groove
                percentText
            }
            VStack(alignment: .leading, spacing: DGSpacing.s6) {
                HStack(spacing: DGSpacing.s10) {
                    chip
                    Spacer(minLength: 0)
                    percentText
                }
                groove
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("出やすさ"))
        .accessibilityValue(Text("\(Text(level.label)) \(percent)%"))
    }

    /// レベルのチップ（「出やすい」「ふつう」「レア」「平等」）
    private var chip: some View {
        Text(level.label)
            .font(.dgBody(12, weight: .black, relativeTo: .caption))
            .foregroundStyle(level.chipForeground)
            .lineLimit(1)
            .padding(.horizontal, DGSpacing.s8)
            .padding(.vertical, DGSpacing.s4)
            .frame(minWidth: Self.chipMinWidth)
            .background(level.chipBackground, in: RoundedRectangle(cornerRadius: Self.chipCornerRadius))
            .fixedSize()
    }

    /// 溝とバー。バーの長さは最大の候補を満タンにした割合
    private var groove: some View {
        let fraction = DGProbabilityMeterRule.fillFraction(percent: percent, maxPercent: maxPercent)
        return RoundedRectangle(cornerRadius: Self.grooveCornerRadius)
            .fill(Color.dgSurfaceMuted)
            .frame(height: Self.grooveHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: Self.grooveCornerRadius)
                        .fill(level.bar)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.grooveCornerRadius))
            .frame(minWidth: Self.grooveMinWidth)
            .animation(reduceMotion ? nil : DGMotion.meter.animation, value: fraction)
    }

    /// 表示 %（数字は見出し 24、「%」は 13）
    private var percentText: some View {
        Text("\(Text(verbatim: "\(percent)").font(.dg(.displayL)))%")
            .font(.dgDisplay(Self.percentSignSize, relativeTo: .title2))
            .foregroundStyle(level.number)
            .lineLimit(1)
            .frame(minWidth: Self.percentMinWidth, alignment: .trailing)
            .fixedSize()
    }
}

/// 出やすさのメーターのバーの長さを決める（02 の F-22「メーターの長さ = 表示% ÷ 全候補の中の最大の表示% × 100%」）。
nonisolated enum DGProbabilityMeterRule {
    /// バーの長さを、溝の幅に対する割合（0〜1）で返す。
    ///
    /// 最大の表示 % の候補が満タン（1）になる。最大が 0 以下（候補が無いなど）のときは 0 にし、
    /// 渡し間違いで表示 % が最大を超えても溝からはみ出さないよう 0〜1 に収める。
    /// - Parameters:
    ///   - percent: この候補の表示 %
    ///   - maxPercent: 全候補の中で最大の表示 %
    static func fillFraction(percent: Int, maxPercent: Int) -> Double {
        guard maxPercent > 0 else {
            return 0
        }
        return min(max(Double(percent) / Double(maxPercent), 0), 1)
    }
}

#Preview("ProbabilityMeter レベルごと") {
    VStack(spacing: DGSpacing.s16) {
        DGProbabilityMeter(level: .high, percent: 16, maxPercent: 16)
        DGProbabilityMeter(level: .mid, percent: 13, maxPercent: 16)
        DGProbabilityMeter(level: .low, percent: 5, maxPercent: 16)
        DGProbabilityMeter(level: .flat, percent: 13, maxPercent: 13)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("ProbabilityMeter 変化") {
    @Previewable @State var percent = 5
    VStack(spacing: DGSpacing.s16) {
        DGProbabilityMeter(level: percent >= 13 ? .high : .low, percent: percent, maxPercent: 16)
        DGButton("いいねで変える", kind: .secondary) {
            percent = percent == 5 ? 16 : 5
        }
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("ProbabilityMeter 文字を最大") {
    VStack(spacing: DGSpacing.s16) {
        DGProbabilityMeter(level: .high, percent: 16, maxPercent: 16)
        DGProbabilityMeter(level: .low, percent: 5, maxPercent: 16)
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
    .dynamicTypeSize(.accessibility5)
}
