//
//  DGButton.swift
//  Dokogacha
//
//  ボタンの部品（`04_design_system.md` の §4 の Button）。
//  見た目は `DGButtonStyle`（`.buttonStyle(.dg(.primary))`）にまとめ、アイコン付きのボタンは `DGButton` で作る。
//

import SwiftUI

/// ボタンの種類（04 の §4 の Button の表）。
///
/// 表で幅のある値（「48〜52」など）は、使う画面の多いほうに決めてある。
/// 黄色のボタンはタップ領域を 44 以上にするため、高さを 44 にする（表は「40〜44」）。
nonisolated enum DGButtonKind: CaseIterable, Sendable {
    /// 主ボタン（朱色・太い縁・ハードシャドウ）。「ルームを作成」「はじめる」など
    case primary
    /// 副ボタン（白・縁）。「招待コードで参加」など
    case secondary
    /// 黄色のボタン。「準備OK」「候補を追加」など
    case yellow
    /// 墨色のボタン。「ルームへ進む」「この行き先で決定」など
    case dark
    /// 点線のボタン。「引き直しを提案」など
    case dashed

    /// 最小の高さ（Dynamic Type で文字が大きくなったら伸びる）
    var height: CGFloat {
        switch self {
        case .primary: 56
        case .secondary: 48
        case .yellow: 44
        case .dark: 52
        case .dashed: 48
        }
    }

    /// 角丸の半径
    var cornerRadius: CGFloat {
        switch self {
        case .primary: 18
        case .secondary, .dark, .dashed: DGRadius.md
        case .yellow: 14
        }
    }

    /// 背景色（有効なとき）
    var background: Color {
        switch self {
        case .primary: .dgAccentPrimary
        case .secondary: .dgSurfaceCard
        case .yellow: .dgAccentSecondary
        case .dark: .dgInk
        case .dashed: .clear
        }
    }

    /// 文字とアイコンの色（有効なとき）
    var foreground: Color {
        switch self {
        case .primary, .dark: .dgTextOnAccent
        case .secondary, .yellow, .dashed: .dgInk
        }
    }

    /// 文字の大きさ（本文 Black。`body.button` の幅 15〜17 と表の値）
    var fontSize: CGFloat {
        switch self {
        case .primary: 17
        case .secondary: 15
        case .yellow, .dashed: 14
        case .dark: 16
        }
    }

    /// アイコンの一辺（プロトタイプの値）
    var iconSize: CGFloat {
        switch self {
        case .primary: 20
        case .secondary, .dark, .dashed: 18
        case .yellow: 16
        }
    }

    /// 縁の太さ。縁が無い種類は 0
    var borderWidth: CGFloat {
        switch self {
        case .primary: DGBorder.strong
        case .secondary, .yellow, .dashed: DGBorder.regular
        case .dark: 0
        }
    }

    /// 縁を点線で描くか
    var isDashed: Bool {
        self == .dashed
    }

    /// 有効なときの影。影の無い種類は `nil`
    var shadow: DGShadow? {
        self == .primary ? .hard : nil
    }

    /// 既定で横幅いっぱいに広げるか（黄色のボタンは中身の幅）
    var fillsWidthByDefault: Bool {
        self != .yellow
    }
}

/// 04 の §4 の Button の見た目を付けるボタンのスタイル。
///
/// 無効（`.disabled(true)`）のときは種類によらず `surface.disabled` の背景・`text.disabled` の文字・背景と同じ色の縁にし、影を消す。
/// 押している間は 0.97 倍に縮め、影を y 1 に縮める（0.1 秒）。「視差効果を減らす」がオンのときは縮めず、影だけを即時に変える。
struct DGButtonStyle: ButtonStyle {
    /// ボタンの種類
    var kind: DGButtonKind
    /// 横幅いっぱいに広げるか。`nil` なら種類の既定（`DGButtonKind.fillsWidthByDefault`）
    var fillsWidth: Bool?

