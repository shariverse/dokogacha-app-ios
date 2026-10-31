//
//  DGGachaMachine.swift
//  Dokogacha
//
//  ガチャの筐体（`04_design_system.md` の §4 の GachaMachine・03 の S-13）。
//

import SwiftUI

/// カプセルトイの筐体。上にカプセルの入ったドーム、下に朱色の本体（ネームプレート・レバー・取り出し口）を重ねる。
///
/// ドーム（直径 250・線 5・`surface.gachaDome`・左上にハイライト）に、候補の色のカプセル（直径 40）を 50 個まで散らす（`DGGachaCapsuleLayout`）。
/// 本体（280×210・ドームに 14 重ねる・線 5・角丸「上 14・下 30」・`accent.primary`）の左にレバー（直径 96）、右下に取り出し口（96×76）を置く。
/// 当選したカプセル（直径 60・白い線 4）は、`dispensedColor` を渡すと取り出し口に出る（押せない。自動で開ける。Issue #158）。
///
/// ここは形と静止状態だけを描き、動き（ドームの揺れ・レバーの回転・カプセルの落下・開く）は画面の側（S-13）で付ける。
/// そのために、動かす値（傾き・回転角・ずれ・大きさ・不透明度）を `Pose` で受け取る。
/// 筐体の大きさは 04 の値で固定し、Dynamic Type では変えない（ネームプレートの文字だけ、本体に収まる大きさまで追従する）。
/// ドメインのモデルには依存させず、カプセルの色の並びだけを受け取る。
struct DGGachaMachine: View {
    /// 動かす値。静止状態は `rest`
    nonisolated struct Pose: Equatable, Sendable {
        /// ドームの傾き（度。`shake` で揺らす）
        var domeRotationDegrees: Double = 0
        /// レバーのバーの回転角（度。`turn` で回す）
        var leverRotationDegrees: Double = 0
        /// 取り出し口のカプセルの縦のずれ（pt。`drop` で上から落とす）
        var dispensedOffsetY: CGFloat = 0
        /// 取り出し口のカプセルの大きさの倍率（`open` で変える）
        var dispensedScale: CGFloat = 1
        /// 取り出し口のカプセルの不透明度（`drop`・`open` で変える）
        var dispensedOpacity: Double = 1

        /// 静止状態
        static let rest = Pose()
    }

    // MARK: 寸法（04 の §4 の GachaMachine）

    /// 本体の幅
    private static let bodyWidth: CGFloat = 280
    /// 本体の高さ
    private static let bodyHeight: CGFloat = 210
    /// 本体がドームに重なる量
    private static let bodyOverlap: CGFloat = 14
    /// 本体の上の角丸
    private static let bodyTopRadius: CGFloat = 14
    /// 本体の下の角丸
    private static let bodyBottomRadius: CGFloat = 30
    /// ドームのハイライトの大きさ
    private static let highlightSize = CGSize(width: 46, height: 18)
    /// ドームのハイライトの中心（ドームの外形の左上から。プロトタイプの位置）
    private static let highlightCenter = CGPoint(x: 68, y: 42)
    /// ドームのハイライトの傾き（度）
    private static let highlightRotationDegrees: Double = -30
    /// ドームのハイライトの不透明度（04 の §4「白90%」）
    private static let highlightOpacity: Double = 0.9
    /// ネームプレートの上端（本体の外形の上から。線 5 ＋プロトタイプの上の余白 22）
    private static let nameplateTop: CGFloat = 27
    /// ネームプレートの文字の大きさ
    private static let nameplateTextSize: CGFloat = 15
    /// ネームプレートの左右の余白（プロトタイプの値）
    private static let nameplateHorizontalPadding: CGFloat = 14
    /// ネームプレートの角丸
    private static let nameplateCornerRadius: CGFloat = 8
    /// ネームプレートの文字の大きさの上限（これより大きくするとレバーに重なる）
    private static let nameplateMaxTypeSize: DynamicTypeSize = .xxxLarge
    /// レバーの左上（本体の外形の左上から。線 5 ＋プロトタイプの位置 x30・y70）
    private static let leverOrigin = CGPoint(x: 35, y: 75)
    /// レバーの直径
    private static let leverDiameter: CGFloat = 96
    /// レバーのバーの大きさ
    private static let leverBarSize = CGSize(width: 72, height: 18)
    /// レバーのバーの線の太さ
    private static let leverBarLineWidth: CGFloat = 3
    /// 取り出し口の右下からの距離（本体の外形の右下から。線 5 ＋プロトタイプの位置 右26・下26）
    private static let outletInset: CGFloat = 31
    /// 取り出し口の大きさ
    private static let outletSize = CGSize(width: 96, height: 76)
    /// 取り出し口の下の余白（カプセルの下端まで。プロトタイプの値）
    private static let outletBottomPadding: CGFloat = 8
    /// 取り出し口から出てくるカプセルの直径
    private static let dispensedDiameter: CGFloat = 60
    /// 取り出し口から出てくるカプセルの白い縁の太さ
    private static let dispensedLineWidth: CGFloat = 4

