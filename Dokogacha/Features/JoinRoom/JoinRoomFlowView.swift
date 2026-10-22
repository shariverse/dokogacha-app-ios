//
//  JoinRoomFlowView.swift
//  Dokogacha
//

import SwiftUI

/// 招待コードで参加するシート（03 の §1「S-05・S-06：シート」・§2「S-05 → S-06 →（参加する）→ S-07」）。
///
/// シートの中に `NavigationStack` を持ち、根元に S-05 招待コードで参加、確かめたら上に S-06 参加確認を積む
/// （S-06 の戻るで S-05 に戻ってコードを直せる）。すでにメンバーなら S-06 を出さずに `onJoined` を呼ぶ。
/// 参加したら `onJoined` でルームの ID を親（`MainNavigationView`）に渡し、親がシートを閉じてルームを開く。
///
/// トーストの窓口をシートの中で持ち、シートの根元に重ねる（アプリの根元のトーストはシートの後ろに隠れるため）。
struct JoinRoomFlowView: View {
    /// 積んでいる S-06 の行き先
    @State private var path: [JoinConfirmDestination] = []
    @State private var toasts: DGToastCenter
    @State private var codeModel: JoinByCodeModel

    /// `previewRoom`・`joinRoom` を呼ぶ窓口
    private let functions: any FunctionsClient
    /// 参加した（もとからメンバーだった）ときの処理。値はルームの ID
    private let onJoined: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - functions: `previewRoom`・`joinRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - onJoined: 参加した（もとからメンバーだった）ときの処理。値はルームの ID
    init(functions: any FunctionsClient, onJoined: @escaping (String) -> Void) {
        let toasts = DGToastCenter()
        _toasts = State(initialValue: toasts)
        _codeModel = State(initialValue: JoinByCodeModel(functions: functions, toasts: toasts))
        self.functions = functions
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
            .navigationDestination(for: JoinConfirmDestination.self) { destination in
                JoinConfirmView(
                    model: JoinConfirmModel(destination: destination, functions: functions, toasts: toasts),
                    onCancel: { dismiss() },
                    onJoined: onJoined
                )
            }
        }
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