    func makeBody(configuration: Configuration) -> some View {
        DGButtonBody(
            kind: kind,
            fillsWidth: fillsWidth ?? kind.fillsWidthByDefault,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}

extension ButtonStyle where Self == DGButtonStyle {
    /// ドコガチャのボタンのスタイル（`.buttonStyle(.dg(.primary))` のように使う）。
    /// - Parameters:
    ///   - kind: ボタンの種類
    ///   - fillsWidth: 横幅いっぱいに広げるか。`nil` なら種類の既定
    static func dg(_ kind: DGButtonKind, fillsWidth: Bool? = nil) -> DGButtonStyle {
        DGButtonStyle(kind: kind, fillsWidth: fillsWidth)
    }
}

/// `DGButtonStyle` の中身。`isEnabled` と「視差効果を減らす」を環境から読むため、ビューに分けている。
private struct DGButtonBody<Label: View>: View {
    /// 押している間の縮み（04 の §4）
    private static var pressedScale: CGFloat { 0.97 }
    /// 点線の線と隙間の長さ（CSS の `dashed` の見た目に合わせる）
    private static var dashPattern: [CGFloat] { [6, 4] }

    let kind: DGButtonKind
    let fillsWidth: Bool
    let isPressed: Bool
    let label: Label

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: kind.cornerRadius)
        label
            .font(.dgBody(kind.fontSize, weight: .black, relativeTo: .body))
            .foregroundStyle(isEnabled ? kind.foreground : Color.dgTextDisabled)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DGSpacing.s16)
            .padding(.vertical, DGSpacing.s8)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: kind.height)
            .background(isEnabled ? kind.background : Color.dgSurfaceDisabled, in: shape)
            .overlay { border(shape) }
            .contentShape(shape)
            .modifier(OptionalHardShadow(shadow: currentShadow, cornerRadius: kind.cornerRadius))
            .scaleEffect(isPressed && !reduceMotion ? Self.pressedScale : 1)
            .animation(reduceMotion ? nil : DGMotion.press.animation, value: isPressed)
    }

    /// いまの状態の影（無効なときと、影の無い種類は `nil`）
    private var currentShadow: DGShadow? {
        guard isEnabled, kind.shadow != nil else {
            return nil
        }
        return isPressed ? .pressed : kind.shadow
    }

    /// 縁。無効なときは背景と同じ色で描く（04 の §4 の「無効状態」）
    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        let color = isEnabled ? Color.dgInk : Color.dgSurfaceDisabled
        if kind.isDashed {
            shape.strokeBorder(color, style: StrokeStyle(lineWidth: kind.borderWidth, dash: Self.dashPattern))
        } else if kind.borderWidth > 0 {
            shape.strokeBorder(color, lineWidth: kind.borderWidth)
        }
    }
}

/// 影があるときだけ `HardShadow` を付ける。
private struct OptionalHardShadow: ViewModifier {
    let shadow: DGShadow?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let shadow {
            content.dgHardShadow(shadow, cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}

/// 見た目を部品の側で描くボタンのスタイル（TabSwitch・SegmentedChoice・Stepper・PlaceRow のボタン）。
///
/// `.plain` は無効のときにシステムが全体を薄くし、04 の無効の色（`surface.disabled`・`text.disabled`）や墨色の縁が変わってしまうので使わない。
/// 押している間だけ少し薄くして、押したことを示す。
struct DGBareButtonStyle: ButtonStyle {
    /// 押している間の不透明度
    private static let pressedOpacity: Double = 0.7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == DGBareButtonStyle {
    /// 見た目を部品の側で描くボタンのスタイル（`DGBareButtonStyle`）
    static var dgBare: DGBareButtonStyle {
        DGBareButtonStyle()
    }
}

/// 文言と、必要ならアイコンを並べたボタン（`DGButtonStyle` を付けたもの）。
///
/// アイコンは文言の飾りなので VoiceOver では読まない（ボタンの名前は文言になる）。
struct DGButton: View {
    /// ボタンの文言（03 の表記）
    let title: LocalizedStringKey
    /// 文言の前に置くアイコンのアセット名（`ui-plus` など）。無ければ `nil`
    let icon: String?
    /// ボタンの種類
    let kind: DGButtonKind
    /// 横幅いっぱいに広げるか。`nil` なら種類の既定
    let fillsWidth: Bool?
    /// 押したときの処理
    let action: () -> Void

    /// アイコンを Dynamic Type に合わせて大きくする倍率
    @ScaledMetric(relativeTo: .body) private var iconScale: CGFloat = 1

    /// - Parameters:
    ///   - title: ボタンの文言
    ///   - icon: 文言の前に置くアイコンのアセット名
    ///   - kind: ボタンの種類（既定は主ボタン）
    ///   - fillsWidth: 横幅いっぱいに広げるか。`nil` なら種類の既定
    ///   - action: 押したときの処理
    init(
        _ title: LocalizedStringKey,
        icon: String? = nil,
        kind: DGButtonKind = .primary,
        fillsWidth: Bool? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: kind == .primary ? DGSpacing.s8 : DGSpacing.s6) {
                if let icon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: kind.iconSize * iconScale, height: kind.iconSize * iconScale)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(.dg(kind, fillsWidth: fillsWidth))
    }
}

#Preview("Button 有効") {
    VStack(spacing: DGSpacing.s16) {
        DGButton("ルームを作る", icon: "ui-plus") {}
        DGButton("招待コードで参加", kind: .secondary) {}
        DGButton("候補を追加", icon: "ui-plus", kind: .yellow) {}
        DGButton("ルームへ進む", kind: .dark) {}
        DGButton("引き直しを提案（過半数の賛成で1回まで）", kind: .dashed) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("Button 無効") {
    VStack(spacing: DGSpacing.s16) {
        ForEach(DGButtonKind.allCases, id: \.self) { kind in
            DGButton("準備OKが揃うと回せます", kind: kind) {}
                .disabled(true)
        }
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("Button 文字を最大") {
    VStack(spacing: DGSpacing.s16) {
        DGButton("ルームを作る", icon: "ui-plus") {}
        DGButton("招待コードで参加", kind: .secondary) {}
        DGButton("準備OK", kind: .yellow) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
