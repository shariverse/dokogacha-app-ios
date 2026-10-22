//
//  PendingScreenView.swift
//  Dokogacha
//

import SwiftUI

/// まだ作っていない画面の仮の画面（ホームからの行き先の口だけを先に通すため）。
///
/// ヘッダー（プッシュなら戻る、シート・フルスクリーンカバーなら閉じる）と「この画面は準備中です」だけを出す。
/// 各画面のタスク（S-08: タスク 20、S-10: タスク 21、S-11・S-12: タスク 25、S-13: タスク 27）で、
/// `MainNavigationView` の行き先を本物の画面に差し替える。
struct PendingScreenView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 仮の画面
        static func screen(_ route: AppRoute) -> String {
            switch route {
            case .createRoom: "pending.createRoom"
            case .invite: "pending.invite"
            case .joinByCode: "pending.joinByCode"
            case .room: "pending.room"
            case .settings: "pending.settings"
            case .addCandidate: "pending.addCandidate"
            case .candidateDetail: "pending.candidateDetail"
            case .members: "pending.members"
            case .roomSettings: "pending.roomSettings"
            case .gacha: "pending.gacha"
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

    /// プッシュは戻るボタン、シート・フルスクリーンカバーは右端の閉じるボタン
    @ViewBuilder private var header: some View {
        switch route.presentation {
        case .push:
            DGHeader(title, onBack: { dismiss() })
        case .sheet, .fullScreenCover:
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
        case .invite: Text("招待")
        case .joinByCode: Text("招待コードで参加")
        case .room: Text("ルーム")
        case .settings: Text("設定")
        case .addCandidate: Text("行きたい場所を追加")
        case .candidateDetail: Text("候補の詳細")
        case .members: Text("メンバー")
        case .roomSettings: Text("ルーム設定")
        case .gacha: Text("ガチャ")
        }
    }
}

#Preview("仮の画面") {
    PendingScreenView(route: .createRoom)
}
