//
//  Motion.swift
//  Dokogacha
//
//  `docs/spec/design/tokens.json` の `motion` を写したアニメーションのトークン（`04_design_system.md` の §5）。
//  「視差効果を減らす」がオンのときの切り替え（フェード 0.2 秒だけ）は `DGMotion.reducedFade` を使う。
//

import SwiftUI

/// アニメーションの時間の曲線。
nonisolated enum DGMotionCurve: Sendable, Equatable {
    /// だんだん速く（`easeIn`）
    case easeIn
    /// だんだん遅く（`easeOut`）
    case easeOut
    /// ゆっくり始まりゆっくり終わる（`easeInOut`）
    case easeInOut
    /// CSS の `cubic-bezier(x1, y1, x2, y2)` と同じ制御点の曲線
    case bezier(Double, Double, Double, Double)
}

/// アニメーション 1 つ分の値（時間・曲線・遅れ・繰り返し）。
///
/// `Animation` からは値を読み出せないので、値を持つ型にしてテストで tokens.json と突き合わせ、
/// 描くときに `animation` で `Animation` に変える。
nonisolated struct DGMotionSpec: Sendable, Equatable {
    /// 1 回分の時間（秒）。繰り返すものは 1 周期の時間
    let duration: Double
    /// 時間の曲線。資料で決まっていないものは `nil`（`easeInOut` で動かす）
    let curve: DGMotionCurve?
    /// 始めるまでの遅れ（秒）
    var delay: Double = 0
    /// 繰り返す回数。`nil` なら 1 回だけ
    var repeatCount: Int?

    /// この値の SwiftUI のアニメーション（遅れ・繰り返しを含む。繰り返しは行って戻る）
    var animation: Animation {
        var animation: Animation = switch curve {
        case .easeIn: .easeIn(duration: duration)
        case .easeOut: .easeOut(duration: duration)
        case .easeInOut, nil: .easeInOut(duration: duration)
        case let .bezier(x1, y1, x2, y2): .timingCurve(x1, y1, x2, y2, duration: duration)
        }
        if let repeatCount {
            animation = animation.repeatCount(repeatCount, autoreverses: true)
        }
        return animation.delay(delay)
    }
}

/// 演出ごとのアニメーションのトークン（`motion`）。
///
/// 動きの中身（揺れの角度・落ちる距離など）は部品の側で持ち、ここは時間と曲線だけを持つ。
nonisolated enum DGMotion {
    /// ドームの揺れ（`motion.shake`。0.4 秒 × 4 回）
    static let shake = DGMotionSpec(duration: 0.4, curve: .easeInOut, repeatCount: 4)
    /// レバーのバーの回転（`motion.turn`）
    static let turn = DGMotionSpec(duration: 1.6, curve: .bezier(0.4, 0, 0.2, 1))
    /// 出てくるカプセルの落下（`motion.drop`）
    static let drop = DGMotionSpec(duration: 0.7, curve: .easeOut)
    /// 出てきたカプセルの拡大縮小（`motion.pulse`。1.2 秒周期、0.8 秒後から。止めるまで繰り返す）
    static let pulse = DGMotionSpec(duration: 1.2, curve: nil, delay: 0.8)
    /// カプセルが開いて消える（`motion.open`）
    static let open = DGMotionSpec(duration: 0.5, curve: .easeIn)
    /// きっぷが出てくる（`motion.pop`）。SwiftUI では `popSpring` を使う
    static let pop = DGMotionSpec(duration: 0.45, curve: .bezier(0.2, 0.9, 0.3, 1.3))
    /// 決定スタンプ（`motion.stamp`。0.5 秒遅れて 0.5 秒）
    static let stamp = DGMotionSpec(duration: 0.5, curve: nil, delay: 0.5)
    /// 出やすさのバーの幅の変化（`motion.meter`）
    static let meter = DGMotionSpec(duration: 0.35, curve: .easeOut)
    /// トーストの出入り（`motion.toast`）
    static let toast = DGMotionSpec(duration: 0.25, curve: nil)
    /// トーストを出しておく時間（秒。`motion.toast.visibleFor`）
    static let toastVisibleFor: Double = 2.2
    /// ボタンを押したときの縮みと影の変化（04 の §4 の Button「0.1秒」。tokens.json には無い）
    static let press = DGMotionSpec(duration: 0.1, curve: .easeOut)
    /// いいねのハートを弾ませる時間（04 の §5 の「いいね」の「0.25秒（spring）」。tokens.json には無い）。
    ///
    /// 大きくして戻すまでの合計の時間。曲線はばねで、`DGLikeButton` が `SpringKeyframe` を半分ずつに分けて使う
    /// （`DGMotionCurve` はばねを持たないので `curve` は nil）
    static let like = DGMotionSpec(duration: 0.25, curve: nil)
    /// いいねのハートをいちばん大きくしたときの倍率（04 の §5 の「いいね」の「1.0→1.25→1.0」）
    static let likeScale: CGFloat = 1.25

    /// きっぷが出てくるばね（04 の §5 の `pop` の「SwiftUI では」の値）。
    ///
    /// `cubic-bezier(.2,.9,.3,1.3)` は行き過ぎて戻る曲線で、SwiftUI ではばねのほうが自然に見えるため。
    static var popSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.6)
    }

    /// 「視差効果を減らす」がオンのときに、動きの代わりに使うフェードの時間（秒。04 の §5）
    static let reducedFadeDuration: Double = 0.2

    /// 「視差効果を減らす」がオンのときに使う切り替え（フェード 0.2 秒だけ）
    static var reducedFade: Animation {
        .easeInOut(duration: reducedFadeDuration)
    }
}
