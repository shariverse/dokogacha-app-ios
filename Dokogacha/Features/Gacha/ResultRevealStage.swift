//
//  ResultRevealStage.swift
//  Dokogacha
//
//  S-14 で、S-13 から替わった直後に行き先きっぷを出す演出（パタパタ行き先表示・カプセルぱかっ・発券）を流す舞台（Issue #158）。
//

import SwiftUI

/// 行き先きっぷの置き場所に、選んだ演出を流す。
///
/// - 動きは時刻だけから決める（`TimelineView` の時刻から、演出ごとの `pose(at:)` を読んで描く）。止めるときは最後の形に跳ぶだけで済む
/// - 触覚の合図と段階（`decided`・`settled`）は、演出ごとの予定（`ResultRevealPlan`）の時刻に `.task` から出す。
///   段階は `onPhase` で画面に渡し、画面が見出し・ボタンを出す
/// - 演出の途中に押すと、最後まで飛ばす（まだなら「決まった」の触覚だけ鳴らす）
/// - VoiceOver: 重ねた飾り（カプセル・黒帯・取り出し口・紙吹雪）は読まない。きっぷは行き先が分かるまで読ませない
///   （見出しへの選択の移動は画面の側。`ResultView`）
/// - 「視差効果を減らす」では、演出ごとにフェード（0.2 秒）だけの流れにする（04 の §5）
/// - 設定（S-16）の見本でも同じものを流す（`onPhase` は使わない）
struct ResultRevealStage: View {
    /// 演出
    let style: ResultRevealStyle
    /// きっぷの値
    let ticket: ResultTicket
    /// 当選したカプセルの色（カプセルぱかっ）
    let capsuleColor: Color
    /// 抽選の対象だった候補の名前（パタパタ行き先表示）
    let flapNames: [String]
    /// 抽選の対象だった候補の数（パタパタ行き先表示）
    let capsuleCount: Int
    /// 常に「視差効果を減らす」の流れで動かすか（UI テスト）
    let forcesReducedMotion: Bool
    /// 段階が進んだ
    let onPhase: (ResultRevealPhase) -> Void

    /// 実際より前にずれた予定を「遅れた」とみなす幅（秒）
    private static let lateTolerance = 0.05

