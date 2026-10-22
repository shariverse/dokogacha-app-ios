//
//  JoinRoomFlowView.swift
//  Dokogacha
//

import SwiftUI

/// 招待コードで参加するシート（03 の §1「S-05・S-06：シート」・§2「S-05 → S-06 →（参加する）→ S-07」）。
///
/// シートの中に `NavigationStack` を持ち、根元に S-05 招待コードで参加、確かめたら上に S-06 参加確認を積む
/// （S-06 の戻るで S-05 に戻ってコードを直せる）。すでにメンバーなら S-06 を出さずに `onJoined` を呼ぶ。
/// 招待リンクで開いたとき（`initialCode`）は、S-05 にコードを入れた状態で始め、画面が出たらすぐに確かめて S-06 を積む
/// （コードが見つからない・満員などのときは、S-05 の入力欄の下にエラーを出す。押したときと同じ扱い）。
/// 参加したら `onJoined` でルームの ID を親（`MainNavigationView`）に渡し、親がシートを閉じてルームを開く。
///
/// トーストの窓口をシートの中で持ち、シートの根元に重ねる（アプリの根元のトーストはシートの後ろに隠れるため）。
struct JoinRoomFlowView: View {
    /// 積んでいる S-06 の行き先
    @State private var path: [JoinConfirmDestination] = []
    @State private var toasts: DGToastCenter
    @State private var codeModel: JoinByCodeModel
    /// 参加を送っている途中なら、端からのスワイプで S-05 に戻らせない
    @State private var navigationLock = NavigationLock()

    /// `previewRoom`・`joinRoom` を呼ぶ窓口
    private let functions: any FunctionsClient
    /// 開いた道（`room_join` の `via`）
    private let via: RoomJoinVia
    /// 参加できたら `room_join` を送る窓口
    private let analytics: any AnalyticsService
    /// 参加した（もとからメンバーだった）ときの処理。値はルームの ID
    private let onJoined: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - functions: `previewRoom`・`joinRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - initialCode: 招待リンクで開いたときの招待コード。S-05 に入れた状態で始め、すぐに確かめて S-06 を積む
    ///   - via: 開いた道（招待リンク・招待コード・前回のメンバーへの招待の通知。`room_join` の `via`）
    ///   - analytics: Analytics のイベント（05 の §9）を送る窓口
    ///   - onJoined: 参加した（もとからメンバーだった）ときの処理。値はルームの ID
    init(
        functions: any FunctionsClient,
        initialCode: InviteCode? = nil,
        via: RoomJoinVia = .code,
        analytics: any AnalyticsService = DisabledAnalyticsService(),
        onJoined: @escaping (String) -> Void
    ) {
        let toasts = DGToastCenter()
        _toasts = State(initialValue: toasts)
        _codeModel = State(initialValue: JoinByCodeModel(functions: functions, toasts: toasts, initialCode: initialCode))
        self.functions = functions
        self.via = via
        self.analytics = analytics
        self.onJoined = onJoined
    }

    var body: some View {
        NavigationStack(path: $path) {
            JoinByCodeView(
                model: codeModel,
                onClose: { dismiss() },
                onOutcome: { outcome in
                    switch outcome {
                    case let .confirm(destination):
                        path.append(destination)
                    case let .openRoom(roomID):
                        onJoined(roomID)
                    }
                }
            )
            .task {
                codeModel.submitInitialCodeIfNeeded()
            }
            // ナビゲーションバーを隠しても、S-06 から端のスワイプで S-05 に戻れるようにする（PR #49 の持ち越し）
            .background(InteractivePopGesture(lock: navigationLock))
            .navigationDestination(for: JoinConfirmDestination.self) { destination in
                JoinConfirmView(
                    model: JoinConfirmModel(destination: destination, functions: functions, toasts: toasts, via: via, analytics: analytics),
                    onCancel: { dismiss() },
                    onJoined: onJoined
                )
            }
        }
        .environment(\.navigationLock, navigationLock)
        .dgToast(toasts)
    }
}

/// シートの右上の閉じるボタン（44×44。アイコンだけなので VoiceOver のラベル「閉じる」を付ける）
struct JoinSheetCloseButton: View {
    /// 閉じるアイコンの大きさ
    private static let iconSize: CGFloat = 20

    /// 押したときの処理
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var iconSize = JoinSheetCloseButton.iconSize

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: iconSize))
                .fontWeight(.bold)
                .foregroundStyle(Color.dgInk)
                .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dgBare)
        .accessibilityLabel(Text("閉じる"))
    }
}

#Preview("招待コードで参加（シート）") {
    Color.dgBgBase
        .sheet(isPresented: .constant(true)) {
            JoinRoomFlowView(functions: InMemoryServer.demo(.joinable)) { _ in }
        }
}
