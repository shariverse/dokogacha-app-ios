//
//  ResultCloseSection.swift
//  Dokogacha
//

import SwiftUI

/// S-14 結果の下部に固定する「この行き先で決定」（03 の S-14 の 6・02 の §6.3・§6.5 F-44）。
///
/// - 作成者には DarkButton「この行き先で決定」を出し、確認のダイアログの後に `closeRoom` を呼ぶ。終了できたら、
///   親（`MainNavigationView`）が環境に入れた `roomClosed` でカバーを閉じてホームに戻る（03 の §2「S-14 → この行き先で決定 → S-02」）
/// - 作成者以外には、ボタンの代わりに「作成者が決定するとルームが終了します」を出す
/// - `drawn` のときだけ出す（`RoomClosing.footer`）。`closed`（ホームの思い出のきっぷから開いた閲覧のみ）・
///   引き直しが可決して `unlocked` に戻ったときは何も出さない。きっぷが読めるまでも出さない
///
/// S-14 の上部のヘッダー（戻る・ルーム名）は残す。作成者以外と閲覧のみの画面には、ほかに抜ける操作が無いため
/// （03 の §3「各画面の上部にヘッダー」）。
struct ResultCloseSection: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 「この行き先で決定」
        static let decide = "result.decide"
        /// 「作成者が決定するとルームが終了します」
        static let ownerNote = "result.ownerNote"
    }

    /// 結果の画面の状態（ルームの状態・作成者かを読む）
    let result: ResultModel

    @Environment(\.roomClosed) private var roomClosed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if result.loadState == .loaded, let room = result.room.room {
            switch RoomClosing.footer(for: room, userID: result.room.userID) {
            case .decide:
                decideButton
            case .waitingForOwner:
                ownerNote
            case .hidden:
                EmptyView()
            }
        }
    }

    /// 作成者の「この行き先で決定」（DarkButton。送っている途中は押せない）と確認のダイアログ
    private var decideButton: some View {
        @Bindable var closing = result.closing
        return DGButton("この行き先で決定", kind: .dark) {
            closing.decideTapped()
        }
        .disabled(closing.isClosing)
        .accessibilityIdentifier(Identifier.decide)
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.top, DGSpacing.s10)
        .padding(.bottom, DGSpacing.s16)
        .dgContentColumn()
        .background(Color.dgBgBase)
        .confirmationDialog(
            Text("この行き先で決定しますか？"),
            isPresented: $closing.isConfirming,
            titleVisibility: .visible
        ) {
            Button("決定する") {
                closing.confirmTapped { finish() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ルームが終了し、外れた候補は次のルームで使えるようになります")
        }
    }

    /// 作成者以外への説明（ボタンの代わり）
    private var ownerNote: some View {
        Text("作成者が決定するとルームが終了します")
            .font(.dg(.bodyCaption))
            .foregroundStyle(Color.dgTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.top, DGSpacing.s10)
            .padding(.bottom, DGSpacing.s16)
            .dgContentColumn()
            .background(Color.dgBgBase)
            .accessibilityIdentifier(Identifier.ownerNote)
    }

    /// 終了できたらホームに戻る（親が戻り方を渡していなければ、このカバーを閉じるだけ）
    private func finish() {
        if let handler = roomClosed.handler {
            handler()
        } else {
            dismiss()
        }
    }
}

/// ルームを終了した後の戻り方（`MainNavigationView` がフルスクリーンカバーの中に入れる。カバーを閉じてホームに戻る）。
///
/// 既定（`handler` が nil）は、S-14 を単独で出したとき（撮影モード・プレビュー）で、カバーを閉じるだけにする
nonisolated struct RoomClosedAction: Sendable {
    /// 戻る処理（無ければ既定の戻り方）
    let handler: (@MainActor () -> Void)?
}

extension EnvironmentValues {
    /// ルームを終了した後の戻り方
    @Entry var roomClosed = RoomClosedAction(handler: nil)
}
