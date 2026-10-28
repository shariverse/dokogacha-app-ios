//
//  ActivityShareSheet.swift
//  Dokogacha
//

import SwiftUI
import UIKit

/// 共有シート（`UIActivityViewController`）を SwiftUI のシートとして出す。
///
/// `ShareLink` は押したときの処理を持てず、押したことを同時のタップ（`simultaneousGesture`）で受けると、
/// VoiceOver のダブルタップ・Switch Control では処理が呼ばれない（PR #94 の持ち越し）。
/// 押したときに処理をしてから共有シートを出したいボタンは、ふつうの `Button` からこのシートを出す。
struct ActivityShareSheet: UIViewControllerRepresentable {
    /// 共有するもの（`UIImage`・`String`・`URL` など）
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 共有シートに渡す画像（`sheet(item:)` で出すため、出すたびに別の ID を持つ）
struct SharedImage: Identifiable {
    /// シートを出すたびに変わる ID
    let id = UUID()
    /// 共有する画像
    let image: UIImage
}
