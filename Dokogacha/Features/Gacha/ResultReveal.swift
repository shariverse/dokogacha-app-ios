//
//  ResultReveal.swift
//  Dokogacha
//
//  S-14 で行き先きっぷを出すときの演出（Issue #158）。標準はパタパタ行き先表示で、設定（S-16 結果の演出）でカプセル・発券に替えられる。
//  演出ごとの時間・合図・動きの値は `nonisolated` の値の型にし、画面（`ResultRevealStage`）は時刻から値を読んで描くだけにする。
//

import SwiftUI

/// S-14 で行き先きっぷを出す演出（S-13 でカプセルを開けた直後に流す）。
///
/// 設定の「結果の演出」（`ResultRevealSetting`）で選び、端末に覚える。rawValue は端末に覚える値なので変えない
nonisolated enum ResultRevealStyle: String, CaseIterable, Sendable {
    /// パタパタ行き先表示: 駅の発車標のような黒帯が候補の名前をめくって止まり、裏返って行き先きっぷになる（標準）
    case flap
    /// カプセルぱかっ: カプセルが揺れて割れ、きっぷが紙吹雪とともに飛び出す
    case capsule
    /// 発券: 券売機の取り出し口から、きっぷが少しずつ出てくる（行き先の手前でためる）
    case issue

    /// 標準の演出（まだ選んでいない端末・覚えた値が読めないとき）
    static let standard = Self.flap

    /// 設定に並べる順（標準を先頭にする）
    static let settingsOrder: [Self] = [.flap, .capsule, .issue]

    /// 演出の名前（設定の行と選ぶ画面）
    var title: LocalizedStringResource {
        switch self {
        case .flap: "パタパタ行き先表示"
        case .capsule: "カプセルぱかっ"
        case .issue: "発券"
        }
    }

    /// 演出の説明（選ぶ画面の名前の下）
    var summary: LocalizedStringResource {
        switch self {
        case .flap: "駅の行き先表示のように、候補の名前がめくれて当たりで止まります"
        case .capsule: "カプセルが揺れて割れ、紙吹雪とともにきっぷが飛び出します"
        case .issue: "券売機の口から、きっぷが少しずつ出てきます"
        }
    }
}