    /// 演出を始めた時刻（押して飛ばしたら、最後まで進んだことにする時刻に替える）
    @State private var startDate: Date?
    /// いまの段階
    @State private var phase: ResultRevealPhase = .revealing
    /// 動きがすべて止まったか（止まったら時刻を進めない）
    @State private var isFinished = false
    /// 「決まった」の触覚を鳴らしたか
    @State private var hasPlayedDecidedCue = false
    /// 触覚の合図
    @State private var cue: ResultRevealCueEvent?
    /// 合図の通し番号
    @State private var cueSequence = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// - Parameters:
    ///   - style: 演出
    ///   - ticket: きっぷの値
    ///   - capsuleColor: 当選したカプセルの色
    ///   - flapNames: 抽選の対象だった候補の名前
    ///   - capsuleCount: 抽選の対象だった候補の数
    ///   - forcesReducedMotion: 常に「視差効果を減らす」の流れで動かすか（UI テスト）
    ///   - onPhase: 段階が進んだ
    init(
        style: ResultRevealStyle,
        ticket: ResultTicket,
        capsuleColor: Color,
        flapNames: [String],
        capsuleCount: Int,
        forcesReducedMotion: Bool = false,
        onPhase: @escaping (ResultRevealPhase) -> Void
    ) {
        self.style = style
        self.ticket = ticket
        self.capsuleColor = capsuleColor
        self.flapNames = flapNames
        self.capsuleCount = capsuleCount
        self.forcesReducedMotion = forcesReducedMotion
        self.onPhase = onPhase
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isFinished || startDate == nil)) { context in
            reveal(at: elapsed(at: context.date))
        }
        .accessibilityHidden(phase == .revealing)
        .sensoryFeedback(trigger: cue) { _, event in
            event?.cue.feedback
        }
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { skip() }, including: isFinished ? .subviews : .all)
        .onAppear {
            if startDate == nil {
                startDate = .now
            }
        }
        .task(id: startDate) {
            await runPlan()
        }
    }

    /// 演出ごとの予定
    static func plan(for style: ResultRevealStyle, reduceMotion: Bool) -> ResultRevealPlan {
        switch style {
        case .flap: FlapBoardTimeline.plan(reduceMotion: reduceMotion)
        case .capsule: CapsuleBurstTimeline.plan(reduceMotion: reduceMotion)
        case .issue: TicketIssueTimeline.plan(reduceMotion: reduceMotion)
        }
    }

    /// 「視差効果を減らす」か
    private var reduceMotion: Bool {
        systemReduceMotion || forcesReducedMotion
    }

    private var plan: ResultRevealPlan {
        Self.plan(for: style, reduceMotion: reduceMotion)
    }

    /// 時刻 `date` の、演出を始めてからの秒（始める前は 0。止まった後は最後の形になる時刻）
    private func elapsed(at date: Date) -> Double {
        guard let startDate else {
            return 0
        }
        if isFinished {
            return plan.duration + 1
        }
        return date.timeIntervalSince(startDate)
    }

    /// 時刻 `time` の演出の見た目
    @ViewBuilder private func reveal(at time: Double) -> some View {
        switch style {
        case .flap:
            FlapBoardReveal(
                pose: FlapBoardTimeline.pose(at: time, reduceMotion: reduceMotion),
                ticket: ticket,
                texts: FlapBoardTimeline.texts(names: flapNames, winner: ticket.destinationName),
                capsuleCount: capsuleCount
            )
        case .capsule:
            CapsuleBurstReveal(
                pose: CapsuleBurstTimeline.pose(at: time, reduceMotion: reduceMotion),
                ticket: ticket,
                capsuleColor: capsuleColor
            )
        case .issue:
            TicketIssueReveal(time: time, reduceMotion: reduceMotion, ticket: ticket)
        }
    }

    /// 予定の時刻に合図を出し、段階を進める。遅れた予定（押して飛ばした後）は、段階と「決まった」の触覚だけを出す
    private func runPlan() async {
        guard let startDate else {
            return
        }
        let plan = plan
        for event in plan.events {
            let delay = event.time - Date.now.timeIntervalSince(startDate)
            if delay > 0 {
                guard (try? await Task.sleep(for: .seconds(delay))) != nil, !Task.isCancelled else {
                    return
                }
            }
            apply(event, isLate: delay < -Self.lateTolerance)
        }
        let rest = plan.duration - Date.now.timeIntervalSince(startDate)
        if rest > 0 {
            guard (try? await Task.sleep(for: .seconds(rest))) != nil, !Task.isCancelled else {
                return
            }
        }
        isFinished = true
    }

    /// 予定 1 つを出す
    private func apply(_ event: ResultRevealPlan.Event, isLate: Bool) {
        switch event.kind {
        case let .phase(next):
            guard next > phase else {
                return
            }
            phase = next
            onPhase(next)
        case .cue(.decided):
            guard !hasPlayedDecidedCue else {
                return
            }
            hasPlayedDecidedCue = true
            emit(.decided)
        case let .cue(value):
            if !isLate {
                emit(value)
            }
        }
    }

    /// 合図を出す
    private func emit(_ value: ResultRevealCue) {
        cueSequence += 1
        cue = ResultRevealCueEvent(sequence: cueSequence, cue: value)
    }

    /// 演出を最後まで飛ばす（予定をやり直し、遅れた予定として段階だけを進める）
    private func skip() {
        guard !isFinished, phase < .settled else {
            return
        }
        startDate = Date.now.addingTimeInterval(-plan.duration)
    }
}

/// 演出の中で描くきっぷ。値（きっぷ・ハンコの押し具合）が変わらなければ描き直さない（`equatable()`）。
///
/// 演出は毎フレーム時刻から形を求めて描き直すので、きっぷの中身まで毎回組み直さないようにする
nonisolated struct RevealTicket: View, Equatable {
    /// きっぷの値
    let ticket: ResultTicket
    /// ハンコの押し具合（0〜1）
    let stampProgress: Double

    var body: some View {
        ResultTicketView(ticket: ticket, stampProgress: stampProgress)
    }
}

/// Preview のきっぷ
enum ResultRevealPreview {
    /// 週末のランチでサンシャイン水族館が当たったきっぷ
    static let ticket = ResultTicket(
        roomName: "週末のランチ",
        destinationName: "サンシャイン水族館",
        area: "東京・豊島区",
        category: .aquarium,
        note: "ペンギンが空を飛ぶ水槽が見たい",
        author: .member("はるか"),
        likeCount: 2,
        percent: 45,
        drawnAt: Date(timeIntervalSince1970: 1_792_555_200),
        isRare: false
    )
}
