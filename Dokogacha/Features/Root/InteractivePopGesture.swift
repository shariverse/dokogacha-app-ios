//
//  InteractivePopGesture.swift
//  Dokogacha
//

import SwiftUI
import UIKit

/// 標準のナビゲーションバーを隠した `NavigationStack` でも、画面の左端からのスワイプで戻れるようにする。
///
/// 03 の §3 でナビゲーションバーを隠す（`.toolbar(.hidden, for: .navigationBar)`）と、UIKit の
/// `UINavigationController` は端からのスワイプ（`interactivePopGestureRecognizer`）を始めなくなる（iOS 26.5 の Simulator で確かめた）。
/// ジェスチャーの delegate を差し替え、積んだ画面が 2 つ以上で、画面の切り替えの途中でないときだけ始めさせる。
///
/// `NavigationStack` の根元の画面に `.background(InteractivePopGesture())` で 1 回だけ付ける
/// （`UINavigationController` は積んだ画面で共有なので、根元で差し替えれば全部の画面に効く）。
struct InteractivePopGesture: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ProbeViewController {
        ProbeViewController(coordinator: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: ProbeViewController, context: Context) {}

    /// 端からのスワイプの delegate。
    ///
    /// ジェスチャーの `delegate` は弱い参照なので、このビューの寿命（`NavigationStack` の根元が出ている間）だけ持つ Coordinator にする
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// 差し替えた `UINavigationController`（弱い参照。持ち主は SwiftUI）
        weak var navigationController: UINavigationController?

        /// 積んだ画面が 2 つ以上で、切り替えの途中でないときだけ始める（根元でスワイプすると画面が固まるのを防ぐ）
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController else {
                return false
            }
            return navigationController.viewControllers.count > 1 && navigationController.transitionCoordinator == nil
        }
    }

    /// 親の `UINavigationController` を見つけて、端からのスワイプの delegate を差し替えるだけの見えない画面
    final class ProbeViewController: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) は使わない")
        }

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach()
        }

        /// 親をたどって見つけた `UINavigationController` のスワイプの delegate を、Coordinator にする
        private func attach() {
            guard let navigationController, let gesture = navigationController.interactivePopGestureRecognizer else {
                return
            }
            coordinator.navigationController = navigationController
            gesture.delegate = coordinator
            gesture.isEnabled = true
        }
    }
}
