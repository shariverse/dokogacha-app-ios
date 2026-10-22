//
//  SettingsRow.swift
//  Dokogacha
//

import SwiftUI

/// S-15 設定の 1 行（項目名・値・右端の印）。白いカード（`SettingsSection`）の中に縦に並べる。
///
/// 文字を大きくして項目名と値が折り返さずに 1 行に収まらないときは、項目名の下に値と印を並べる（どちらも切らない）。
/// 押せる行は `Button` の中に入れて使い、VoiceOver では項目名と値を 1 つの要素として読む。
struct SettingsRow: View {
    /// 右端の印
    enum Accessory: Equatable {
        /// 印なし（バージョンなど、見るだけの行）
        case none
        /// 押すと先へ進む（シェブロン）
        case disclosure
        /// まだ作っていない（「準備中」。押しても何もしない）
        case pending
    }

    /// 項目名
    let title: Text
    /// 値（今の表示名・バージョンなど）。無ければ nil
    var value: Text?
    /// 右端の印
    var accessory: Accessory = .none
    /// 赤文字にするか（「アカウントを削除」。03 の S-15）
    var isDestructive = false

    /// シェブロンの大きさ
    private static let chevronSize: CGFloat = 14

    @ScaledMetric(relativeTo: .body) private var chevronSize = SettingsRow.chevronSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // 1 行の並びは、項目名も値も折り返さずに収まるときだけ使う（折り返すなら縦に並べる）
            HStack(spacing: DGSpacing.s8) {
                titleText
                    .fixedSize()
                Spacer(minLength: DGSpacing.s8)
                trailing
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                titleText
                trailing
            }
        }
        .padding(.horizontal, DGSpacing.cardPadding)
        .padding(.vertical, DGSpacing.s12)
        .frame(maxWidth: .infinity, minHeight: DGMetrics.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleText: some View {
        title
            .font(.dg(.bodyTitle))
            .foregroundStyle(isDestructive ? Color.dgAccentText : Color.dgInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 値と右端の印
    private var trailing: some View {
        HStack(spacing: DGSpacing.s6) {
            if let value {
                value
                    .font(.dg(.bodyRegular))
                    .foregroundStyle(Color.dgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch accessory {
            case .none:
                EmptyView()
            case .disclosure:
                Image(systemName: "chevron.right")
                    .font(.system(size: chevronSize))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.dgTextSecondary)
                    .accessibilityHidden(true)
            case .pending:
                Text("準備中")
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
            }
        }
    }
}

/// S-15 設定の項目のまとまり（白いカードに行を区切り線で並べる）。
struct SettingsSection<Content: View>: View {
    /// 行（`SettingsRow`。間に `DGDashedLine` を挟む）
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        VStack(spacing: 0) {
            content
        }
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
        .clipShape(shape)
    }
}

#Preview("設定の行") {
    VStack(spacing: DGSpacing.s16) {
        SettingsSection {
            SettingsRow(title: Text("表示名"), value: Text(verbatim: "たくみ"), accessory: .disclosure)
            DGDashedLine()
            SettingsRow(title: Text("購入を復元"), accessory: .pending)
            DGDashedLine()
            SettingsRow(title: Text("バージョン"), value: Text(verbatim: "1.0"))
        }
        SettingsSection {
            SettingsRow(title: Text("アカウントを削除"), accessory: .pending, isDestructive: true)
        }
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}
