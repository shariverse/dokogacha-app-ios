//
//  NavigationLock.swift
//  Dokogacha
//

import Observation
import SwiftUI

/// 送っている途中の画面から戻らせない印（`NavigationStack` ごとに 1 つ）。
///
/// 送っている途中に戻る・閉じると、画面の Task が止まり、サーバーでは済んだのに画面は進まない（参加したのにルームが開かない など）。
/// 画面は `.lockNavigation(while:)` で「送っている途中」を知らせ、ここに集める。
/// - 端からのスワイプで戻る（`InteractivePopGesture`）は、どれかの画面が送っている途中なら始めない
/// - シートの下スワイプは `interactiveDismissDisabled` で止める（`.lockNavigation(while:)` が一緒に付ける）
/// - ヘッダーの戻る・閉じるボタンは、各画面が `.disabled` で止める
@Observable
final class NavigationLock {
    /// 送っている途中の画面（画面ごとの ID）
    private(set) var holders: Set<UUID> = []

    /// どれかの画面が送っている途中か
    var isLocked: Bool {
        !holders.isEmpty
    }

    /// 画面の「送っている途中」を入れ替える
    /// - Parameters:
    ///   - holder: 画面の ID
    ///   - locked: 送っている途中か
    func set(_ holder: UUID, locked: Bool) {
        if locked {
            holders.insert(holder)
        } else {
            holders.remove(holder)
        }
    }
}

extension EnvironmentValues {
    /// いまの `NavigationStack` の戻らせない印（無ければ、シートの下スワイプだけを止める）
    @Entry var navigationLock: NavigationLock?
}

/// 送っている途中は、端からのスワイプとシートの下スワイプで戻らせない
private struct LockNavigationModifier: ViewModifier {
    /// 送っている途中か
    let isLocked: Bool

    @Environment(\.navigationLock) private var lock
    /// この画面の ID（印に入れる）
    @State private var holder = UUID()

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isLocked)
            .onChange(of: isLocked, initial: true) { _, locked in
                lock?.set(holder, locked: locked)
            }
            .onDisappear {
                lock?.set(holder, locked: false)
            }
    }
}

extension View {
    /// 送っている途中は、端からのスワイプで戻る・シートを下スワイプで閉じるのを止める（ヘッダーのボタンは各画面で止める）
    /// - Parameter isLocked: 送っている途中か
    func lockNavigation(while isLocked: Bool) -> some View {
        modifier(LockNavigationModifier(isLocked: isLocked))
    }
}
