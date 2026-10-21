//
//  MainNavigationView.swift
//  Dokogacha
//

import SwiftUI

/// 表示名を登録した後の画面の根元。ホーム（S-02）を根元にした `NavigationStack` と、シートの行き先を持つ（03 の §2）。
///
/// 行き先は `AppRoute` で受け取り、`presentation` に合わせて積むかシートで出す。まだ無い画面は `PendingScreenView`。
/// 標準のナビゲーションバーは各画面で隠し、画面ごとのヘッダー（`DGHeader`）を使う（03 の §3）。
struct MainNavigationView: View {
    /// 積んでいる行き先
    @State private var path: [AppRoute] = []
    /// シートで出している行き先
    @State private var sheet: AppRoute?
    @State private var homeModel: HomeModel

    /// - Parameters:
    ///   - userID: 自分の uid
    ///   - services: データ層の窓口
    ///   - toasts: 通信エラーを出すトーストの窓口
    init(userID: String, services: DataServices, toasts: DGToastCenter) {
        _homeModel = State(initialValue: HomeModel(userID: userID, repository: services.rooms, toasts: toasts))
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(model: homeModel) { route in
                open(route)
            }
            .navigationDestination(for: AppRoute.self) { route in
                destination(route)
            }
        }
        .sheet(item: $sheet) { route in
            destination(route)
        }
    }

    /// 行き先を開く（積む・シートで出す）
    private func open(_ route: AppRoute) {
        switch route.presentation {
        case .push:
            path.append(route)
        case .sheet:
            sheet = route
        }
    }

    /// 行き先の画面（後のタスクで本物の画面に差し替える）
    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .createRoom, .joinByCode, .room, .settings:
            PendingScreenView(route: route)
        }
    }
}