/// 演出の段階（画面の見出し・ボタンを出す区切り）
nonisolated enum ResultRevealPhase: Int, Comparable, Sendable {
    /// 演出の途中（行き先はまだ分からない）
    case revealing
    /// 行き先が分かった（見出し「行き先が決まりました」とレア当選を出し、VoiceOver の選択を見出しに移す）
    case decided
    /// 演出を終えた（ボタン・引き直しの欄・下部の決定を出す）
    case settled

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// S-14 にどこから入ったか
nonisolated enum ResultEntrance: Sendable {
    /// ルーム・通知から直接開いた（見終えた結果を開き直すことが多いので、短いポップインだけにする）
    case direct
    /// S-13 でカプセルを開けた直後（選んだ演出を流す）
    case afterOpening
}

/// 演出の触覚の合図（後で足すサウンドのフックも兼ねる。04 の §5）
nonisolated enum ResultRevealCue: Equatable, Sendable {
    /// ためている間の刻み（強さ 0〜1）
    case tick(intensity: Double)
    /// きっぷが取り出し口から離れた（C）
    case release
    /// 行き先が決まった瞬間
    case decided
    /// ハンコが紙に当たった
    case stamp

    /// 合図の触覚
    var feedback: SensoryFeedback {
        switch self {
        case let .tick(intensity): .impact(weight: .light, intensity: intensity)
        case .release: .impact(weight: .medium)
        case .decided: .success
        case .stamp: .impact(flexibility: .rigid, intensity: 0.9)
        }
    }
}

/// 合図 1 回分（同じ合図が続いても鳴らし直すよう、通し番号を付ける）
nonisolated struct ResultRevealCueEvent: Equatable, Sendable {
    /// 通し番号
    let sequence: Int
    /// 合図
    let cue: ResultRevealCue
}

/// 演出の予定（いつ合図を出し、いつ段階を進めるか）。時刻は演出を始めてからの秒
nonisolated struct ResultRevealPlan: Equatable, Sendable {
    /// 予定の中身
    enum EventKind: Equatable, Sendable {
        /// 触覚の合図
        case cue(ResultRevealCue)
        /// 段階を進める
        case phase(ResultRevealPhase)
    }

    /// 予定 1 つ分
    struct Event: Equatable, Sendable {
        /// 時刻（秒）
        let time: Double
        /// 中身
        let kind: EventKind
    }

    /// 予定（時刻の順）
    let events: [Event]
    /// 動きがすべて止まる時刻（これより後は最後の形のまま）
    let duration: Double

    /// - Parameters:
    ///   - cues: 触覚の合図（時刻と合図。順は問わない。時刻の順に並べ直す）
    ///   - decidedAt: 行き先が分かる時刻（`decided` に進める）
    ///   - settledAt: 演出を終える時刻（`settled` に進める）
    ///   - duration: 動きがすべて止まる時刻
    init(cues: [(Double, ResultRevealCue)], decidedAt: Double, settledAt: Double, duration: Double) {
        let all = cues.map { Event(time: $0.0, kind: .cue($0.1)) } + [
            Event(time: decidedAt, kind: .phase(.decided)),
            Event(time: settledAt, kind: .phase(.settled))
        ]
        // 同じ時刻なら段階を先にする（見出しを出してから触覚を鳴らす）
        let ordered = all.enumerated().sorted { lhs, rhs in
            if lhs.element.time != rhs.element.time {
                return lhs.element.time < rhs.element.time
            }
            return lhs.offset > rhs.offset
        }
        events = ordered.map(\.element)
        self.duration = max(duration, settledAt)
    }

    /// `decided` に進める時刻
    var decidedAt: Double {
        events.first { $0.kind == .phase(.decided) }?.time ?? 0
    }

    /// `settled` に進める時刻
    var settledAt: Double {
        events.first { $0.kind == .phase(.settled) }?.time ?? 0
    }

    /// 行き先が決まった合図の時刻（無ければ nil）
    var decidedCueAt: Double? {
        events.first { $0.kind == .cue(.decided) }?.time
    }
}

/// 演出の動きを時刻から求める道具（どれも 0〜1 の進みを受け取る）
nonisolated enum RevealCurve {
    /// 0〜1 に収める
    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// 時刻 `time` の、区間（`start` から `duration` 秒）の中の進み（0〜1）
    static func progress(_ time: Double, from start: Double, duration: Double) -> Double {
        guard duration > 0 else {
            return time >= start ? 1 : 0
        }
        return clamp((time - start) / duration)
    }

    /// だんだん遅く（3 次）
    static func easeOut(_ value: Double) -> Double {
        let rest = 1 - clamp(value)
        return 1 - rest * rest * rest
    }

    /// だんだん速く（3 次）
    static func easeIn(_ value: Double) -> Double {
        let clamped = clamp(value)
        return clamped * clamped * clamped
    }

    /// ゆっくり始まりゆっくり終わる（3 次）
    static func easeInOut(_ value: Double) -> Double {
        let clamped = clamp(value)
        return clamped < 0.5 ? 4 * clamped * clamped * clamped : 1 - pow(-2 * clamped + 2, 3) / 2
    }

    /// `from` から `to` へ `value` だけ進めた値
    static func mix(_ from: Double, _ to: Double, _ value: Double) -> Double {
        from + (to - from) * value
    }

    /// 0 から 1 へ、行き過ぎて戻るばね（SwiftUI の `spring(response:dampingFraction:)` と同じ意味の値）。
    /// - Parameters:
    ///   - time: 動き始めてからの秒（負なら 0）
    ///   - response: 1 往復の時間
    ///   - dampingFraction: 減衰の強さ（1 未満で行き過ぎる）
    static func spring(_ time: Double, response: Double, dampingFraction: Double) -> Double {
        guard time > 0 else {
            return 0
        }
        let omega = 2 * Double.pi / response
        let damping = min(dampingFraction, 0.999)
        let dampedOmega = omega * (1 - damping * damping).squareRoot()
        let decay = exp(-damping * omega * time)
        return 1 - decay * (cos(dampedOmega * time) + damping * omega / dampedOmega * sin(dampedOmega * time))
    }
}

extension EnvironmentValues {
    /// S-14 で行き先きっぷを出す演出（設定で選んだもの。`MainNavigationView` が S-13・S-14 のカバーに渡す）
    @Entry var resultRevealStyle: ResultRevealStyle = .standard
    /// S-14 にどこから入ったか（`GachaFlowView` が S-13 から替えたときに `afterOpening` にする）
    @Entry var resultEntrance: ResultEntrance = .direct
}
