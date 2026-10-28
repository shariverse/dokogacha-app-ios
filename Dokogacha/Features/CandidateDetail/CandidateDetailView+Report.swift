//
//  CandidateDetailView+Report.swift
//  Dokogacha
//

import SwiftUI

extension ReportReason {
    /// 理由の表示名（02 の §3.5「不適切な内容／スパム／その他」）
    var label: LocalizedStringKey {
        switch self {
        case .inappropriate:
            "不適切な内容"
        case .spam:
            "スパム"
        case .other:
            "その他"
        }
    }
}

extension View {
    /// S-10 の「この投稿を報告」で出す、理由を選ぶダイアログ（F-14）。理由を選ぶと報告を送る（選ぶことを確認とし、取り消しは「キャンセル」）
    func candidateReportDialog(_ model: CandidateDetailModel) -> some View {
        modifier(CandidateReportDialog(model: model))
    }
}

/// 報告の理由を選ぶダイアログ（02 の §3.5「理由（不適切な内容／スパム／その他）を選んで送信」）。
///
/// 削除の確認と同じ `confirmationDialog`（アクションシート）にし、何が起きるか（運営に届く・自分の画面で隠れる）を本文に書く
private struct CandidateReportDialog: ViewModifier {
    @Bindable var model: CandidateDetailModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            Text("この投稿を報告"),
            isPresented: $model.isChoosingReportReason,
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button {
                    model.reportReasonChosen(reason)
                } label: {
                    Text(reason.label)
                }
            }
            Button(role: .cancel) {} label: {
                Text("キャンセル")
            }
        } message: {
            Text("報告の理由を選んでください。運営が内容を確認します。報告すると、あなたの画面ではこの投稿のひとことと参考URLが表示されなくなります。")
        }
    }
}
