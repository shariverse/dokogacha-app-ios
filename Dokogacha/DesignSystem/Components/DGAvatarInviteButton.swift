//
//  DGAvatarInviteButton.swift
//  Dokogacha
//
//  アバターの並びの末尾に置く、メンバーを招待するボタン（S-07 のルームパネル）。
//

import SwiftUI

/// アバター（`DGAvatar` の `.large`）と同じ 44 の円に「＋」を描いた、メンバーを招待するボタン。
///
/// 円の下に、アバターの名前と同じ大きさで「招待」と出す。アバターの列（円＋名前）と高さがそろい、並べたときに段が崩れない。
/// 幅は置く側が列の幅で決める（この部品は渡された幅いっぱいに広がり、円と文字を真ん中に置く）。押せる範囲は円と文字を合わせた列全体。
///
/// - 押せる（`available`）: 縁は 04 の DashedButton と同じ 2pt の ink の点線（円周で割り切れる刻みにし、継ぎ目を作らない）。
///   押している間は円を `surface.muted` で塗って縮め（「視差効果を減らす」では縮めない）、押したら軽い触覚を返す
/// - 満員（`full`）: 押せない。円を無効の色（`surface.disabled`）で塗って縁を消し、下に「満員」と出す。
///   `Button` にはせず、VoiceOver では「満員のため招待できません」と読む（無効の `Button` は「淡色表示、ボタン」と読まれ、
///   押せるはずの操作が押せないように聞こえるため。`DGButtonShapedStatus` と同じ考え）
struct DGAvatarInviteButton: View {
    /// 押せるか
    nonisolated enum Status: Sendable {
        /// 招待できる
        case available
        /// 満員で招待できない
        case full
    }

    /// 円の直径（ルームパネルのアバターと同じ 44）
    static let diameter = DGAvatar.Size.large.diameter

    /// いまの状態
    let status: Status
    /// 押したときの処理（招待の画面を開く）
    let action: () -> Void

    /// 押した回数（触覚を鳴らす合図）
    @State private var feedbackTrigger = 0

    var body: some View {
        switch status {
        case .available:
            Button {
                feedbackTrigger += 1
                action()
            } label: {
                Text("招待")
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
            .accessibilityLabel(Text("メンバーを招待"))
            .accessibilityHint(Text("招待コードと招待リンクを出します"))
        case .full:
            DGAvatarInviteFace(status: .full, isPressed: false, title: Text("満員"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("満員のため招待できません"))
        }
    }

    /// 押している間の見た目を `DGAvatarInviteFace` に渡すスタイル
    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            DGAvatarInviteFace(status: .available, isPressed: configuration.isPressed, title: configuration.label)
        }
    }
}

/// `DGAvatarInviteButton` の見た目（円と下の文字）。「視差効果を減らす」を環境から読むため、ビューに分けている
private struct DGAvatarInviteFace<Title: View>: View {
    /// 円の中の「＋」の一辺（04 の DashedButton のアイコン）
    private static var iconSize: CGFloat { DGButtonKind.dashed.iconSize }
    /// 下の文字の大きさ（S-07 のアバターの名前「11pt」と同じ）
    private static var titleSize: CGFloat { 11 }
    /// 下の文字を列の幅に収めるときに縮める下限（S-07 のアバターの名前と同じ）
    private static var titleMinimumScale: CGFloat { 0.7 }
    /// 押している間の縮み（円が小さいので、ボタンの 0.97 より大きく縮めて押したことを見せる）
    private static var pressedScale: CGFloat { 0.9 }
    /// 点線の 1 刻み（線と隙間）のおおよその長さ（DashedButton の `[6, 4]`）
    private static var dashUnit: CGFloat { 10 }
    /// 1 刻みのうち線の割合（DashedButton の 6:4）
    private static var dashRatio: CGFloat { 0.6 }

    let status: DGAvatarInviteButton.Status
    let isPressed: Bool
    let title: Title

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DGSpacing.s4) {
            circle
            title
                .font(.dgBody(Self.titleSize, weight: .black, relativeTo: .caption2))
                .foregroundStyle(status == .available ? Color.dgInk : Color.dgTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(Self.titleMinimumScale)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    /// 44 の円と「＋」
    private var circle: some View {
        let diameter = DGAvatarInviteButton.diameter
        return Image("ui-plus")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: Self.iconSize, height: Self.iconSize)
            .foregroundStyle(status == .available ? Color.dgInk : Color.dgTextDisabled)
            .frame(width: diameter, height: diameter)
            .background(fill, in: Circle())
            .overlay {
                if status == .available {
                    Circle().strokeBorder(Color.dgInk, style: StrokeStyle(lineWidth: DGBorder.regular, dash: Self.dash(diameter: diameter)))
                }
            }
            .scaleEffect(isPressed && !reduceMotion ? Self.pressedScale : 1)
            .animation(reduceMotion ? nil : DGMotion.press.animation, value: isPressed)
    }

    /// 円の塗り（押している間は `surface.muted`、満員は無効の色）
    private var fill: Color {
        switch status {
        case .available: isPressed ? Color.dgSurfaceMuted : Color.dgSurfaceCard
        case .full: Color.dgSurfaceDisabled
        }
    }

    /// 点線の線と隙間。円周を刻みの数で割り切り、始まりと終わりで線がつながったり隙間が詰まったりしないようにする
    /// - Parameter diameter: 円の直径（縁は内側に描くので、線の中心の円周は縁の太さの分だけ短い）
    private static func dash(diameter: CGFloat) -> [CGFloat] {
        let circumference = CGFloat.pi * (diameter - DGBorder.regular)
        let unit = circumference / max((circumference / dashUnit).rounded(), 1)
        return [unit * dashRatio, unit * (1 - dashRatio)]
    }
}

#Preview("AvatarInviteButton 状態ごと") {
    VStack(alignment: .leading, spacing: DGSpacing.s16) {
        HStack(alignment: .top, spacing: DGSpacing.s8) {
            ForEach(Array(["ゆい", "けんた", "みさき"].enumerated()), id: \.offset) { index, name in
                VStack(spacing: DGSpacing.s4) {
                    DGAvatar(name: name, color: .dgAvatar(at: index), readiness: index == 0 ? .ready : .notReady)
                    Text(verbatim: name)
                        .font(.dgBody(11, relativeTo: .caption2))
                        .foregroundStyle(Color.dgTextSecondary)
                }
                .frame(width: 56)
            }
            DGAvatarInviteButton(status: .available) {}
                .frame(width: 56)
        }
        HStack(alignment: .top, spacing: DGSpacing.s8) {
            DGAvatarInviteButton(status: .available) {}
                .frame(width: 56)
            DGAvatarInviteButton(status: .full) {}
                .frame(width: 56)
        }
    }
    .padding(DGSpacing.s16)
    .background(Color.dgSurfaceCard)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("AvatarInviteButton 文字を最大") {
    HStack(alignment: .top, spacing: DGSpacing.s8) {
        DGAvatarInviteButton(status: .available) {}
            .frame(width: 120)
        DGAvatarInviteButton(status: .full) {}
            .frame(width: 120)
    }
    .padding(DGSpacing.s16)
    .background(Color.dgSurfaceCard)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
