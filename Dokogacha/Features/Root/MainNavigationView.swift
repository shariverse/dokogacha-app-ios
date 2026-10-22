//
//  MainNavigationView.swift
//  Dokogacha
//

import SwiftUI

/// 表示名を登録した後の画面の根元。ホーム（S-02）を根元にした `NavigationStack` と、シート・フルスクリーンカバーの行き先を持つ（03 の §2）。
///
/// 行き先は `AppRoute` で受け取り、`presentation` に合わせて積むかシート・フルスクリーンカバーで出す。まだ無い画面は `PendingScreenView`。
/// 標準のナビゲーションバーは各画面で隠し、画面ごとのヘッダー（`DGHeader`）を使う（03 の §3）。
///
/// ルームを作ったら、S-03 を積みから外して作ったルーム（S-07）とその上に S-04 を積む（`AppRoute.pathAfterCreating`）。
/// S-04 から戻る・「ルームへ進む」と S-07 に出て、S-07 から戻るとホームに戻る（03 の §1「S-04 招待：プッシュ（戻るとルーム）」）。
struct MainNavigationView: View {
    /// 積んでいる行き先
    @State private var path: [AppRoute] = []
    /// シートで出している行き先
    @State private var sheet: AppRoute?
    /// フルスクリーンカバーで出している行き先
    @State private var fullScreen: AppRoute?
    @State private var homeModel: HomeModel
    /// 自分の uid
    private let userID: String
    /// データ層の窓口（行き先の画面の Model に渡す）
    private let services: DataServices
    /// 通信エラーを出すトーストの窓口
    private let toasts: DGToastCenter

    /// - Parameters:
    ///   - userID: 自分の uid
    ///   - services: データ層の窓口
    ///   - toasts: 通信エラーを出すトーストの窓口
    init(userID: String, services: DataServices, toasts: DGToastCenter) {
        _homeModel = State(initialValue: HomeModel(userID: userID, repository: services.rooms, toasts: toasts))
        self.userID = userID
        self.services = services
        self.toasts = toasts
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(model: homeModel) { route in
                open(route)
            }
            // ナビゲーションバーを隠しても、端からのスワイプで戻れるようにする
            .background(InteractivePopGesture())
            .navigationDestination(for: AppRoute.self) { route in
                destination(route)
            }
        }
        .sheet(item: $sheet) { route in
            destination(route)
        }
        .fullScreenCover(item: $fullScreen) { route in
            destination(route)
        }
    }

    /// 行き先を開く（積む・シート・フルスクリーンカバーで出す）
    private func open(_ route: AppRoute) {
        switch route.presentation {
        case .push:
            path.append(route)
        case .sheet:
            sheet = route
        case .fullScreenCover:
            fullScreen = route
        }
    }

    /// 行き先の画面（後のタスクで本物の画面に差し替える）
    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .createRoom:
            CreateRoomView(model: CreateRoomModel(functions: services.functions, toasts: toasts)) { created in
                path = AppRoute.pathAfterCreating(created, from: path)
            }
        case let .invite(created):
            InviteView(model: InviteModel(destination: created, toasts: toasts)) {
                path = AppRoute.pathOpeningRoom(from: path)
            }
        case .joinByCode:
            // 参加したら（もとからメンバーなら）シートを閉じて、そのルームを開く（03 の §2「S-06 → 参加する → S-07」）
            JoinRoomFlowView(functions: services.functions) { roomID in
                sheet = nil
                path.append(.room(id: roomID))
            }
        case let .room(roomID):
            let model = RoomModel(roomID: roomID, userID: userID, repository: services.rooms, functions: services.functions, toasts: toasts)
            RoomView(model: model) { route in
                open(route)
            }
        case .settings:
            SettingsView(model: SettingsModel(userID: userID, auth: services.auth, toasts: toasts), toasts: toasts)
        case let .candidateDetail(roomID, candidateID):
            candidateDetail(roomID: roomID, candidateID: candidateID)
        case let .addCandidate(roomID):
            AddCandidateView(
                model: AddCandidateModel(
                    roomID: roomID,
                    userID: userID,
                    repository: services.rooms,
                    functions: services.functions,
                    places: services.places,
                    toasts: toasts
                )
            )
        case let .members(roomID):
            members(roomID: roomID)
        case let .roomSettings(roomID):
            roomSettings(roomID: roomID)
        case let .gacha(roomID):
            gacha(roomID: roomID)
        }
    }

    /// S-11 メンバー一覧（シート）。退出できたら、シートを閉じてホームに戻り、トーストで知らせる
    private func members(roomID: String) -> some View {
        let sheetToasts = DGToastCenter()
        let model = MembersModel(
            roomID: roomID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: sheetToasts
        )
        return MembersView(model: model, toasts: sheetToasts) {
            sheet = nil
            path = []
            toasts.show("ルームから退出しました")
        }
    }

    /// S-12 ルーム設定（シート）。保存できたら、シートを閉じてトーストで知らせる
    private func roomSettings(roomID: String) -> some View {
        let sheetToasts = DGToastCenter()
        let model = RoomSettingsModel(
            roomID: roomID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: sheetToasts
        )
        return RoomSettingsView(model: model, toasts: sheetToasts) {
            sheet = nil
            toasts.show("設定を保存しました")
        }
    }

    /// S-13 ガチャ（フルスクリーンカバー）。トーストはカバーの中に重ねるので、カバー用の窓口を作って渡す。
    ///
    /// カプセルを開け終えたら、いまはカバーを閉じてルーム（S-07）に戻る（S-14 結果はタスク 28 で差し替える）。
    /// UI テストでは演出を待たないよう、常に「視差効果を減らす」で動かす
    private func gacha(roomID: String) -> some View {
        let coverToasts = DGToastCenter()
        let model = GachaModel(
            roomID: roomID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: coverToasts,
            seenDraws: services.seenDraws
        )
        return GachaView(model: model, toasts: coverToasts, forcesReducedMotion: LaunchContext.current.isUITesting) { _ in
            fullScreen = nil
        }
    }

    /// S-10 候補の詳細（シート）。トーストはシートの中に重ねるので、シート用の窓口を作って渡す
    private func candidateDetail(roomID: String, candidateID: String) -> some View {
        let sheetToasts = DGToastCenter()
        let model = CandidateDetailModel(
            roomID: roomID,
            candidateID: candidateID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: sheetToasts
        )
        return CandidateDetailView(model: model, toasts: sheetToasts)
    }
}
