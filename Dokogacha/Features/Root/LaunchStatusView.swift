//
//  LaunchStatusView.swift
//  Dokogacha
//

import SwiftUI

/// 起動中（サインイン・プロフィールの読み込み）と、起動に失敗したときの画面。
///
/// ロゴの下に、読み込み中の印か、失敗の文言を出す。失敗が再試行できるときは「もう一度試す」を置く。
/// 03 の §3 の `redacted` は形の決まった部品の読み込みに使うもので、ここは出す画面（S-01 かホーム）がまだ決まっていないので使わない。
struct LaunchStatusView: View {
    /// 出す状態
    enum Status: Equatable {
        /// サインイン中・プロフィールの読み込み中
        case loading
        /// サーバーに接続できない（再試行しても変わらない）
        case serverUnavailable
        /// サインイン・読み込みに失敗した（値は文言）
        case failed(message: String)
    }

    /// UI テストが探す ID
    enum Identifier {
        /// 「もう一度試す」
        static let retry = "launch.retry"
        /// 失敗の文言
        static let message = "launch.message"
    }

    /// 出す状態
    let status: Status
    /// 「もう一度試す」を押したときの処理。nil ならボタンを出さない
    var onRetry: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DGSpacing.s24) {
                DGLogo()
                statusContent
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.vertical, DGSpacing.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.dgBgBase.ignoresSafeArea())
    }

    @ViewBuilder private var statusContent: some View {
        switch status {
        case .loading:
            ProgressView()
                .tint(Color.dgInk)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("読み込み中"))
        case .serverUnavailable:
            message(Text("サーバーに接続できません"))
        case let .failed(text):
            VStack(alignment: .leading, spacing: DGSpacing.s16) {
                message(Text(verbatim: text))
                if let onRetry {
                    DGButton("もう一度試す", kind: .secondary, action: onRetry)
                        .accessibilityIdentifier(Identifier.retry)
                }
            }
        }
    }

    /// 失敗の文言（本文 Black 16）
    private func message(_ text: Text) -> some View {
        text
            .font(.dg(.bodyTitle))
            .foregroundStyle(Color.dgInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Identifier.message)
    }
}

#Preview("起動中") {
    LaunchStatusView(status: .loading)
}

#Preview("失敗") {
    LaunchStatusView(status: .failed(message: AppError(.network).message)) {}
}

#Preview("接続できない") {
    LaunchStatusView(status: .serverUnavailable)
}
