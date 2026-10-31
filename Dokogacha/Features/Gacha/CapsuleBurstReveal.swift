//
//  CapsuleBurstReveal.swift
//  Dokogacha
//
//  案 A「カプセルぱかっ」: 当選のカプセルが揺れて（溜め）、ぎゅっと縮んでから上下に割れ、きっぷが紙吹雪とともに飛び出す（Issue #158）。
//

import SwiftUI

/// 案 A の時間と動き。時刻（演出を始めてからの秒）から形を求める
nonisolated enum CapsuleBurstTimeline {
    /// カプセルの直径（S-13 の取り出し口のカプセル 60 の 2 倍）
    static let capsuleDiameter: CGFloat = 120
    /// 登場（S-13 で大きくなって消えたカプセルの続きに見えるよう、大きめから縮む）の時間
    static let enterDuration = 0.35
    /// 登場の最初の大きさ
    static let enterScale = 1.25
    /// 揺れ始める時刻
    static let wobbleStart = 0.4
    /// 揺れの 1 区間の時間
    static let wobbleSegment = 0.12
    /// 揺れの角度（区間ごとの行き先。だんだん大きくして最後に戻す）
    static let wobbleAngles: [Double] = [-6, 6, -8, 8, -11, 11, 0]
    /// ぎゅっと縮む時間
    static let squashDuration = 0.14
    /// ぎゅっと縮んだときの横・縦の倍率
    static let squashScale = CGSize(width: 1.1, height: 0.86)
    /// 割れた殻が飛んで消える時間
    static let halvesDuration = 0.55
    /// 上の殻の飛ぶ先と回る角度
    static let topHalfTravel = CGSize(width: -36, height: -150)
    /// 上の殻の回る角度
    static let topHalfTurn: Double = -42
    /// 下の殻の飛ぶ先
    static let bottomHalfTravel = CGSize(width: 30, height: 120)
    /// 下の殻の回る角度
    static let bottomHalfTurn: Double = 30
    /// 飛び出す前のきっぷの大きさ
    static let ticketStartScale = 0.2
    /// 飛び出す前のきっぷの傾き
    static let ticketStartTurn: Double = -8
    /// きっぷが飛び出すばねの往復の時間
    static let ticketSpringResponse = 0.5
    /// きっぷが飛び出すばねの減衰（1 未満で少し行き過ぎる）
    static let ticketSpringDamping = 0.6
    /// きっぷが見えるまでのフェードの時間
    static let ticketFadeDuration = 0.12
    /// 割れてから、きっぷのばねが止まるまでの時間
    static let ticketSettleDuration = 1.1
    /// 紙吹雪が消えるまでの時間
    static let confettiLifetime = 1.6
    /// 割れてから見出しを出すまでの間
    static let headlineDelay = 0.1
    /// 割れてからハンコを押し始めるまでの間
    static let stampDelay = 0.6
    /// ハンコが紙に当たる位置（`DGStamp` の押し込む割合と同じ）
    static let stampLandFraction = 0.7
    /// 揺れの刻みの触覚の強さ（最初と最後）
    static let tickIntensity = (first: 0.35, last: 0.8)

    /// 揺れ終わる時刻
    static var wobbleEnd: Double {
        wobbleStart + wobbleSegment * Double(wobbleAngles.count)
    }

    /// 割れる時刻（行き先が分かる瞬間）
    static var burstAt: Double {
        wobbleEnd + squashDuration
    }

    /// ハンコを押し始める時刻
    static var stampStart: Double {
        burstAt + stampDelay
    }

    /// 動きがすべて止まる時刻
    static var duration: Double {
        burstAt + max(ticketSettleDuration, confettiLifetime)
    }

    /// 「視差効果を減らす」: カプセルからきっぷに替える時刻
    static let reducedSwapAt = 0.55
    /// 「視差効果を減らす」: ハンコを出し始める時刻
    static var reducedStampStart: Double {
        reducedSwapAt + DGMotion.reducedFadeDuration + 0.1
    }

    /// 演出の予定
    static func plan(reduceMotion: Bool) -> ResultRevealPlan {
        if reduceMotion {
            return ResultRevealPlan(
                cues: [(reducedSwapAt, .decided), (reducedStampStart, .stamp)],
                decidedAt: reducedSwapAt,
                settledAt: reducedStampStart + DGMotion.reducedFadeDuration,
                duration: reducedStampStart + DGMotion.reducedFadeDuration
            )
        }
        let tickCount = wobbleAngles.count - 1
        let ticks: [(Double, ResultRevealCue)] = (0..<tickCount).map { index in
            let intensity = RevealCurve.mix(tickIntensity.first, tickIntensity.last, Double(index) / Double(max(tickCount - 1, 1)))
            return (wobbleStart + wobbleSegment * Double(index + 1), .tick(intensity: intensity))
        }
        let stampDuration = DGMotion.stamp.duration
        return ResultRevealPlan(
            cues: ticks + [(burstAt, .decided), (stampStart + stampDuration * stampLandFraction, .stamp)],
            decidedAt: burstAt + headlineDelay,
            settledAt: stampStart + stampDuration,
            duration: duration
        )
    }

    /// ある時刻の形
    struct Pose: Equatable {
        /// 割れる前のカプセルの横・縦の倍率
        var capsuleScale = CGSize(width: 1, height: 1)
        /// 割れる前のカプセルの傾き
        var capsuleTurn: Double = 0
        /// 割れる前のカプセルの不透明度
        var capsuleOpacity: Double = 0
        /// 割れた殻を出しているか
        var showsHalves = false
        /// 割れた殻の飛び具合（0〜1）
        var halvesTravel: Double = 0
        /// 割れた殻の不透明度
        var halvesOpacity: Double = 0
        /// きっぷの大きさ
        var ticketScale: Double = 1
        /// きっぷの傾き
        var ticketTurn: Double = 0
        /// きっぷの不透明度
        var ticketOpacity: Double = 1
        /// 紙吹雪の、割れてからの時刻（出していなければ nil）
        var confettiTime: Double?
        /// ハンコの押し具合（0〜1）
        var stampProgress: Double = 1
    }

    /// 時刻 `time` の形
    static func pose(at time: Double, reduceMotion: Bool) -> Pose {
        if reduceMotion {
            let swap = RevealCurve.progress(time, from: reducedSwapAt, duration: DGMotion.reducedFadeDuration)
            return Pose(
                capsuleOpacity: 1 - swap,
                ticketOpacity: swap,
                stampProgress: RevealCurve.progress(time, from: reducedStampStart, duration: DGMotion.reducedFadeDuration)
            )
        }
        if time >= duration {
            return Pose()
        }
        guard time >= burstAt else {
            return closedPose(at: time)
        }
        let since = time - burstAt
        let spring = RevealCurve.spring(since, response: ticketSpringResponse, dampingFraction: ticketSpringDamping)
        let fadeStart = halvesDuration * 0.35
        return Pose(
            showsHalves: since < halvesDuration,
            halvesTravel: RevealCurve.easeOut(RevealCurve.progress(since, from: 0, duration: halvesDuration)),
            halvesOpacity: 1 - RevealCurve.easeIn(RevealCurve.progress(since, from: fadeStart, duration: halvesDuration - fadeStart)),
            ticketScale: RevealCurve.mix(ticketStartScale, 1, spring),
            ticketTurn: RevealCurve.mix(ticketStartTurn, 0, spring),
            ticketOpacity: RevealCurve.progress(since, from: 0, duration: ticketFadeDuration),
            confettiTime: since < confettiLifetime ? since : nil,
            stampProgress: RevealCurve.progress(time, from: stampStart, duration: DGMotion.stamp.duration)
        )
    }

    /// 割れる前（登場・揺れ・ぎゅっ）の形
    private static func closedPose(at time: Double) -> Pose {
        let enter = RevealCurve.easeOut(RevealCurve.progress(time, from: 0, duration: enterDuration))
        let size = RevealCurve.mix(enterScale, 1, enter)
        let squash = RevealCurve.easeIn(RevealCurve.progress(time, from: wobbleEnd, duration: squashDuration))
        return Pose(
            capsuleScale: CGSize(
                width: size * RevealCurve.mix(1, squashScale.width, squash),
                height: size * RevealCurve.mix(1, squashScale.height, squash)
            ),
            capsuleTurn: wobbleAngle(at: time),
            capsuleOpacity: 1,
            ticketScale: ticketStartScale,
            ticketTurn: ticketStartTurn,
            ticketOpacity: 0,
            stampProgress: 0
        )
    }

    /// 揺れの角度（区間ごとに easeInOut で次の角度へ）
    static func wobbleAngle(at time: Double) -> Double {
        guard time > wobbleStart, time < wobbleEnd else {
            return 0
        }
        let position = (time - wobbleStart) / wobbleSegment
        let index = min(Int(position), wobbleAngles.count - 1)
        let from = index == 0 ? 0 : wobbleAngles[index - 1]
        return RevealCurve.mix(from, wobbleAngles[index], RevealCurve.easeInOut(position - Double(index)))
    }
}