    /// 筐体全体の大きさ（ドームと本体を重ねた外形）
    static let size = CGSize(
        width: bodyWidth,
        height: DGGachaCapsuleLayout.domeDiameter + bodyHeight - bodyOverlap
    )

    /// ドームに入れるカプセルの色（候補の投稿順の `Color.dgCapsule(at:)`）。数がカプセルの数になる
    let capsuleColors: [Color]
    /// 取り出し口に出ている当選のカプセルの色。出ていなければ `nil`
    let dispensedColor: Color?
    /// レバーを回せるか（回転中・取り出し中・候補が 0 件のときは `false`）
    let isLeverEnabled: Bool
    /// 動かす値
    let pose: Pose
    /// レバーを押したときの処理
    let onTurnLever: () -> Void

    /// - Parameters:
    ///   - capsuleColors: ドームに入れるカプセルの色（50 個を超えた分は描かない）
    ///   - dispensedColor: 取り出し口に出ている当選のカプセルの色。出ていなければ `nil`
    ///   - isLeverEnabled: レバーを回せるか
    ///   - pose: 動かす値。静止状態は `.rest`
    ///   - onTurnLever: レバーを押したときの処理
    init(
        capsuleColors: [Color],
        dispensedColor: Color? = nil,
        isLeverEnabled: Bool = true,
        pose: Pose = .rest,
        onTurnLever: @escaping () -> Void
    ) {
        self.capsuleColors = capsuleColors
        self.dispensedColor = dispensedColor
        self.isLeverEnabled = isLeverEnabled
        self.pose = pose
        self.onTurnLever = onTurnLever
    }

    var body: some View {
        VStack(spacing: -Self.bodyOverlap) {
            dome
                // ドームを本体の手前に重ねる（04 の §4「ドームに14重ねる」はドームが上）
                .zIndex(1)
            machineBody
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement(children: .contain)
    }

    // MARK: ドーム

    /// カプセルの入ったドーム。VoiceOver では「ガチャ。カプセル N個」と読む
    private var dome: some View {
        let diameter = DGGachaCapsuleLayout.domeDiameter
        let placements = DGGachaCapsuleLayout.placements(count: capsuleColors.count)
        return ZStack(alignment: .topLeading) {
            Color.dgSurfaceGachaDome
            ForEach(placements, id: \.index) { placement in
                CapsuleBall(color: capsuleColors[placement.index])
                    .frame(width: DGGachaCapsuleLayout.capsuleDiameter, height: DGGachaCapsuleLayout.capsuleDiameter)
                    .rotationEffect(.degrees(placement.rotationDegrees))
                    .position(placement.center)
            }
            Capsule()
                .fill(Color.dgSurfaceCard.opacity(Self.highlightOpacity))
                .frame(width: Self.highlightSize.width, height: Self.highlightSize.height)
                .rotationEffect(.degrees(Self.highlightRotationDegrees))
                .position(Self.highlightCenter)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.dgInk, lineWidth: DGBorder.machine))
        .rotationEffect(.degrees(pose.domeRotationDegrees))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ガチャ。カプセル \(capsuleColors.count)個"))
    }

    // MARK: 本体

