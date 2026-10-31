//
//  ResultRevealSetting.swift
//  Dokogacha
//

import Foundation
import Observation

/// 設定の「結果の演出」（S-16）で選んだ、S-14 で行き先きっぷを出す演出（Issue #158）。
///
/// 端末の好みなので端末に覚えるだけで、サーバーには送らない（アカウントを削除しても忘れない。`AccountDeviceData` で消さない）。
/// `AppDelegate` が起動時に 1 つ作り、`DokoGachaApp` が `@Environment` で画面に渡す。
/// 画面は `@Environment(ResultRevealSetting.self)` を省略可で読み、無ければ（プレビューなど）標準の演出にする。
/// `-uiTesting`・撮影モードでは端末に覚えず、起動引数 `-result-animation <演出>` の演出（無ければ標準）から始める
@Observable
final class ResultRevealSetting {
    /// `UserDefaults` の鍵
    static let key = "resultRevealStyle"

    /// 選んでいる演出
    private(set) var style: ResultRevealStyle

    /// 覚える先（nil ならメモリだけ）
    @ObservationIgnored private let defaults: UserDefaults?

    /// - Parameters:
    ///   - defaults: 覚える先。nil ならメモリだけに持つ（テスト・撮影モード）
    ///   - initial: メモリだけに持つときの初めの演出
    init(defaults: UserDefaults?, initial: ResultRevealStyle = .standard) {
        self.defaults = defaults
        if let defaults {
            // 覚えた値が無い・知らない値なら標準にする
            style = defaults.string(forKey: Self.key).flatMap(ResultRevealStyle.init(rawValue:)) ?? .standard
        } else {
            style = initial
        }
    }

    /// 起動のしかたに合わせて作る（`-uiTesting`・撮影モードではメモリだけ、ほかは端末に覚える）
    static func make(launch: LaunchContext, defaults: UserDefaults = .standard) -> ResultRevealSetting {
        if launch.isUITesting || launch.isScreenshotDemo {
            return ResultRevealSetting(defaults: nil, initial: launch.resultRevealStyle ?? .standard)
        }
        return ResultRevealSetting(defaults: defaults)
    }

    /// 演出を選ぶ（端末に覚える）
    func select(_ style: ResultRevealStyle) {
        self.style = style
        defaults?.set(style.rawValue, forKey: Self.key)
    }
}
