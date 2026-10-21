//
//  PendingScreenView.swift
//  Dokogacha
//

import SwiftUI

/// まだ作っていない画面の仮の画面（ホームからの行き先の口だけを先に通すため）。
///
/// ヘッダー（プッシュなら戻る、シートなら閉じる）と「この画面は準備中です」だけを出す。
/// 各画面のタスク（S-03・S-05: タスク 14・15、S-07: タスク 19、S-15: タスク 16）で、`MainNavigationView` の行き先を本物の画面に差し替えて消す。
struct PendingScreenView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 仮の画面
        static func screen(_ route: AppRoute) -> String {
            switch route {
            case .createRoom: "pending.createRoom"
            case .joinByCode: "pending.joinByCode"
            case .room: "pending.room"
            case .settings: "pending.settings"
            }
        }
    }

    /// 閉じるアイコンの大きさ
    private static let closeIconSize: CGFloat = 20

    /// 開いた行き先
    let route: AppRoute

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var closeIconSize = PendingScreenView.closeIconSize

    var body: some View {
        VStack(alignment: .leading, spacing: DGSpacing.s16) {
            header
            Text("この画面は準備中です")
                .font(.dg(.bodyRegular))
                .foregroundStyle(Color.dgTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DGSpacing.screenX)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen(route))
    }

    /// プッシュは戻るボタン、シートは右端の閉じるボタン
    @ViewBuilder private var header: some View {
        switch route.presentation {
        case .push:
            DGHeader(title, onBack: { dismiss() })
        case .sheet:
            DGHeader(title, onBack: nil) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: closeIconSize))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.dgInk)
                        .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dgBare)
                .accessibilityLabel(Text("閉じる"))
            }
            .padding(.leading, DGSpacing.s12)
        }
    }

    /// 画面のタイトル（03 の表記）
    private var title: Text {
        switch route {
        case .createRoom: Text("ルームを作る")
        case .joinByCode: Text("招待コードで参加")
        case .room: Text("ルーム")
        case .settings: Text("設定")
        }
    }
}

#Preview("仮の画面") {
    PendingScreenView(route: .createRoom)
}