    /// 朱色の本体（ネームプレート・レバー・取り出し口）
    private var machineBody: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Self.bodyTopRadius,
            bottomLeadingRadius: Self.bodyBottomRadius,
            bottomTrailingRadius: Self.bodyBottomRadius,
            topTrailingRadius: Self.bodyTopRadius
        )
        return shape
            .fill(Color.dgAccentPrimary)
            .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.machine))
            .frame(width: Self.bodyWidth, height: Self.bodyHeight)
            .overlay(alignment: .top) {
                nameplate
                    .padding(.top, Self.nameplateTop)
            }
            .overlay(alignment: .topLeading) {
                lever
                    .padding(.leading, Self.leverOrigin.x)
                    .padding(.top, Self.leverOrigin.y)
            }
            .overlay(alignment: .bottomTrailing) {
                outlet
                    .padding(.trailing, Self.outletInset)
                    .padding(.bottom, Self.outletInset)
            }
    }

    /// 「ドコガチャ」のネームプレート。飾りなので VoiceOver では読まない
    private var nameplate: some View {
        Text("ドコガチャ")
            .font(.dgDisplay(Self.nameplateTextSize, relativeTo: .headline))
            .foregroundStyle(Color.dgInk)
            .lineLimit(1)
            .padding(.horizontal, Self.nameplateHorizontalPadding)
            .padding(.vertical, DGSpacing.s4)
            .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: Self.nameplateCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.nameplateCornerRadius)
                    .strokeBorder(Color.dgInk, lineWidth: DGBorder.strong)
            )
            // 本体の大きさは変えないので、レバーに重ならない大きさで止める
            .dynamicTypeSize(...Self.nameplateMaxTypeSize)
            .accessibilityHidden(true)
    }

    /// 黄色の円に白いバーを入れたレバー（押すと回す）
    private var lever: some View {
        Button(action: onTurnLever) {
            RoundedRectangle(cornerRadius: Self.leverBarSize.height / 2)
                .fill(Color.dgSurfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.leverBarSize.height / 2)
                        .strokeBorder(Color.dgInk, lineWidth: Self.leverBarLineWidth)
                )
                .frame(width: Self.leverBarSize.width, height: Self.leverBarSize.height)
                .rotationEffect(.degrees(pose.leverRotationDegrees))
                .frame(width: Self.leverDiameter, height: Self.leverDiameter)
                .background(Color.dgAccentSecondary, in: Circle())
                .overlay(Circle().strokeBorder(Color.dgInk, lineWidth: DGBorder.machine))
                .contentShape(Circle())
        }
        .buttonStyle(.dgBare)
        .disabled(!isLeverEnabled)
        .accessibilityLabel(Text("レバーを回す"))
    }

    /// 墨色の取り出し口と、出ている当選のカプセル（押せない飾り。何が起きているかは画面の文言と読み上げで伝える）
    private var outlet: some View {
        RoundedRectangle(cornerRadius: DGRadius.md)
            .fill(Color.dgInk)
            .frame(width: Self.outletSize.width, height: Self.outletSize.height)
            .overlay(alignment: .bottom) {
                if let dispensedColor {
                    CapsuleBall(color: dispensedColor, strokeColor: .dgSurfaceCard, lineWidth: Self.dispensedLineWidth)
                        .frame(width: Self.dispensedDiameter, height: Self.dispensedDiameter)
                        .scaleEffect(pose.dispensedScale)
                        .opacity(pose.dispensedOpacity)
                        .offset(y: pose.dispensedOffsetY)
                        .padding(.bottom, Self.outletBottomPadding)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

// MARK: - Preview

/// Preview に並べるカプセルの色（候補の投稿順）
private func previewCapsuleColors(_ count: Int) -> [Color] {
    (0..<count).map { Color.dgCapsule(at: $0) }
}

#Preview("GachaMachine 回せる（カプセル 8 個）") {
    DGGachaMachine(capsuleColors: previewCapsuleColors(8)) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dgBgBase)
}

#Preview("GachaMachine 回せない（カプセル 0 個）") {
    DGGachaMachine(capsuleColors: [], isLeverEnabled: false) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dgBgBase)
}

#Preview("GachaMachine 取り出し（カプセル 60 個）") {
    DGGachaMachine(
        capsuleColors: previewCapsuleColors(60),
        dispensedColor: .dgCapsule(at: 2),
        isLeverEnabled: false
    ) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dgBgBase)
}

#Preview("GachaMachine 動きの途中（Pose）") {
    DGGachaMachine(
        capsuleColors: previewCapsuleColors(12),
        dispensedColor: .dgCapsule(at: 4),
        isLeverEnabled: false,
        pose: DGGachaMachine.Pose(domeRotationDegrees: -4, leverRotationDegrees: 45, dispensedOffsetY: -30, dispensedScale: 1.3)
    ) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dgBgBase)
}

#Preview("GachaMachine 文字を最大") {
    DGGachaMachine(capsuleColors: previewCapsuleColors(8)) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dgBgBase)
        .dynamicTypeSize(.accessibility5)
}
