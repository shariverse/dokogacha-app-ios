//
//  ScreenshotDemo.swift
//  Dokogacha
//
//  App Store 用スクリーンショットの撮影モード。
//  Tools/capture_screenshots.sh が次の起動引数でアプリを起動し、目的の画面をデモデータで開かせる。
//
//    -screenshot-demo -screenshot-scene <Scene の rawValue> -AppleLanguages (<言語>) -AppleLocale <ロケール>
//
//  画面を足すときは、Scene に case を足し、App/DokoGachaApp.swift の rootView で開く画面を返し、
//  AppStore/screenshots.json の scenes に同じ rawValue を足す（突き合わせは Tools/app_store_config.py が行う）。
//  デモデータは実データと混ざらないよう、撮影モードのときだけメモリ上やインメモリのストアに用意する。
//

import SwiftUI

enum ScreenshotDemo {
    /// 撮る画面。rawValue が AppStore/screenshots.json の scene と対応する
    enum Scene: String {
        case home
        case onboarding
        case createRoom
        case invite
        case settings
        case room
        case candidateDetail
        case addCandidate
        case members
        case roomSettings
        case gacha
        case result
        case resultMember
        case homeMemories
        case pastIdeas
        case inviteLastMembers
        case roomInvite
        case roomAdFree
        case settingsAppleLinked
        case settingsAdFree
        case settingsDeleteAccount
        case licenses
    }

    /// 撮影モードで起動するときの起動引数（`LaunchContext` からも読むので nonisolated）
    nonisolated static let argument = "-screenshot-demo"

    /// 撮影モードで、バナー広告の場所に固定の見た目の枠（`DGAdPlaceholder`）を出す起動引数（`LaunchContext` からも読むので nonisolated）。
    ///
    /// App Store の撮影（`Tools/capture_screenshots.sh`）はこれを付けないので、広告の場所を取らずに撮る
    /// （枠の高さ 50 と本物のアダプティブバナーの高さが違い、App Store の画面に実際と違う見た目を載せないため。PR #89 の持ち越し）。
    /// PR のスクリーンショットで広告の場所を見せるときに付ける
    nonisolated static let adPlaceholderArgument = "-screenshot-ad-placeholder"

    /// 撮影モードで起動しているか
    static let isEnabled = ProcessInfo.processInfo.arguments.contains(argument)

    /// 撮影モードで開く画面。撮影モードでないときと、知らない値を渡されたときは nil
    static let scene: Scene? = {
        guard isEnabled else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot-scene"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Scene(rawValue: arguments[index + 1])
    }()
}

extension ScreenshotDemo {
    /// S-01 オンボーディングを擬似のサーバーで開く（起動の流れを通さず、`-demo-scenario` によらずに S-01 を出す）。
    ///
    /// 起動引数 `-screenshot-display-name <名前>` を付けると、入力欄にその名前を入れた状態で開く（入力した状態・無効の状態を撮るため）
    struct OnboardingScene: View {
        /// 入力欄に入れておく名前の起動引数
        static let displayNameArgument = "-screenshot-display-name"

        @State private var toasts = DGToastCenter()
        private let model: OnboardingModel

        /// - Parameter auth: 表示名を登録する窓口（撮影モードでは擬似のサーバー）
        init(auth: any AuthService) {
            let toasts = DGToastCenter()
            let model = OnboardingModel(auth: auth, toasts: toasts)
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: Self.displayNameArgument), arguments.indices.contains(index + 1) {
                model.displayName = arguments[index + 1]
            }
            self.model = model
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            OnboardingView(model: model)
                .dgToast(toasts)
        }
    }
}

extension ScreenshotDemo {
    /// S-03 ルーム作成を擬似のサーバーで開く（ホームから進まずに、S-03 だけを `NavigationStack` に入れて出す）。
    ///
    /// 起動引数 `-screenshot-room-name <名前>` でルーム名を入れ、`-screenshot-unlock-rule <UnlockRule の rawValue>` で
    /// 解禁の条件を選んだ状態で開く（締切日時のピッカーを出した状態を撮るため）
    struct CreateRoomScene: View {
        /// ルーム名の起動引数
        static let roomNameArgument = "-screenshot-room-name"
        /// 解禁の条件の起動引数
        static let unlockRuleArgument = "-screenshot-unlock-rule"

