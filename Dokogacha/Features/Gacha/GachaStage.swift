//
//  GachaStage.swift
//  Dokogacha
//
//  S-13 ガチャの演出の段階・文言・触覚の合図・時間（03 の S-13・04 の §5）。
//

import Foundation

/// S-13 の演出の段階（03 の S-13「レバーを押す → 回転中（1.6秒）→ 取り出し → 開く（0.5秒）→ S-14」）。
///
/// レバーを押したら、結果の画面まで止まらずに進む（カプセルを押して開ける操作は無い。Issue #158）
nonisolated enum GachaPhase: Equatable, Sendable {
    /// 待機（レバーを回せる）
    case idle
    /// 回転中（ドームが揺れ、レバーのバーが回る。自分が回したときは、この間に `drawGacha` を呼ぶ）
    case spinning
    /// 当選のカプセルがドームの底から抜け（`exit`）、取り出し口へ落ちて（`drop`）、少し止まって見せている途中
    case dropping
    /// カプセルが開いている途中（`open`）
    case opening
    /// 開け終えた（結果の画面へ進む）
    case opened

    /// 演出の途中か（レバー・閉じるボタンを押せない。開け終えた後は含めない）
    var isAnimating: Bool {
        switch self {
        case .spinning, .dropping, .opening: true
        case .idle, .opened: false
        }
    }

    /// 取り出し口にカプセルを出しているか
    var showsCapsule: Bool {
        switch self {
        case .dropping, .opening, .opened: true
        case .idle, .spinning: false
        }
    }
}

/// S-13 のタイトルとサブ文言の組み合わせ（03 の S-13 の表）。文言は `GachaView` が `Text` にする
nonisolated enum GachaCaption: Equatable, Sendable {
    /// 待機（「レバーを回してね」／「結果はメンバー全員の画面に同時に出ます」。引き直しなら「引き直し（前回の当選は除外）」）
    case ready(isReroll: Bool)
    /// 待機だが候補が無い（「レバーを回してね」／「候補がありません」。02 の F-40）
    case noCandidates
    /// 待機だが解禁していない（`open`。「レバーを回してね」／「まだガチャは解禁されていません」）
    case locked
    /// 自分が回した回転中（「ガラガラ…」／「どこに決まるかな」）
    case spinning
    /// ほかの人が回した回転中（「{名前}さんが回しました！」／「どこに決まるかな」。F-41）
    case drawnByOther(name: String)
    /// 取り出し（「ころん！」／「行き先を発表します」。カプセルが落ちてから結果の画面に替わるまで）
    case landed

    /// 段階とルームの状態から、出す文言を選ぶ
    /// - Parameters:
    ///   - phase: 演出の段階
    ///   - drawnByName: ほかの人が回したときの、回した人の表示名（自分が回したときは nil）
    ///   - status: ルームの状態（読み込む前は nil）
    ///   - isReroll: 引き直しの抽選か（除外した候補がある）
    ///   - capsuleCount: 抽選の対象の候補の数
    static func make(phase: GachaPhase, drawnByName: String?, status: RoomStatus?, isReroll: Bool, capsuleCount: Int) -> Self {
        switch phase {
        case .idle:
            if status == .drawn || status == .closed {
                // ほかの人が回した直後（回した人の名前を読んでいる間）。03 の S-13 の表の「他の人が回した」（名前が分からなければ回転中）
                return drawnByName.map(Self.drawnByOther(name:)) ?? .spinning
            }
            if status != .unlocked {
                return status == nil ? .ready(isReroll: isReroll) : .locked
            }
            return capsuleCount > 0 ? .ready(isReroll: isReroll) : .noCandidates
        case .spinning:
            return drawnByName.map(Self.drawnByOther(name:)) ?? .spinning
        case .dropping, .opening, .opened:
            return .landed
        }
    }
}

