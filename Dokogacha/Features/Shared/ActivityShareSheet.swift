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
            content.sheet(item: sheetItem) { shared in
                ActivityShareSheet(items: [shared.image])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    /// シートで出す画像。ポップオーバーで出した画像は、ウィンドウが狭くなってシートに切り替わっても出し直さない
    /// （ポップオーバーは閉じて、`item` を nil に戻すところ。`ActivitySharePopover.Presenter.close()`）
    private var sheetItem: Binding<SharedImage?> {
        Binding {
            item.flatMap { ActivitySharePopover.Presenter.isShowing($0) ? nil : $0 }
        } set: { newValue in
            item = newValue
        }
    }
}

/// iPad で共有シートを、置いた場所（押したボタンの背景）を指すポップオーバーで出す。
///
/// SwiftUI の `popover` の中に `UIActivityViewController` を入れると大きさが決まらないので、UIKit の
/// `popoverPresentationController` に置いた場所の View を渡して出す。閉じたら（共有した・外を押した）`item` を nil に戻す
/// （`completionWithItemsHandler` は、共有したときも何もせずに閉じたときも呼ばれる）。
/// ボタンが消えたら（ウィンドウが狭くなった・文字の大きさで並べ方が替わった）、ポップオーバーを閉じて `item` を nil に戻す
private struct ActivitySharePopover: UIViewControllerRepresentable {
    @Binding var item: SharedImage?

    func makeUIViewController(context: Context) -> Presenter {
        Presenter()
    }

    func updateUIViewController(_ presenter: Presenter, context: Context) {
        presenter.onDismiss = { item = nil }
        presenter.show(item)
    }

    static func dismantleUIViewController(_ presenter: Presenter, coordinator: ()) {
        presenter.close()
    }

    /// ボタンの背景に敷く、ポップオーバーの元になる View を持つ View Controller（タッチは受けない）
    final class Presenter: UIViewController {
        /// ポップオーバーで出している（閉じている途中を含む）画像の ID。共有は一度に 1 つなので、アプリで 1 つだけ持つ。
        /// 「きっぷを共有」は `ViewThatFits` の横と縦の両方に入るので、ボタンごとの Presenter が同じ画像を二重に出さないようにする
        private static var showingID: UUID?

        /// 共有シートが閉じたときの処理（`item` を nil に戻す）
        var onDismiss: @MainActor () -> Void = {}
        /// この Presenter から出している共有シート
        private weak var shown: UIActivityViewController?

        /// `item` の画像をポップオーバーで出しているか（閉じている途中を含む）
        static func isShowing(_ item: SharedImage) -> Bool {
            showingID == item.id
        }

        override func loadView() {
            let view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            self.view = view
        }

        /// 画像が入ったら共有シートを出し、nil になったら閉じる（同じ画像で出し直さない）
        func show(_ item: SharedImage?) {
            guard let item else {
                shown?.dismiss(animated: true)
                return
            }
            // 出している画像か、画面に出ていない側のボタン（`ViewThatFits` の選ばれなかった方）なら何もしない
            guard !Self.isShowing(item), view.window != nil else {
                return
            }
            let onDismiss = onDismiss
            guard presentedViewController == nil else {
                // 前のポップオーバーが閉じ終わる前に押された。出せないので、もう一度押せるように `item` を戻す（画面の更新の後に）
                Task { @MainActor in onDismiss() }
                return
            }
            let controller = UIActivityViewController(activityItems: [item.image], applicationActivities: nil)
            controller.modalPresentationStyle = .popover
            // 置いた View を指す（回転などでボタンの大きさが変わっても付いていく）。
            // 確認のダイアログと同じくボタンの上か下に出す（横に出すと隣のボタンを隠す）
            controller.popoverPresentationController?.sourceItem = view
            controller.popoverPresentationController?.permittedArrowDirections = [.up, .down]
            // この Presenter が先に消えても `item` を戻せるよう、self を介さずに呼ぶ
            let id = item.id
            controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.shown = nil
                Self.finish(id, onDismiss: onDismiss)
            }
            Self.showingID = id
            shown = controller
            present(controller, animated: true)
        }

        /// ボタンが消えるとき、出している共有シートを閉じて `item` を nil に戻す（画面の更新の後に）
        func close() {
            guard let controller = shown, let id = Self.showingID else {
                return
            }
            shown = nil
            controller.completionWithItemsHandler = nil
            controller.dismiss(animated: false)
            let onDismiss = onDismiss
            Task { @MainActor in
                Self.finish(id, onDismiss: onDismiss)
            }
        }

        /// 共有シートが閉じた（`id` の画像を出し終えた）
        private static func finish(_ id: UUID, onDismiss: @MainActor () -> Void) {
            if showingID == id {
                showingID = nil
            }
            onDismiss()
        }
    }
}
