//
//  LicensesView.swift
//  Dokogacha
//

import SwiftUI

/// S-15 の「ライセンス」から積む画面。同梱のフォント（OFL）と、アプリに入るライブラリと、同梱のデータ（市区町村の一覧）を並べ、
/// 押すとライセンスの全文（データは出典と利用条件）を出す（`LicenseDetailView`）。
///
/// 03 の S-15「ライセンス（フォントの OFL 表記を含む）」・04 の §2・06 の §5「フォントの OFL ライセンス表記」。
/// 設定と同じく、標準のナビゲーションバーは使わず画面のヘッダー（`DGHeader`）を置く
struct LicensesView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// ライセンスの画面
        static let screen = "licenses.screen"

        /// 1 行（`LicenseEntry.id` ごと）
        static func row(_ id: String) -> String {
            "licenses.row.\(id)"
        }
    }

    /// 全文を出しているもの
    @State private var selected: LicenseEntry?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text("ライセンス"), onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpacing.s16) {
                    section(Text("フォント"), entries: LicenseCatalog.fonts)
                    section(Text("ライブラリ"), entries: LicenseCatalog.libraries)
                    section(Text("データ"), entries: LicenseCatalog.data)
                }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.top, DGSpacing.s8)
                .padding(.bottom, DGSpacing.s24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .navigationDestination(item: $selected) { entry in
            LicenseDetailView(entry: entry)
        }
    }

    /// 見出しと行のまとまり
    private func section(_ title: Text, entries: [LicenseEntry]) -> some View {
        VStack(alignment: .leading, spacing: DGSpacing.s8) {
            title
                .font(.dg(.displaySection))
                .foregroundStyle(Color.dgInk)
                .accessibilityAddTraits(.isHeader)
            SettingsSection {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        DGDashedLine()
                    }
                    Button {
                        selected = entry
                    } label: {
                        SettingsRow(title: Text(verbatim: entry.name), value: Text(verbatim: entry.kind.title), accessory: .disclosure)
                    }
                    .buttonStyle(.dgBare)
                    .accessibilityIdentifier(Identifier.row(entry.id))
                }
            }
        }
    }
}

/// ライセンスの全文の画面（名前・著作権の表示・ライセンスの全文）
struct LicenseDetailView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 全文の画面
        static let screen = "licenses.detail"
        /// 全文（段落を並べたまとまり）
        static let text = "licenses.detail.text"
    }

    /// 出すもの
    let entry: LicenseEntry

    @Environment(\.dismiss) private var dismiss

    /// 全文の段落
    private var paragraphs: [String] {
        LicenseCatalog.paragraphs(of: LicenseCatalog.text(of: entry) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text(verbatim: entry.name), onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: DGSpacing.s12) {
                    Text(verbatim: entry.notice)
                        .font(.dg(.bodyTitle))
                        .foregroundStyle(Color.dgInk)
                    Text(verbatim: entry.kind.title)
                        .font(.dg(.bodyRegular))
                        .foregroundStyle(Color.dgTextSecondary)
                    DGDashedLine()
                    // 段落ごとに分けて出す（文字を大きくしても画面の幅で折り返し、VoiceOver では段落ごとに読める）
                    VStack(alignment: .leading, spacing: DGSpacing.s10) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(verbatim: paragraph)
                                .font(.dg(.bodyCaption))
                                .foregroundStyle(Color.dgTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(Identifier.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DGSpacing.cardPadding)
                .background(Color.dgSurfaceCard, in: RoundedRectangle(cornerRadius: DGRadius.lg))
                .overlay { RoundedRectangle(cornerRadius: DGRadius.lg).strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
                .padding(.horizontal, DGSpacing.screenX)
                .padding(.top, DGSpacing.s8)
                .padding(.bottom, DGSpacing.s24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
    }
}

#Preview("ライセンス") {
    NavigationStack {
        LicensesView()
    }
}

#Preview("ライセンスの全文") {
    NavigationStack {
        LicenseDetailView(entry: LicenseCatalog.fonts[0])
    }
}