/// 案 A の見た目。きっぷの上に、割れる前のカプセル・割れた殻・紙吹雪を重ねる（重ねたものは VoiceOver では読まない）
struct CapsuleBurstReveal: View {
    /// いまの形
    let pose: CapsuleBurstTimeline.Pose
    /// きっぷの値
    let ticket: ResultTicket
    /// 当選したカプセルの色
    let capsuleColor: Color

    var body: some View {
        RevealTicket(ticket: ticket, stampProgress: pose.stampProgress)
            .equatable()
            .scaleEffect(pose.ticketScale)
            .rotationEffect(.degrees(pose.ticketTurn))
            .opacity(pose.ticketOpacity)
            .overlay {
                capsule
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                if let time = pose.confettiTime {
                    ConfettiBurst(time: time)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    /// 割れる前のカプセルと、割れた殻
    @ViewBuilder private var capsule: some View {
        let diameter = CapsuleBurstTimeline.capsuleDiameter
        if pose.showsHalves {
            ZStack {
                CapsuleHalf(isTop: true, color: capsuleColor)
                    .frame(width: diameter, height: diameter / 2)
                    .rotationEffect(.degrees(CapsuleBurstTimeline.topHalfTurn * pose.halvesTravel))
                    .offset(
                        x: CapsuleBurstTimeline.topHalfTravel.width * pose.halvesTravel,
                        y: -diameter / 4 + CapsuleBurstTimeline.topHalfTravel.height * pose.halvesTravel
                    )
                CapsuleHalf(isTop: false, color: capsuleColor)
                    .frame(width: diameter, height: diameter / 2)
                    .rotationEffect(.degrees(CapsuleBurstTimeline.bottomHalfTurn * pose.halvesTravel))
                    .offset(
                        x: CapsuleBurstTimeline.bottomHalfTravel.width * pose.halvesTravel,
                        y: diameter / 4 + CapsuleBurstTimeline.bottomHalfTravel.height * pose.halvesTravel
                    )
            }
            .opacity(pose.halvesOpacity)
        } else if pose.capsuleOpacity > 0 {
            CapsuleBall(color: capsuleColor, lineWidth: DGBorder.machine)
                .frame(width: diameter, height: diameter)
                .scaleEffect(x: pose.capsuleScale.width, y: pose.capsuleScale.height, anchor: .bottom)
                .rotationEffect(.degrees(pose.capsuleTurn), anchor: .bottom)
                .opacity(pose.capsuleOpacity)
        }
    }
}

/// 割れたカプセルの半分（上は候補の色、下は白）。切り口の直線も縁取る
private struct CapsuleHalf: View {
    /// 上の殻か
    let isTop: Bool
    /// 候補の色
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let radius = proxy.size.width / 2
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: isTop ? radius : 0,
                bottomLeadingRadius: isTop ? 0 : radius,
                bottomTrailingRadius: isTop ? 0 : radius,
                topTrailingRadius: isTop ? radius : 0
            )
            shape
                .fill(isTop ? color : Color.dgSurfaceCard)
                .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.machine))
        }
    }
}

#Preview("案 A カプセルぱかっ") {
    @Previewable @State var round = 0
    VStack(spacing: DGSpacing.s24) {
        ResultRevealStage(
            style: .capsule,
            ticket: ResultRevealPreview.ticket,
            capsuleColor: .dgCapsule(at: 0),
            flapNames: [],
            capsuleCount: 3
        ) { _ in }
        .id(round)
        DGButton("もう一度押す", kind: .secondary) {
            round += 1
        }
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}
