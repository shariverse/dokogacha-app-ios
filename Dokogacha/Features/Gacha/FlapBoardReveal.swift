//
//  FlapBoardReveal.swift
//  Dokogacha
//
//  案 B「パタパタ行き先表示」: 駅の発車標（ソラリー式）のような黒帯が、抽選の対象だった候補の名前をパタパタとめくり、
//  だんだん遅くなって当選の名前で止まる。点滅してから黒帯が裏返り、行き先きっぷになる（Issue #158）。
//

import SwiftUI

/// 案 B の時間と動き。時刻（演出を始めてからの秒）から形を求める
nonisolated enum FlapBoardTimeline {
    /// めくり始める時刻（S-13 からのフェードが終わるころ）
    static let startAt = 0.35
    /// 1 枚ずつのめくる時間（速く回って、最後はゆっくり止まる）
    static let flipDurations: [Double] = [0.14, 0.10, 0.08, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.09, 0.12, 0.16, 0.22, 0.30]
    /// 止まった後の点滅の 1 回の時間（点く → 消える → 点く）
    static let blinkInterval = 0.12
    /// 点滅の回数（点いている回）
    static let blinkCount = 2
    /// 止まってから裏返し始めるまでの間（名前を読む時間）
    static let holdAfterStop = 0.55
    /// 止まったときに名前を弾ませる時間
    static let settleBounceDuration = 0.28
    /// 止まったときに名前をいちばん大きくする倍率
    static let settleBounceScale = 1.06
    /// 黒帯が倒れて見えなくなるまでの時間
    static let foldDuration = 0.18
    /// きっぷが起き上がるばねの往復の時間
    static let unfoldResponse = 0.42
    /// きっぷが起き上がるばねの減衰
    static let unfoldDamping = 0.72
    /// きっぷが起き上がりきるまでの時間（ばねが止まるまで）
    static let unfoldDuration = 0.6
    /// きっぷが見えてからハンコを押し始めるまでの間
    static let stampDelay = 0.4
    /// ハンコが紙に当たる位置（`DGStamp` の押し込む割合と同じ）
    static let stampLandFraction = 0.7
    /// めくる刻みの触覚の強さ（速いとき・遅いとき）
    static let tickIntensity = (fast: 0.3, slow: 0.7)
    /// 決まる前に表示する「？？？」（DGDestinationBoard と同じ表記）
    static let undecided = "？？？"
    /// 何も書いていない札（候補が当選の 1 つだけのときに挟む）
    static let blank = ""

    /// めくる回数
    static var flipCount: Int {
        flipDurations.count
    }

    /// 各めくりを始める時刻
    static var flipStarts: [Double] {
        flipDurations.indices.map { index in
            startAt + flipDurations.prefix(index).reduce(0, +)
        }
    }

    /// 当選の名前で止まる時刻（行き先が分かる瞬間）
    static var stopAt: Double {
        startAt + flipDurations.reduce(0, +)
    }

    /// 黒帯が倒れ始める時刻
    static var foldStart: Double {
        stopAt + holdAfterStop
    }

    /// きっぷが起き上がり始める時刻
    static var ticketShownAt: Double {
        foldStart + foldDuration
    }

    /// ハンコを押し始める時刻
    static var stampStart: Double {
        ticketShownAt + stampDelay
    }

    /// 動きがすべて止まる時刻
    static var duration: Double {
        max(ticketShownAt + unfoldDuration, stampStart + DGMotion.stamp.duration)
    }

    /// 「視差効果を減らす」: 名前を出す時刻
    static let reducedDecideAt = 0.5
    /// 「視差効果を減らす」: 黒帯からきっぷに替える時刻
    static let reducedSwapAt = 1.15
    /// 「視差効果を減らす」: ハンコを出し始める時刻
    static var reducedStampStart: Double {
        reducedSwapAt + DGMotion.reducedFadeDuration + 0.1
    }

    /// めくって見せる文字の並び（`flipCount + 1` 個）。
    ///
    /// 最初は「？？？」、途中は当選以外の名前を順に繰り返し、最後は当選の名前。めくっても同じ文字が続かないよう、
    /// 当選以外が 1 つしか無いときは「？？？」と交互にし、1 つも無いときは白札（`blank`）と「？？？」を交互にする
    static func texts(names: [String], winner: String) -> [String] {
        var others: [String] = []
        for name in names where name != winner && !others.contains(name) {
            others.append(name)
        }
        if others.isEmpty {
            others = [blank, undecided]
        } else if others.count == 1 {
            others.append(undecided)
        }
        let middle = (1..<flipCount).map { others[($0 - 1) % others.count] }
        return [undecided] + middle + [winner]
    }

    /// 演出の予定
    static func plan(reduceMotion: Bool) -> ResultRevealPlan {
        if reduceMotion {
            let settledAt = reducedStampStart + DGMotion.reducedFadeDuration
            return ResultRevealPlan(
                cues: [(reducedDecideAt, .decided), (reducedStampStart, .stamp)],
                decidedAt: reducedDecideAt,
                settledAt: settledAt,
                duration: settledAt
            )
        }
        let slowest = flipDurations.max() ?? 1
        let fastest = flipDurations.min() ?? 0
        // 最後のめくりは「決まった」の合図にするので、刻みはその前まで
        let ticks: [(Double, ResultRevealCue)] = zip(flipStarts, flipDurations).dropLast().map { start, length in
            let slowness = slowest > fastest ? (length - fastest) / (slowest - fastest) : 0
            return (start + length, .tick(intensity: RevealCurve.mix(tickIntensity.fast, tickIntensity.slow, slowness)))
        }
        let stampDuration = DGMotion.stamp.duration
        return ResultRevealPlan(
            cues: ticks + [(stopAt, .decided), (stampStart + stampDuration * stampLandFraction, .stamp)],
            decidedAt: stopAt,
            settledAt: stampStart + stampDuration,
            duration: duration
        )
    }

    /// ある時刻の形
    struct Pose: Equatable {
        /// 見せている文字の番号（`texts` の位置）
        var index = 0
        /// めくっている途中の進み（0〜1。めくっていなければ nil。次の文字は `index + 1`）
        var flip: Double?
        /// 「視差効果を減らす」で、当選の名前に替えるフェードの進み（0〜1。使わなければ nil）
        var fadeToWinner: Double?
        /// 窓の縁を光らせているか（止まった後の点滅）
        var isLit = false
        /// 名前の大きさ（止まったときに弾ませる）
        var nameScale: Double = 1
        /// 黒帯の倒れ具合（0〜90 度）
        var boardAngle: Double = 0
        /// 黒帯の不透明度
        var boardOpacity: Double = 0
        /// きっぷの起き上がり具合（−90〜0 度）
        var ticketAngle: Double = 0
        /// きっぷの不透明度
        var ticketOpacity: Double = 1
        /// ハンコの押し具合（0〜1）
        var stampProgress: Double = 1
    }

    /// 時刻 `time` の形
    static func pose(at time: Double, reduceMotion: Bool) -> Pose {
        if reduceMotion {
            return reducedPose(at: time)
        }
        if time >= duration {
            return Pose()
        }
        if time >= ticketShownAt {
            let rise = RevealCurve.spring(time - ticketShownAt, response: unfoldResponse, dampingFraction: unfoldDamping)
            return Pose(
                ticketAngle: RevealCurve.mix(-90, 0, rise),
                stampProgress: RevealCurve.progress(time, from: stampStart, duration: DGMotion.stamp.duration)
            )
        }
        var pose = Pose(index: flipCount, boardOpacity: 1, ticketOpacity: 0, stampProgress: 0)
        if time < stopAt {
            pose.index = 0
            for (offset, start) in flipStarts.enumerated() where time >= start {
                pose.index = offset
                pose.flip = RevealCurve.progress(time, from: start, duration: flipDurations[offset])
            }
            if pose.flip == 1 {
                pose.index += 1
                pose.flip = nil
            }
            return pose
        }
        let sinceStop = time - stopAt
        let blink = Int(sinceStop / blinkInterval)
        pose.isLit = blink < blinkCount * 2 && blink.isMultiple(of: 2)
        let bounce = RevealCurve.progress(sinceStop, from: 0, duration: settleBounceDuration)
        pose.nameScale = 1 + (settleBounceScale - 1) * sin(Double.pi * bounce)
        pose.boardAngle = 90 * RevealCurve.easeIn(RevealCurve.progress(time, from: foldStart, duration: foldDuration))
        return pose
    }

    /// 「視差効果を減らす」の形（「？？？」→ フェードで当選の名前 → フェードできっぷ）
    private static func reducedPose(at time: Double) -> Pose {
        let swap = RevealCurve.progress(time, from: reducedSwapAt, duration: DGMotion.reducedFadeDuration)
        return Pose(
            index: 0,
            fadeToWinner: RevealCurve.progress(time, from: reducedDecideAt, duration: DGMotion.reducedFadeDuration),
            boardOpacity: 1 - swap,
            ticketOpacity: swap,
            stampProgress: RevealCurve.progress(time, from: reducedStampStart, duration: DGMotion.reducedFadeDuration)
        )
    }
}

