//
//  SafariView.swift
//  Dokogacha
//

import SafariServices
import SwiftUI

/// アプリの中の Safari（`SFSafariViewController`）。S-15 の利用規約・プライバシーポリシーを開く。
///
/// アプリから離れずに読めて、閉じると設定に戻る（`openURL` で Safari に切り替えると、戻るのに左上の「◀︎ ドコガチャ」を押す必要がある）
struct SafariView: UIViewControllerRepresentable {
    /// 開くページ
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
