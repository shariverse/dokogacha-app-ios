//
//  TicketIssueReveal.swift
//  Dokogacha
//
//  案 C「発券」: 券売機の取り出し口から、行き先きっぷが少しずつ押し出されてくる。行き先の名前の手前でいったん止めて（溜め）、
//  名前の段を一気に出してから残りを出しきり、取り出し口が外れてきっぷがぽとっと落ち着く（Issue #158）。
//

import SwiftUI

/// 案 C の時間と動き。時刻（演出を始めてからの秒）ときっぷの高さから形を求める
nonisolated enum TicketIssueTimeline {
    /// 取り出し口が出始める時刻
    static let slotAppearStart = 0.15
    /// 取り出し口が出る時間
    static let slotAppearDuration = 0.25
    /// 取り出し口が出るときの横の大きさ（ここから等倍に広がる）
    static let slotStartWidthScale = 0.85
    /// きっぷが出始める時刻
    static let feedStart = 0.45
    /// 名前の手前まで出す刻みの数
    static let leadSteps = 7
    /// 1 刻みの時間（前の 6 割で動き、残りは止まる）
    static let leadStepDuration = 0.1
    /// 1 刻みのうち動いている割合
    static let stepMoveFraction = 0.6
    /// 名前の手前までの長さ（帯・本文の上の余白・カテゴリタイル・間。きっぷの高さの割合で上限をかける）
    static let leadLength: Double = 124
    /// 名前の手前までの長さの、きっぷの高さに対する上限の割合
    static let leadMaxFraction = 0.42
    /// 名前の手前で止める時間（溜め）
    static let holdDuration = 0.45
    /// 名前の段の長さ
    static let nameLength: Double = 62
    /// 名前の段を出す時間
    static let pushDuration = 0.22
    /// 名前の後の間
    static let afterPushGap = 0.08
    /// 残りを出す刻みの数
    static let tailSteps = 6
    /// 残りの 1 刻みの時間
    static let tailStepDuration = 0.09
    /// 出しきってから取り出し口が外れるまでの間
    static let releaseGap = 0.08
    /// 取り出し口が外れる時間
    static let releaseDuration = 0.3
    /// 取り出し口が外れるときに下がる距離
    static let slotDropDistance: Double = 14
    /// きっぷが落ち着くときに沈む深さ
    static let settleDepth: Double = 4
    /// 外れてからハンコを押し始めるまでの間
    static let stampDelay = 0.35
    /// ハンコが紙に当たる位置（`DGStamp` の押し込む割合と同じ）
    static let stampLandFraction = 0.7
    /// 押し出す刻みの触覚の強さ
    static let tickIntensity = 0.45

    /// 名前の手前まで出し終える時刻
    static var leadEnd: Double {
        feedStart + leadStepDuration * Double(leadSteps)
    }

    /// 名前の段を出し始める時刻
    static var pushStart: Double {
        leadEnd + holdDuration
    }

    /// 名前の段を出し終える時刻（行き先が分かる瞬間）
    static var pushEnd: Double {
        pushStart + pushDuration
    }

    /// 残りを出し始める時刻
    static var tailStart: Double {
        pushEnd + afterPushGap
    }

    /// 残りを出し終える時刻
    static var tailEnd: Double {
        tailStart + tailStepDuration * Double(tailSteps)
    }

    /// 取り出し口が外れ始める時刻
    static var releaseAt: Double {
        tailEnd + releaseGap
    }

    /// ハンコを押し始める時刻
    static var stampStart: Double {
        releaseAt + stampDelay
    }

    /// 動きがすべて止まる時刻
    static var duration: Double {
        max(releaseAt + releaseDuration, stampStart + DGMotion.stamp.duration)
    }

    /// 「視差効果を減らす」: ハンコを出し始める時刻
    static var reducedStampStart: Double {
        DGMotion.reducedFadeDuration + 0.2
    }

    /// 演出の予定
    static func plan(reduceMotion: Bool) -> ResultRevealPlan {
        if reduceMotion {
            let settledAt = reducedStampStart + DGMotion.reducedFadeDuration
            return ResultRevealPlan(
                cues: [(DGMotion.reducedFadeDuration, .decided), (reducedStampStart, .stamp)],
                decidedAt: DGMotion.reducedFadeDuration,
                settledAt: settledAt,
                duration: settledAt
            )
        }
        let leadTicks = (1...leadSteps).map { feedStart + leadStepDuration * (Double($0 - 1) + stepMoveFraction) }
        let tailTicks = (1...tailSteps).map { tailStart + tailStepDuration * (Double($0 - 1) + stepMoveFraction) }
        let ticks: [(Double, ResultRevealCue)] = (leadTicks + tailTicks).map { ($0, .tick(intensity: tickIntensity)) }
        let stampDuration = DGMotion.stamp.duration
        return ResultRevealPlan(
            cues: ticks + [(pushEnd, .decided), (releaseAt, .release), (stampStart + stampDuration * stampLandFraction, .stamp)],
            decidedAt: pushEnd,
            settledAt: stampStart + stampDuration,
            duration: duration
        )
    }

    /// ある時刻の形
    struct Pose: Equatable {
        /// きっぷの下へのずれ（取り出し口の中に隠れている長さ）
        var ticketOffset: Double = 0
        /// きっぷの不透明度
        var ticketOpacity: Double = 1
        /// 取り出し口より下を隠すか（取り出し口がある間）
        var masksBelowSlot = false
        /// 取り出し口の不透明度
        var slotOpacity: Double = 0
        /// 取り出し口の横の大きさ
        var slotWidthScale: Double = 1
        /// 取り出し口の下へのずれ
        var slotOffset: Double = 0
        /// ハンコの押し具合（0〜1）
        var stampProgress: Double = 1
    }

    /// 時刻 `time` の形
    /// - Parameters:
    ///   - time: 演出を始めてからの秒
    ///   - height: きっぷの高さ（まだ分からなければ 0。そのときは隠しておく）
    ///   - reduceMotion: 「視差効果を減らす」か
    static func pose(at time: Double, height: Double, reduceMotion: Bool) -> Pose {
        if reduceMotion {
            return Pose(
                ticketOpacity: RevealCurve.progress(time, from: 0, duration: DGMotion.reducedFadeDuration),
                stampProgress: RevealCurve.progress(time, from: reducedStampStart, duration: DGMotion.reducedFadeDuration)
            )
        }
        if time >= duration {
            return Pose()
        }
        let appear = RevealCurve.easeOut(RevealCurve.progress(time, from: slotAppearStart, duration: slotAppearDuration))
        let release = RevealCurve.progress(time, from: releaseAt, duration: releaseDuration)
        let settle = time >= releaseAt ? settleDepth * sin(Double.pi * release) : 0
        return Pose(
            ticketOffset: max(height - emergedLength(at: time, height: height), 0) + settle,
            ticketOpacity: height > 0 ? 1 : 0,
            masksBelowSlot: time < releaseAt,
            slotOpacity: appear * (1 - RevealCurve.easeIn(release)),
            slotWidthScale: RevealCurve.mix(slotStartWidthScale, 1, appear),
            slotOffset: slotDropDistance * RevealCurve.easeIn(release),
            stampProgress: RevealCurve.progress(time, from: stampStart, duration: DGMotion.stamp.duration)
        )
    }

    /// 取り出し口から出ている長さ（刻みで押し出し、名前の手前で止め、名前の段を一気に出し、残りを刻みで出す）
    static func emergedLength(at time: Double, height: Double) -> Double {
        let lead = min(leadLength, height * leadMaxFraction)
        let name = min(nameLength, max(height - lead, 0))
        let tail = max(height - lead - name, 0)
        if time < leadEnd {
            return stepped(time - feedStart, steps: leadSteps, stepDuration: leadStepDuration, length: lead)
        }
        if time < pushStart {
            return lead
        }
        if time < tailStart {
            return lead + name * RevealCurve.easeOut(RevealCurve.progress(time, from: pushStart, duration: pushDuration))
        }
        return lead + name + stepped(time - tailStart, steps: tailSteps, stepDuration: tailStepDuration, length: tail)
    }

    /// 刻みで進めた長さ（各刻みの前の `stepMoveFraction` で動き、残りは止まる）
    private static func stepped(_ elapsed: Double, steps: Int, stepDuration: Double, length: Double) -> Double {
        guard elapsed > 0 else {
            return 0
        }
        let position = elapsed / stepDuration
        let done = min(Int(position), steps)
        guard done < steps else {
            return length
        }
        let within = RevealCurve.easeOut((position - Double(done)) / stepMoveFraction)
        return length / Double(steps) * (Double(done) + within)
    }
}