        @State private var toasts: DGToastCenter
        private let model: CreateRoomModel

        /// - Parameter functions: `createRoom` を呼ぶ窓口（撮影モードでは擬似のサーバー）
        init(functions: any FunctionsClient) {
            let toasts = DGToastCenter()
            let model = CreateRoomModel(functions: functions, toasts: toasts)
            if let name = ScreenshotDemo.value(after: Self.roomNameArgument) {
                model.name = name
            }
            if let rule = ScreenshotDemo.value(after: Self.unlockRuleArgument).flatMap(UnlockRule.init(rawValue:)) {
                model.unlockRule = rule
            }
            self.model = model
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                CreateRoomView(model: model) { _ in }
            }
            .dgToast(toasts)
        }
    }

    /// S-04 招待を、デモのルーム（「年末の旅行」・招待コード `DK7-29Q`）で開く
    struct InviteScene: View {
        @State private var toasts = DGToastCenter()

        var body: some View {
            NavigationStack {
                if let code = InviteCode(DemoScenario.inviteCode) {
                    InviteView(
                        model: InviteModel(
                            destination: InviteDestination(roomID: DemoScenario.roomID, roomName: "年末の旅行", inviteCode: code),
                            toasts: toasts
                        )
                    ) {}
                }
            }
            .dgToast(toasts)
        }
    }

    /// S-15 設定を擬似のサーバーで開く（ホームから進まずに、設定の画面を根元にして出す）。
    ///
    /// 既定は Apple に未連携・広告非表示を買っていない状態。`settingsAppleLinked`・`settingsAdFree` の scene では、
    /// 擬似のサーバーのこの端末のユーザーを連携済み・購入済み（`users.adFree`）にしてから開く。
    /// `settingsDeleteAccount` の scene では、「アカウントを削除しますか？」の確認を出した状態で開く（02 の F-06）
    struct SettingsScene: View {
        @State private var toasts: DGToastCenter
        private let model: SettingsModel

        /// - Parameters:
        ///   - services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        ///   - appleLinked: Sign in with Apple に連携済みにするか
        ///   - adFree: 広告非表示を購入済みにするか
        ///   - confirmingDeletion: 「アカウントを削除しますか？」の確認を出した状態で開くか
        init(services: DataServices, appleLinked: Bool = false, adFree: Bool = false, confirmingDeletion: Bool = false) {
            let toasts = DGToastCenter()
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            if let server = services.inMemoryServer {
                if appleLinked {
                    server.appleAccounts[DemoAppleAuthorizer.demoIDToken] = userID
                }
                if adFree {
                    server.users[userID]?.adFree = true
                }
            }
            model = SettingsModel(
                userID: userID,
                auth: services.auth,
                purchases: .disabled,
                toasts: toasts,
                appleAuthorizer: DemoAppleAuthorizer()
            )
            model.isConfirmingDeletion = confirmingDeletion
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                SettingsView(model: model, toasts: toasts)
            }
            .dgToast(toasts)
        }
    }

    /// S-07 ルームを、デモのルーム（`DemoScenario.roomID`）で開く（ホームから進まずに、ルームを `NavigationStack` に入れて出す）。
    ///
    /// データは `-demo-scenario` で選ぶ（候補あり: `room-with-candidates`、空: `one-room`）。
    /// 起動引数で撮る状態を選ぶ:
    /// - `-screenshot-like <候補の ID>`: その候補に自分がいいねした状態で開く（いいねした後を撮るため）
    /// - `-screenshot-ready <uid,uid,…>`: そのメンバーが準備OKにした状態で開く（解禁の判定も通す。「あと N人」・解禁を撮るため）
    /// - `-screenshot-force-unlocked`: 作成者（自分）が強制解禁した状態で開く
    /// - `-screenshot-confirm-force-unlock`: 強制解禁の確認のダイアログを出した状態で開く
    struct RoomScene: View {
        /// いいねしておく候補の起動引数
        static let likeArgument = "-screenshot-like"
        /// 準備OKにしておくメンバーの起動引数（uid をカンマでつなぐ）
        static let readyArgument = "-screenshot-ready"
        /// 強制解禁しておく起動引数
        static let forceUnlockedArgument = "-screenshot-force-unlocked"
        /// 強制解禁の確認のダイアログを出しておく起動引数
        static let confirmForceUnlockArgument = "-screenshot-confirm-force-unlock"

        @State private var toasts: DGToastCenter
        private let model: RoomModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバー。この端末のユーザーはサインイン済み）
        init(services: DataServices) {
            let toasts = DGToastCenter()
            let userID = services.auth.currentUserID ?? DemoScenario.myUserID
            if let server = services.inMemoryServer, let candidateID = ScreenshotDemo.value(after: Self.likeArgument) {
                server.applyDirectWrite {
                    try server.writeLike(true, candidateID: candidateID, roomID: DemoScenario.roomID, userID: userID, by: userID)
                }
            }
            if let server = services.inMemoryServer {
                Self.prepareReadiness(on: server, userID: userID)
            }
            model = RoomModel(
                roomID: DemoScenario.roomID,
                userID: userID,
                repository: services.rooms,
                functions: services.functions,
                toasts: toasts
            )
            model.isConfirmingForceUnlock = ProcessInfo.processInfo.arguments.contains(Self.confirmForceUnlockArgument)
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                RoomView(model: model) { _ in }
            }
            .dgToast(toasts)
        }

        /// 起動引数のメンバーを準備OKにし、指定があれば強制解禁する（擬似のサーバーの書き込みを通すので、解禁の判定もされる）
        private static func prepareReadiness(on server: InMemoryServer, userID: String) {
            let readyIDs = ScreenshotDemo.value(after: readyArgument)?.split(separator: ",").map(String.init) ?? []
            for memberID in readyIDs {
                server.applyDirectWrite {
                    try server.writeReady(true, roomID: DemoScenario.roomID, userID: memberID, by: memberID)
                }
            }
            if ProcessInfo.processInfo.arguments.contains(forceUnlockedArgument) {
                try? server.forceUnlock(RoomRequest(roomId: DemoScenario.roomID), by: userID)
            }
        }
    }

    /// S-08 候補を追加を、デモのルーム（`DemoScenario.roomID`）と擬似の検索で開く（ルームから進まずに、S-08 を `NavigationStack` に入れて出す）。
    ///
    /// 起動引数 `-screenshot-query <語>` を付けると、その語で検索した結果を出した状態で開く（既定は「水族館」）。
    /// `-screenshot-search-area <エリア>`（`SearchArea` の rawValue。`kanto` など）を付けると、そのエリアを選んだ状態で開く（既定は全国）
    struct AddCandidateScene: View {
        /// 検索しておく語の起動引数
        static let queryArgument = "-screenshot-query"
        /// 選んでおくエリアの起動引数
        static let searchAreaArgument = "-screenshot-search-area"
        /// 起動引数が無いときに検索しておく語
        static let defaultQuery = "水族館"

        @State private var toasts: DGToastCenter
        private let model: AddCandidateModel

        /// - Parameter services: データ層の窓口（撮影モードでは擬似のサーバーと擬似の検索）
        init(services: DataServices) {
            let toasts = DGToastCenter()
            if let area = ScreenshotDemo.value(after: Self.searchAreaArgument).flatMap(SearchArea.init(rawValue:)) {
                services.searchArea.save(area)
            }
            model = AddCandidateModel(
                roomID: DemoScenario.roomID,
                userID: services.auth.currentUserID ?? DemoScenario.myUserID,
                repository: services.rooms,
                functions: services.functions,
                places: services.places,
                searchArea: services.searchArea,
                toasts: toasts
            )
            model.search.searchNow(ScreenshotDemo.value(after: Self.queryArgument) ?? Self.defaultQuery)
            _toasts = State(initialValue: toasts)
        }

        var body: some View {
            NavigationStack {
                AddCandidateView(model: model)
            }
            .dgToast(toasts)
        }
    }

    /// 起動引数で `name` の次に渡された値（無ければ nil）
    static func value(after name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
