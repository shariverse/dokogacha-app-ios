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
///
/// 招待リンクで開かれたら（`DeepLinkRouter` に招待コードが入ったら）、いま出している画面の上に S-05・S-06 のシートを
/// そのコードで開く（03 の §2「招待リンク → S-06」）。表示名を登録する前に届いたコードは、この画面が出たときに開く。
///
/// プッシュ通知を開いたら、そのルームを開く（`PushNotificationRouting`）。通知の許可は、ルームを作成・参加したときに尋ねる
/// （02 の §8「初めてルームを作成または参加したときに表示」。まだ尋ねていないときだけ）。
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
    /// 招待リンクで開かれたときの行き先
    private let deepLinks: DeepLinkRouter
    /// プッシュ通知のまとめ役（`DokoGachaApp` が渡す。プレビューでは無い）
    @Environment(PushNotificationCoordinator.self) private var push: PushNotificationCoordinator?

    /// - Parameters:
    ///   - userID: 自分の uid
    ///   - services: データ層の窓口
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - deepLinks: 招待リンクで開かれたときの行き先
    init(userID: String, services: DataServices, toasts: DGToastCenter, deepLinks: DeepLinkRouter) {
        _homeModel = State(initialValue: HomeModel(userID: userID, repository: services.rooms, toasts: toasts))
        self.userID = userID
        self.services = services
        self.toasts = toasts
        self.deepLinks = deepLinks
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
        // カバーを閉じ終えたら、その間に開こうとしたシート（招待リンクの S-05・S-06）を出す（`AppPresentation`）
        .fullScreenCover(
            item: $presentation.fullScreen,
            onDismiss: { presentation.fullScreenDismissed() },
            content: { route in
                destination(route)
                    // S-14 で作成者がルームを終了したら、カバーを閉じてホームに戻る（03 の §2「この行き先で決定 → S-02」）
                    .environment(\.roomClosed, RoomClosedAction {
                        presentation.fullScreen = nil
                        presentation.path = []
                        toasts.show("行き先が決まりました！")
                    })
            }
        )
        // 招待リンクで開かれたら、そのコードで S-05・S-06 を開く（この画面が出る前に届いていたものも、出たときに開く）
        .onChange(of: deepLinks.pendingInviteCode, initial: true) {
            if let code = deepLinks.takePendingInviteCode() {
                openInviteLink(code)
            }
        }
        .modifier(PushNotificationRouting(presentation: $presentation, userID: userID, deepLinks: deepLinks, push: push))
    }

    /// ルームを作成・参加した。まだ尋ねていなければ、通知の許可を尋ねる
    private func requestNotificationPermission() {
        Task { await push?.requestAuthorizationIfNeeded() }
    }

    /// 招待リンクのコードで S-05・S-06 のシートを開く。
    ///
    /// 積んだ画面はそのまま残す（参加したら、その上にルームを積む）。別のシートを出していたら差し替える。
    /// フルスクリーンカバー（S-13・S-14）を出していたら閉じずに待たせ、ユーザーがカバーを閉じてからシートを出す
    /// （S-13 は演出中に閉じられない。`AppPresentation`）
    private func openInviteLink(_ code: InviteCode) {
        presentation.open(.joinByInviteLink(code))
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
                requestNotificationPermission()
            }
        case let .invite(created):
            InviteView(model: InviteModel(destination: created, toasts: toasts)) {
                presentation.path = AppRoute.pathOpeningRoom(from: presentation.path)
            }
        case .joinByCode, .joinByInviteLink:
            joinRoomFlow(initialCode: route.inviteLinkCode)
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

    /// S-13・S-14 のフルスクリーンカバー。S-13 はカプセルを開け終えたら同じカバーの中で S-14 に替わり、
    /// S-14 は引き直しが可決したら同じカバーの中で S-13 に戻る（`GachaFlowView`）
    @ViewBuilder private func cover(_ route: AppRoute) -> some View {
        switch route {
        case let .gacha(roomID):
            gachaFlow(roomID: roomID, startingWith: nil)
        case let .result(roomID, drawID):
            gachaFlow(roomID: roomID, startingWith: drawID)
        default:
            // カバーで出す行き先は S-13・S-14 だけ（`AppRoute.presentation`）
            EmptyView()
        }
    }

    /// S-05・S-06（シート）。参加したら（もとからメンバーなら）シートを閉じて、そのルームを開く（03 の §2「S-06 → 参加する → S-07」）
    /// - Parameter initialCode: 招待リンクで開いたときの招待コード（ホームの「招待コードで参加」からなら nil）
    private func joinRoomFlow(initialCode: InviteCode?) -> some View {
        JoinRoomFlowView(functions: services.functions, initialCode: initialCode) { roomID in
            presentation.sheet = nil
            presentation.path.append(.room(id: roomID))
            requestNotificationPermission()
        }
    }

    /// S-13 と S-14 を行き来するカバーの中身（`drawID` があれば S-14 から始める）
    private func gachaFlow(roomID: String, startingWith drawID: String?) -> some View {
        GachaFlowView(startingWith: drawID) { onOpened in
            gacha(roomID: roomID, onOpened: onOpened)
        } result: { drawID, onPlayAgain in
            result(roomID: roomID, drawID: drawID, onPlayAgain: onPlayAgain)
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

    /// S-14 結果（フルスクリーンカバー）。トーストはカバーの中に重ねる。UI テストではきっぷとハンコを動かさない。
    /// 引き直しが可決したら、「ガチャを回す」で `onPlayAgain`（同じカバーの中の S-13 に戻る）
    private func result(roomID: String, drawID: String, onPlayAgain: @escaping () -> Void) -> ResultView {
        let coverToasts = DGToastCenter()
        let model = ResultModel(
            roomID: roomID,
            drawID: drawID,
            userID: userID,
            repository: services.rooms,
            functions: services.functions,
            toasts: coverToasts
        )
        return ResultView(model: model, toasts: coverToasts, animatesIn: !LaunchContext.current.isUITesting, onPlayAgain: onPlayAgain)
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