/// 案 C の見た目。きっぷの下端に取り出し口を重ね、取り出し口より下に隠したきっぷを押し上げる
struct TicketIssueReveal: View {
    /// 取り出し口の高さ
    private static let slotHeight: CGFloat = 14
    /// 取り出し口がきっぷより左右にはみ出す長さ
    private static let slotOverhang: CGFloat = 10
    /// 隠さない向きに広げる長さ（きっぷの影・押す前の 2.2 倍のハンコが収まる大きさ）
    private static let unmaskedOverflow: CGFloat = 400

    /// 演出を始めてからの秒
    let time: Double
    /// 「視差効果を減らす」か
    let reduceMotion: Bool
    /// きっぷの値
    let ticket: ResultTicket

    var body: some View {
        // 取り出し口の形と押し具合は高さに依らない（ずれだけを、きっぷの高さを読める `visualEffect` で決める）
        let pose = TicketIssueTimeline.pose(at: time, height: 0, reduceMotion: reduceMotion)
        let time = time
        let reduceMotion = reduceMotion
        RevealTicket(ticket: ticket, stampProgress: pose.stampProgress)
            .equatable()
            .visualEffect { content, proxy in
                let placed = TicketIssueTimeline.pose(at: time, height: proxy.size.height, reduceMotion: reduceMotion)
                return content
                    .offset(y: placed.ticketOffset)
                    .opacity(placed.ticketOpacity)
            }
            .mask {
                // 取り出し口がある間は、取り出し口の真ん中（きっぷの下端）より下だけを隠す。
                // 上と左右・外れた後の下は大きく広げ、影や押す前の大きなハンコを切らない
                Rectangle()
                    .padding(.bottom, pose.masksBelowSlot ? 0 : -Self.unmaskedOverflow)
                    .padding([.top, .horizontal], -Self.unmaskedOverflow)
            }
            .overlay(alignment: .bottom) {
                if pose.slotOpacity > 0 {
                    slot
                        .scaleEffect(x: pose.slotWidthScale, y: 1)
                        .offset(y: Self.slotHeight / 2 + pose.slotOffset)
                        .opacity(pose.slotOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    /// 取り出し口（墨色の細長い口。筐体の取り出し口と同じ色）
    private var slot: some View {
        Capsule()
            .fill(Color.dgInk)
            .frame(height: Self.slotHeight)
            .padding(.horizontal, -Self.slotOverhang)
    }
}

#Preview("案 C 発券") {
    @Previewable @State var round = 0
    VStack(spacing: DGSpacing.s24) {
        ResultRevealStage(
            style: .issue,
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
