//
//  OfflineBannerModifier.swift
//  Dokogacha
//

import SwiftUI

/// 端末がオフラインの間、画面の上端（セーフエリアの内側・ヘッダーの上）に「オフラインです」のバナーを出す（02 の §9）。
///
/// 回線の状態は `@Environment(NetworkStatus.self)` から読む（プレビューなどで無ければ出さない）。
/// シート・フルスクリーンカバーは根元の画面の上に重なるので、根元（`RootView`）に加えて、それぞれの中身にも付ける。
/// 出し入れは「視差効果を減らす」に関わらずフェードだけにする（画面の中身が上下に動くのは、バナーの高さの分だけ）。
private struct OfflineBannerModifier: ViewModifier {
    @Environment(NetworkStatus.self) private var network: NetworkStatus?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if network?.isOffline == true {
                    DGOfflineBanner()
                        .transition(.opacity)
                }
            }
            .animation(DGMotion.reducedFade, value: network?.isOffline == true)
    }
}

extension View {
    /// 端末がオフラインの間、上端に「オフラインです」のバナーを出す。画面の根元・シートとカバーの中身に付ける
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