/// 演出の合図（触覚と、後で足すサウンドのフック。04 の §5「演出の各タイミングにフックを用意する」）。
///
/// 03 の S-13 の触覚: レバーを押した瞬間 `.impact(.heavy)`、回転中は 0.2 秒ごとに `.impact(.light)`（レバーがカチッと止まる刻みと同じ）、
/// 当選のカプセルがドームから抜けた瞬間 `.impact(.rigid)`、カプセルが落ちた瞬間 `.impact(.medium)`、開いた瞬間 `.impact(.soft)`
/// （行き先が決まった `.success` は、S-14 の結果の演出の決まる瞬間に鳴らす）。
/// `SensoryFeedback` への対応は画面の側（`GachaView`）で持つ
nonisolated enum GachaCue: Equatable, Sendable {
    /// レバーを押した（自分が回したときだけ）
    case leverPulled
    /// 回転中の刻み
    case spinTick
    /// 当選のカプセルがドームの底から抜けた（落ち始め）
    case capsuleReleased
    /// カプセルが取り出し口に落ちた
    case capsuleLanded
    /// カプセルが開いた
    case capsuleOpened
}

/// 合図 1 回分。同じ合図が続いても `sensoryFeedback(trigger:)` が鳴らし直すよう、通し番号を付ける
nonisolated struct GachaCueEvent: Equatable, Sendable {
    /// 通し番号
    let sequence: Int
    /// 合図
    let cue: GachaCue
}

/// 演出の時間（03 の S-13・04 の §5・プロトタイプの `@keyframes`）。どれも秒
nonisolated enum GachaTimeline {
    /// 回転中の長さ（03「回転中（1.6秒）」。`turn` の 1 回分・`shake` の 0.4 秒 × 4 回と同じ）
    static let spinDuration = DGMotion.turn.duration
    /// 回転中の触覚の間隔（03「回転中は0.2秒ごとに」）
    static let tickInterval = 0.2
    /// 回転中の刻みの数（押した瞬間の後から、回転が終わる前まで。0.2・0.4…1.4 秒の 7 回）
    static let tickCount = Int((spinDuration / tickInterval).rounded()) - 1
    /// 当選のカプセルがドームの底から抜けるまでの時間（落ち始めてから。抜けてから取り出し口に落とす。Issue #178）
    static let exitDuration = 0.35
    /// 取り出し口に落とし始めてから底に当たるまでの時間（プロトタイプの `dgDrop` の 55% の位置）
    static let dropLandingDelay = DGMotion.drop.duration * DropKeyframes.landingFraction
    /// 落ち始め（ドームから抜け始め）から、取り出し口の底に当たるまでの時間
    static let landingDelay = exitDuration + dropLandingDelay
    /// 落ちきってから開け始めるまで、取り出し口のカプセルを見せておく時間（何色のカプセルが出たかが分かる間）
    static let landedHold = 0.4
    /// 底に当たってから開け始めるまでの時間（跳ね終えるまで ＋ `landedHold`）
    static let openDelay = DGMotion.drop.duration - dropLandingDelay + landedHold
    /// カプセルが開く時間（03「開く（0.5秒）」）
    static let openDuration = DGMotion.open.duration

    /// 落ちるカプセルの動き（プロトタイプの `dgDrop`: 0% −90・透明 → 55% +6・不透明 → 75% −8 → 100% 0）
    enum DropKeyframes {
        /// 落ち始めの高さ（上に −90）
        static let startOffset: Double = -90
        /// 底に当たって沈む量
        static let landingOffset: Double = 6
        /// 跳ね返る高さ
        static let bounceOffset: Double = -8
        /// 底に当たる位置（全体の時間に対する割合）
        static let landingFraction = 0.55
        /// 跳ね返りの頂点の位置（全体の時間に対する割合）
        static let bounceFraction = 0.75
    }

    /// ドームの揺れ 1 回分の角度（プロトタイプの `dgShake`: 0 → −4° → 4° → −3° → 3° → 0。20% ずつ）
    static let shakeAngles: [Double] = [-4, 4, -3, 3, 0]
    /// レバーのバーを回す角度（04 の §5 の `turn`「720°回転」）
    static let turnDegrees: Double = 720
    /// 開くときにいちばん大きくする倍率（04 の §5 の `open`「1.6倍に拡大しながら消える」）
    static let openScale = 1.6
}
