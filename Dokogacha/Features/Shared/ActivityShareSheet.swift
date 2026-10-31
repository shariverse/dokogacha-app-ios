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
/// 押したときに処理をしてから共有シートを出したいボタンは、ふつうの `Button` に `activityShareSheet(item:)` を付けて出す。
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

extension View {
    /// `item` に画像が入ったら共有シートを出す（閉じたら nil に戻す）。押したボタンに付ける。
    ///
    /// iPhone（横の size class が compact）では今までどおり下からのシートで出し、iPad（regular）では付けたボタンを指すポップオーバーで出す
    /// （シートに入れると iPad ではフォームシートになるため）
    func activityShareSheet(item: Binding<SharedImage?>) -> some View {
        modifier(ActivityShareSheetModifier(item: item))
    }
}

/// 共有シートの出し方を横の size class で選ぶ（`activityShareSheet(item:)`）
private struct ActivityShareSheetModifier: ViewModifier {
    @Binding var item: SharedImage?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.background {
                ActivitySharePopover(item: $item)
            }
        } else {
            content.sheet(item: $item) { shared in
                ActivityShareSheet(items: [shared.image])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }
}

/// iPad で共有シートを、置いた場所（押したボタンの背景）を指すポップオーバーで出す。
///
/// SwiftUI の `popover` の中に `UIActivityViewController` を入れると大きさが決まらないので、UIKit の
/// `popoverPresentationController` に置いた場所の View を渡して出す。閉じたら（共有した・外を押した）`item` を nil に戻す
/// （`completionWithItemsHandler` は、共有したときも何もせずに閉じたときも呼ばれる）
private struct ActivitySharePopover: UIViewControllerRepresentable {
    @Binding var item: SharedImage?

    func makeUIViewController(context: Context) -> Presenter {
        Presenter()
    }

    func updateUIViewController(_ presenter: Presenter, context: Context) {
        presenter.onDismiss = { item = nil }
        presenter.show(item)
    }

    /// ボタンの背景に敷く、ポップオーバーの元になる View を持つ View Controller（タッチは受けない）
    final class Presenter: UIViewController {
        /// 共有シートが閉じたときの処理
        var onDismiss: () -> Void = {}
        /// 出している共有シートの画像の ID（出していなければ nil）
        private var shownID: UUID?

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        /// 画像が入ったら共有シートを出し、nil になったら閉じる（同じ画像で出し直さない）
        func show(_ item: SharedImage?) {
            guard let item else {
                if shownID != nil {
                    shownID = nil
                    presentedViewController?.dismiss(animated: true)
                }
                return
            }
            guard item.id != shownID, presentedViewController == nil else {
                return
            }
            shownID = item.id
            let controller = UIActivityViewController(activityItems: [item.image], applicationActivities: nil)
            controller.modalPresentationStyle = .popover
            // 置いた View を指す（回転などでボタンの大きさが変わっても付いていく）。
            // 確認のダイアログと同じくボタンの上か下に出す（横に出すと隣のボタンを隠す）
            controller.popoverPresentationController?.sourceItem = view
            controller.popoverPresentationController?.permittedArrowDirections = [.up, .down]
            controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.shownID = nil
                self?.onDismiss()
            }
            present(controller, animated: true)
        }
    }
}
