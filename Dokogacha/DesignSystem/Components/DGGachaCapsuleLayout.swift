//
//  DGGachaCapsuleLayout.swift
//  Dokogacha
//
//  ガチャのドームに入れるカプセルの並べ方（`04_design_system.md` の §4 の GachaMachine「ドームのカプセル」・03 の S-13）。
//

import CoreGraphics

/// ドームの中のカプセル 1 個分の置き場所。
nonisolated struct DGGachaCapsulePlacement: Equatable, Sendable {
    /// 何番目のカプセルか（0 始まり。呼び出し側が渡した色の並びの番号）
    let index: Int
    /// カプセルの中心（ドームの外形（直径 250）の左上を原点とする pt）
    let center: CGPoint
    /// カプセルの傾き（度。0 以上 360 未満）
    let rotationDegrees: Double
}

/// ドームの中のカプセルを、ドームの下半分に散らして並べる。
///
/// 04 の §4 は「ランダムな回転。下半分（y 120〜200）に散らす」とあり、プロトタイプはカプセルの番号から決まる式で位置と傾きを出している
/// （x = 22 + (i × 61) mod 160、y = 120 + (i × 37) mod 80、傾き = (i × 53) mod 360。どれもドームの線の内側を原点とした左上の位置）。
/// 乱数を使うと再描画や画面ごとに並びが変わり、同じルームのメンバーで見え方がそろわないので、プロトタイプと同じ番号から決まる式にする。
/// 描くのは 03 の S-13 のとおり 50 個まで（それより多い候補は、数だけを文言で伝える）。
nonisolated enum DGGachaCapsuleLayout {
    /// ドームに描くカプセルの上限（03 の S-13「最大50個まで描画」）
    static let maxVisibleCount = 50
    /// ドームの外形の直径（04 の §4）
    static let domeDiameter: CGFloat = 250
    /// ドームの中のカプセルの直径（04 の §4）
    static let capsuleDiameter: CGFloat = 40

    /// 左端の位置の始まり（ドームの線の内側から）
    private static let originX: CGFloat = 22
    /// 1 個進むごとに横にずらす量
    private static let stepX = 61
    /// 横に散らす幅（これで割った余りを使う）
    private static let spanX = 160
    /// 上端の位置の始まり（ドームの線の内側から。下半分に入れる）
    private static let originY: CGFloat = 120
    /// 1 個進むごとに縦にずらす量
    private static let stepY = 37
    /// 縦に散らす幅（これで割った余りを使う。04 の §4「y 120〜200」）
    private static let spanY = 80
    /// 1 個進むごとに傾ける量（度）
    private static let stepDegrees = 53
    /// 1 回転（度）
    private static let fullTurn = 360

    /// 描くカプセルの数（候補の数を 0〜50 に収める）
    /// - Parameter count: 候補（カプセル）の数
    static func visibleCount(for count: Int) -> Int {
        min(max(count, 0), maxVisibleCount)
    }

    /// カプセルの置き場所を、描く順（後ろのものほど手前）に返す。
    /// - Parameter count: 候補（カプセル）の数。50 を超えた分は描かない
    static func placements(count: Int) -> [DGGachaCapsulePlacement] {
        (0..<visibleCount(for: count)).map(placement(at:))
    }

    /// `index` 番目のカプセルの置き場所
    private static func placement(at index: Int) -> DGGachaCapsulePlacement {
        // プロトタイプの位置はドームの線の内側を原点にした左上なので、線の太さと半径を足して外形の左上からの中心にする
        let inset = DGBorder.machine + capsuleDiameter / 2
        let left = originX + CGFloat((index * stepX) % spanX)
        let top = originY + CGFloat((index * stepY) % spanY)
        return DGGachaCapsulePlacement(
            index: index,
            center: CGPoint(x: left + inset, y: top + inset),
            rotationDegrees: Double((index * stepDegrees) % fullTurn)
        )
    }
}
