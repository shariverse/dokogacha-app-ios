//
//  MainNavigationView.swift
//  Dokogacha
//

import SwiftUI

/// 表示名を登録した後の画面の根元。ホーム（S-02）を根元にした `NavigationStack` と、シート・フルスクリーンカバーの行き先を持つ（03 の §2）。
///
/// 行き先は `AppRoute` で受け取り、`presentation` に合わせて積むかシート・フルスクリーンカバーで出す。
/// 標準のナビゲーションバーは各画面で隠し、画面ごとのヘッダー（`DGHeader`）を使う（03 の §3）。
///
/// ルームを作ったら、S-03 を積みから外して作ったルーム（S-07）とその上に S-04 を積む（`AppRoute.pathAfterCreating`）。
/// S-04 から戻る・「ルームへ進む」と S-07 に出て、S-07 から戻るとホームに戻る（03 の §1「S-04 招待：プッシュ（戻るとルーム）」）。
struct MainNavigationView: View {
    /// 出している行き先（積み・シート・フルスクリーンカバー）
    @State private var presentation = AppPresentation()
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
        NavigationStack(path: $presentation.path) {
            HomeView(model: homeModel) { route in
                open(route)
            }
            // ナビゲーションバーを隠しても、端からのスワイプで戻れるようにする
            .background(InteractivePopGesture())
            .navigationDestination(for: AppRoute.self) { route in
                destination(route)
            }
        }
        // シートを閉じ終えたら、その間に開こうとしたカバーを出す（`AppPresentation`）
        .sheet(
            item: $presentation.sheet,
            onDismiss: { presentation.sheetDismissed() },
            content: { route in
                destination(route)
            }
        )
        .fullScreenCover(item: $presentation.fullScreen) { route in
            destination(route)
        }
    }

    /// 行き先を開く（積む・シート・フルスクリーンカバーで出す。シートが出ていればシートを閉じてからカバーを出す）
    private func open(_ route: AppRoute) {
        presentation.open(route)
    }

    /// 行き先の画面
    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .createRoom:
            CreateRoomView(model: CreateRoomModel(functions: services.functions, toasts: toasts)) { created in
                presentation.path = AppRoute.pathAfterCreating(created, from: presentation.path)
            }
        case let .invite(created):
            InviteView(model: InviteModel(destination: created, toasts: toasts)) {
                presentation.path = AppRoute.pathOpeningRoom(from: presentation.path)
            }
        case .joinByCode:
            // 参加したら（もとからメンバーなら）シートを閉じて、そのルームを開く（03 の §2「S-06 → 参加する → S-07」）
            JoinRoomFlowView(functions: services.functions) { roomID in
                presentation.sheet = nil
                presentation.path.append(.room(id: roomID))
            }
        case let .room(roomID):
            room(roomID: roomID)
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
        case .gacha, .result:
            cover(route)
        }
    }

    /// S-07 ルーム（プッシュ）
    private func room(roomID: String) -> some View {
        let model = RoomModel(
            roomID: roomID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: toasts,
            seenDraws: services.seenDraws
        )
        return RoomView(model: model) { route in
            open(route)
        }
    }

    /// S-13・S-14 のフルスクリーンカバー。S-13 はカプセルを開け終えたら同じカバーの中で S-14 に替わる（`GachaFlowView`）
    @ViewBuilder private func cover(_ route: AppRoute) -> some View {
        switch route {
        case let .gacha(roomID):
            GachaFlowView { onOpened in
                gacha(roomID: roomID, onOpened: onOpened)
            } result: { drawID in
                result(roomID: roomID, drawID: drawID)
            }
        case let .result(roomID, drawID):
            result(roomID: roomID, drawID: drawID)
        default:
            // カバーで出す行き先は S-13・S-14 だけ（`AppRoute.presentation`）
            EmptyView()
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
            presentation.sheet = nil
            presentation.path = []
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
            presentation.sheet = nil
            toasts.show("設定を保存しました")
        }
    }

    /// S-13 ガチャ（フルスクリーンカバー）。トーストはカバーの中に重ねるので、カバー用の窓口を作って渡す。
    ///
    /// カプセルを開け終えたら `onOpened` で同じカバーの中の S-14 に替える（`GachaFlowView`）。
    /// UI テストでは演出を待たないよう、常に「視差効果を減らす」で動かす
    private func gacha(roomID: String, onOpened: @escaping (String) -> Void) -> GachaView {
        let coverToasts = DGToastCenter()
        let model = GachaModel(
            roomID: roomID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: coverToasts,
            seenDraws: services.seenDraws
        )
        return GachaView(model: model, toasts: coverToasts, forcesReducedMotion: LaunchContext.current.isUITesting, onOpened: onOpened)
    }

    /// S-14 結果（フルスクリーンカバー）。トーストはカバーの中に重ねる。UI テストではきっぷとハンコを動かさない
    private func result(roomID: String, drawID: String) -> ResultView {
        let coverToasts = DGToastCenter()
        let model = ResultModel(
            roomID: roomID,
            drawID: drawID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: coverToasts
        )
        return ResultView(model: model, toasts: coverToasts, animatesIn: !LaunchContext.current.isUITesting)
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