/// 案 B の見た目。きっぷと同じ大きさの黒帯を重ね、黒帯が倒れたらきっぷが起き上がる
struct FlapBoardReveal: View {
    /// いまの形
    let pose: FlapBoardTimeline.Pose
    /// きっぷの値
    let ticket: ResultTicket
    /// めくって見せる文字の並び（`FlapBoardTimeline.texts`）
    let texts: [String]
    /// 抽選の対象だった候補の数
    let capsuleCount: Int

    /// 立体に見せる遠近の強さ
    private static let perspective: CGFloat = 0.55

    var body: some View {
        RevealTicket(ticket: ticket, stampProgress: pose.stampProgress)
            .equatable()
            .rotation3DEffect(.degrees(pose.ticketAngle), axis: (x: 1, y: 0, z: 0), perspective: Self.perspective)
            .opacity(pose.ticketOpacity)
            .overlay {
                if pose.boardOpacity > 0 {
                    FlapBoard(pose: pose, texts: texts, roomName: ticket.roomName, capsuleCount: capsuleCount)
                        .rotation3DEffect(.degrees(pose.boardAngle), axis: (x: 1, y: 0, z: 0), perspective: Self.perspective)
                        .opacity(pose.boardOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// 発車標の黒帯（上に「行き先」とルーム名、真ん中にめくれる名前の窓、下に「カプセル N個」）
private struct FlapBoard: View {
    /// 黒帯の角丸（きっぷと同じ）
    private static let cornerRadius: CGFloat = 18
    /// 影（きっぷと同じ y5）
    private static let shadow = DGShadow(x: 0, y: 5, blur: 0, color: .dgInk)
    /// 「行き先」の文字の大きさ
    private static let labelSize: CGFloat = 11
    /// カプセルの数の文字の大きさ
    private static let countSize: CGFloat = 15

    let pose: FlapBoardTimeline.Pose
    let texts: [String]
    let roomName: String
    let capsuleCount: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        VStack(alignment: .leading, spacing: DGSpacing.s12) {
            HStack(alignment: .firstTextBaseline, spacing: DGSpacing.s8) {
                Text("行き先")
                    .font(.dgBody(Self.labelSize, weight: .bold, relativeTo: .caption))
                Spacer(minLength: 0)
                Text(verbatim: roomName)
                    .font(.dgBody(DGTypeScale.bodyCaption.size, weight: .bold, relativeTo: .caption))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.dgTextOnInk)
            Spacer(minLength: 0)
            SplitFlapWindow(pose: pose, texts: texts)
            Spacer(minLength: 0)
            capsules
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(DGSpacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dgInk, in: shape)
        .dgHardShadow(Self.shadow, cornerRadius: Self.cornerRadius)
    }

    /// 「カプセル N個」（DGDestinationBoard と同じ見た目）
    private var capsules: some View {
        let count = Text(verbatim: "\(capsuleCount)")
            .font(.dgBody(Self.countSize, weight: .bold, relativeTo: .caption))
            .foregroundStyle(Color.dgAccentSecondary)
        return Text("カプセル \(count)個")
            .font(.dg(.bodyCaption))
            .foregroundStyle(Color.dgTextOnInk)
    }
}

/// めくれる名前の窓（上下 2 枚の札に分かれ、上の札が手前に倒れてから下の札が落ちてくる）
private struct SplitFlapWindow: View {
    /// 窓の高さ（黒帯の真ん中を占める大きさ）
    private static let height: CGFloat = 112
    /// 札の角丸
    private static let cornerRadius: CGFloat = DGRadius.sm
    /// 札の縁と、上下の札の間の線の太さ
    private static let lineWidth: CGFloat = DGBorder.regular
    /// 名前を 1 行に収めるときに縮める下限
    private static let minimumScale: CGFloat = 0.45
    /// 倒れている札にかける影の濃さ（真横を向いたとき）
    private static let foldShade = 0.55

    let pose: FlapBoardTimeline.Pose
    let texts: [String]

    var body: some View {
        ZStack {
            if let fade = pose.fadeToWinner {
                card(texts.first ?? "")
                    .opacity(1 - fade)
                card(texts.last ?? "")
                    .opacity(fade)
            } else {
                flipping
            }
        }
        .frame(height: Self.height)
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(pose.isLit ? Color.dgAccentSecondary : Color.dgTextSecondary, lineWidth: Self.lineWidth)
        }
        .overlay {
            // 上下の札の境目
            Rectangle()
                .fill(Color.dgInk)
                .frame(height: Self.lineWidth)
        }
        .scaleEffect(pose.nameScale)
    }

    /// めくっている札（奥に次の上半分と今の下半分、手前に倒れる札）
    @ViewBuilder private var flipping: some View {
        let current = text(at: pose.index)
        let next = text(at: pose.index + 1)
        if let flip = pose.flip {
            ZStack {
                VStack(spacing: 0) {
                    half(next, isTop: true)
                    half(current, isTop: false)
                }
                if flip < 0.5 {
                    // 今の札の上半分が、真ん中の線を軸に手前へ倒れる
                    let angle = -90 * flip / 0.5
                    half(current, isTop: true)
                        .overlay(Color.dgInk.opacity(Self.foldShade * -angle / 90))
                        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    // 次の札の下半分が、真ん中の線を軸に起き上がって落ちてくる
                    let angle = 90 * (1 - (flip - 0.5) / 0.5)
                    half(next, isTop: false)
                        .overlay(Color.dgInk.opacity(Self.foldShade * angle / 90))
                        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        } else {
            card(current)
        }
    }

    /// 番号の文字（範囲の外なら最後）
    private func text(at index: Int) -> String {
        texts.indices.contains(index) ? texts[index] : (texts.last ?? "")
    }

    /// 札 1 枚（名前は見出しの黄色。1 行に収まらなければ縮める）
    private func card(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.dg(.displayXL))
            .foregroundStyle(Color.dgAccentSecondary)
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
            .padding(.horizontal, DGSpacing.s12)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(Color.dgInk, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    /// 札の上半分か下半分
    private func half(_ text: String, isTop: Bool) -> some View {
        card(text)
            .frame(height: Self.height / 2, alignment: isTop ? .top : .bottom)
            .clipped()
    }
}

#Preview("案 B パタパタ行き先表示") {
    @Previewable @State var round = 0
    VStack(spacing: DGSpacing.s24) {
        ResultRevealStage(
            style: .flap,
            ticket: ResultRevealPreview.ticket,
            capsuleColor: .dgCapsule(at: 0),
            flapNames: ["サンシャイン水族館", "明治神宮", "代々木公園"],
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
