//
//  DGAvatar.swift
//  Dokogacha
//
//  メンバーのアバター（`04_design_system.md` の §4 の Avatar）。
//

import SwiftUI

/// 表示名の 1 文字目を、割り当てた色の円に白文字で出すアバター（02 の F-01）。
///
/// 円の大きさは置き場所で決まっていて（ルームパネル 44・ホーム 28・LikeRow 26）、並べたときに崩れないよう Dynamic Type では変えない。
/// 文字は Dynamic Type に追従させたうえで、円に収まるように縮める（VoiceOver では表示名を読む）。
struct DGAvatar: View {
    /// アバターの大きさ（置き場所ごと）
    nonisolated enum Size: CaseIterable, Sendable {
        /// ルームパネル（44）。準備OKのバッジを付けられる
        case large
        /// ホームの RoomTagCard（28）
        case medium
        /// 候補カードの LikeRow（26）
        case small

        /// 円の直径
        var diameter: CGFloat {
            switch self {
            case .large: 44
            case .medium: 28
            case .small: 26
            }
        }

        /// 準備OKのバッジを付ける大きさか（バッジはルームパネルにだけ出す）
        var showsReadyBadge: Bool {
            self == .large
        }
    }

    /// 準備OKの状態。
    nonisolated enum Readiness: Sendable {
        /// 準備OKを表さない（LikeRow など）。割り当てた色で塗る
        case unspecified
        /// まだ準備OKでない。`avatarNotReady` の色で塗る
        case notReady
        /// 準備OK。割り当てた色で塗り、ルームパネルではチェックのバッジを付ける
        case ready
    }

    /// 文字の大きさの、直径に対する割合（04 の §4「サイズの約0.36倍」）
    private static let initialRatio: CGFloat = 0.36
    /// 文字が円に収まらないときに縮める下限
    private static let minimumScale: CGFloat = 0.5
    /// 準備OKのバッジの直径
    private static let badgeDiameter: CGFloat = 20
    /// バッジのチェックの一辺
    private static let badgeIconSize: CGFloat = 12
    /// バッジを右下にはみ出させる量（04 の §4「右下に −3 ずらす」）
    private static let badgeOverhang: CGFloat = 3

    /// メンバーの表示名（1 文字目を出し、VoiceOver では全体を読む）
    let name: String
    /// 割り当てた色（`Color.dgAvatars` のどれか）
    let color: Color
    /// 大きさ
    var size: Size = .large
    /// 準備OKの状態
    var readiness: Readiness = .unspecified
    /// 円の外側の縁の色。重ねて並べるとき（LikeRow）に、下地と同じ色の縁で区切る。縁が要らなければ `nil`
    var ringColor: Color?

    var body: some View {
        Text(verbatim: DGAvatarInitial.make(from: name))
            .font(.dgBody(size.diameter * Self.initialRatio, weight: .black, relativeTo: .caption))
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
            .foregroundStyle(readiness == .notReady ? Color.dgAvatarNotReadyFg : Color.dgTextOnAccent)
            .padding(DGSpacing.s4)
            .frame(width: size.diameter, height: size.diameter)
            .background(readiness == .notReady ? Color.dgAvatarNotReadyBg : color, in: Circle())
            .overlay {
                if let ringColor {
                    Circle().strokeBorder(ringColor, lineWidth: DGBorder.regular)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if readiness == .ready, size.showsReadyBadge {
                    readyBadge
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityValue(accessibilityValue)
    }

    /// 準備OKのバッジ（黄色の円・白い縁・チェック）
    private var readyBadge: some View {
        Image("ui-check")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: Self.badgeIconSize, height: Self.badgeIconSize)
            .foregroundStyle(Color.dgInk)
            .frame(width: Self.badgeDiameter, height: Self.badgeDiameter)
            .background(Color.dgAccentSecondary, in: Circle())
            .overlay(Circle().strokeBorder(Color.dgSurfaceCard, lineWidth: DGBorder.regular))
            .offset(x: Self.badgeOverhang, y: Self.badgeOverhang)
    }

    /// VoiceOver で読む準備OKの状態
    private var accessibilityValue: Text {
        switch readiness {
        case .unspecified: Text(verbatim: "")
        case .notReady: Text("未準備")
        case .ready: Text("準備OK")
        }
    }
}

/// アバターに出す 1 文字を決める（02 の F-01「アバターは表示名の1文字目」）。
nonisolated enum DGAvatarInitial {
    /// 表示名からアバターに出す 1 文字を返す。
    ///
    /// 前後の空白を除いた 1 文字目（書記素。絵文字の合成や濁点の結合文字も 1 文字として扱う）を、英字なら大文字にして返す。
    /// 空白だけ・空のときは空文字を返す（表示名は 1〜10 文字の必須なので、通常は起きない）。
    /// - Parameter name: メンバーの表示名
    static func make(from name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return ""
        }
        return String(first).uppercased()
    }
}

#Preview("Avatar 大きさと状態") {
    VStack(spacing: DGSpacing.s16) {
        HStack(spacing: DGSpacing.s8) {
            DGAvatar(name: "ゆい", color: .dgAvatar(at: 0), readiness: .ready)
            DGAvatar(name: "けんた", color: .dgAvatar(at: 1), readiness: .ready)
            DGAvatar(name: "みさき", color: .dgAvatar(at: 2), readiness: .notReady)
            DGAvatar(name: "Sora", color: .dgAvatar(at: 3), readiness: .notReady)
        }
        HStack(spacing: DGSpacing.s4) {
            ForEach(0..<5) { index in
                DGAvatar(name: "ゆい", color: .dgAvatar(at: index), size: .medium, readiness: index < 3 ? .ready : .notReady)
            }
        }
        HStack(spacing: -DGSpacing.s6) {
            ForEach(0..<3) { index in
                DGAvatar(name: "みさき", color: .dgAvatar(at: index + 4), size: .small, ringColor: .dgSurfaceCard)
            }
        }
        .padding(DGSpacing.s12)
        .background(Color.dgSurfaceCard)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("Avatar 文字を最大") {
    HStack(spacing: DGSpacing.s8) {
        DGAvatar(name: "ゆい", color: .dgAvatar(at: 0), readiness: .ready)
        DGAvatar(name: "けんた", color: .dgAvatar(at: 1), size: .medium)
        DGAvatar(name: "みさき", color: .dgAvatar(at: 2), size: .small)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
