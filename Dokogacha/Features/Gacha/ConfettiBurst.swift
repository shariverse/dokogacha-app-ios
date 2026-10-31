//
//  ConfettiBurst.swift
//  Dokogacha
//
//  結果の演出「カプセルぱかっ」の紙吹雪（Issue #158）。カプセルの 6 色の小片を中心から放ち、空気で減速しながら落とす。
//

import SwiftUI

/// 紙吹雪の小片 1 つ分（中心からの飛び方・形・色）。乱数を使わず、番号から決める（毎回同じ散り方にする）
nonisolated struct ConfettiPiece: Equatable, Sendable {
    /// 形
    enum Shape: Equatable, Sendable {
        /// 丸
        case dot
        /// 四角
        case chip
        /// 細長い帯
        case strip

        /// 大きさ
        var size: CGSize {
            switch self {
            case .dot: CGSize(width: 8, height: 8)
            case .chip: CGSize(width: 10, height: 7)
            case .strip: CGSize(width: 14, height: 5)
            }
        }
    }

    /// 小片の数
    static let count = 42
    /// 重力（pt / 秒²）
    static let gravity: Double = 760
    /// 空気の抵抗（1 秒あたりの減速の強さ）
    static let drag: Double = 2.4
    /// 消え始めるまでの時間（これより後は薄くしていく）
    static let fadeStart: Double = 1.1
    /// 消えきる時刻
    static let lifetime = CapsuleBurstTimeline.confettiLifetime

    /// 飛ぶ向き（ラジアン。0 が右、−π/2 が真上）
    let angle: Double
    /// 初めの速さ（pt / 秒）
    let speed: Double
    /// 回る速さ（度 / 秒）
    let spin: Double
    /// 形
    let shape: Shape
    /// カプセルの色の番号
    let colorIndex: Int

    /// 番号 `index` の小片（上向きに広く散らし、速さ・回転・形・色をずらす）
    static func make(index: Int) -> Self {
        let spread = Self.unit(index, salt: 1)
        let shapes: [Shape] = [.dot, .chip, .strip]
        return Self(
            angle: -Double.pi / 2 + (spread - 0.5) * Double.pi * 1.7,
            speed: 360 + 380 * Self.unit(index, salt: 2),
            spin: (Self.unit(index, salt: 3) - 0.5) * 900,
            shape: shapes[index % shapes.count],
            colorIndex: index % Color.dgCapsules.count
        )
    }

    /// すべての小片
    static let all: [Self] = (0..<count).map(make(index:))

    /// 時刻 `time`（放ってからの秒）の、中心からのずれ
    func offset(at time: Double) -> CGSize {
        let travel = speed / Self.drag * (1 - exp(-Self.drag * time))
        return CGSize(
            width: cos(angle) * travel,
            height: sin(angle) * travel + Self.gravity * time * time / 2
        )
    }

    /// 時刻 `time` の不透明度
    static func opacity(at time: Double) -> Double {
        1 - RevealCurve.progress(time, from: fadeStart, duration: lifetime - fadeStart)
    }

    /// 番号と種から作る 0〜1 の値（同じ番号なら毎回同じ）
    private static func unit(_ index: Int, salt: Int) -> Double {
        let value = sin(Double(index * 127 + salt * 311) * 12.9898) * 43_758.5453
        return value - value.rounded(.down)
    }
}

/// 紙吹雪（`ConfettiPiece` を `Canvas` で描く）。置いた場所の中心から放つ。大きさは置き場所を超えて広がる
struct ConfettiBurst: View {
    /// 描く範囲（中心から散る小片が収まる大きさ）
    private static let canvasSize = CGSize(width: 640, height: 760)
    /// 小片の縁の太さ
    private static let lineWidth: CGFloat = 1.5

    /// 放ってからの秒
    let time: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.opacity = ConfettiPiece.opacity(at: time)
            for piece in ConfettiPiece.all {
                let offset = piece.offset(at: time)
                var pieceContext = context
                pieceContext.translateBy(x: center.x + offset.width, y: center.y + offset.height)
                pieceContext.rotate(by: .degrees(piece.spin * time))
                let size = piece.shape.size
                let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
                let path = piece.shape == .dot ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                pieceContext.fill(path, with: .color(.dgCapsule(at: piece.colorIndex)))
                pieceContext.stroke(path, with: .color(.dgInk), lineWidth: Self.lineWidth)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
    }
}
