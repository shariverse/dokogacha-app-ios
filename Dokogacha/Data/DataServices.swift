//
//  DataServices.swift
//  Dokogacha
//

import Foundation

/// データ層の窓口のまとまり。起動時に 1 つ作り、`ServerSession.services` で画面に渡す。
///
/// 画面の Model は、ここから `RoomRepository` などの protocol を受け取る（実装が Firebase か擬似のサーバーかを知らない）。
struct DataServices {
    /// どの実装か
    enum Backend: Equatable {
        /// Firebase（Emulator・dev・prod）
        case firebase
        /// メモリ上の擬似のサーバー（Unit テストのホスト・`-uiTesting`・撮影モード・プレビュー）
        case inMemory(DemoScenario)
        /// サーバーに接続できない（どの操作も「通信できませんでした」）
        case unavailable
    }

    /// どの実装か
    let backend: Backend
    /// 認証とプロフィール
    let auth: any AuthService
    /// ルーム・メンバー・候補（`requiringOnline` で、オフラインのときはいいね・準備OKを止める窓口に包む）
    var rooms: any RoomRepository
    /// Callable Functions（`requiringOnline` で、オフラインのときは送らない窓口に包む）
    var functions: any FunctionsClient
    /// 擬似のサーバー（擬似のときだけ。UI テストのシナリオやプレビューで状態を足すのに使う）
    let inMemoryServer: InMemoryServer?
    /// 場所検索（F-10）。既定は MapKit、擬似のサーバーのときは決まった結果を返す擬似の検索
    var places: any PlaceSearchService = MapKitPlaceSearchService()
    /// S-08 で選んだ検索のエリア。既定は端末に残す。擬似のサーバーのときはメモリだけ（起動ごとに初めのエリアから始める）
    var searchArea: any SearchAreaStore = UserDefaultsSearchAreaStore()
    /// ガチャの演出を見終えた抽選（F-41）。既定は端末に残す。擬似のサーバーのときはメモリだけ（起動ごとに空から始める）
    var seenDraws: any SeenDrawStore = UserDefaultsSeenDrawStore()
    /// 報告した候補（F-14。ひとこととURLを隠す）。既定は端末に残す。擬似のサーバーのときはメモリだけ（起動ごとに空から始める）
    var reportedCandidates: any ReportedCandidateStore = UserDefaultsReportedCandidateStore()
    /// Analytics のイベントを送る窓口（05 の §9）。既定は何も送らない。Firebase に繋いだときだけ Firebase Analytics に送る
    var analytics: any AnalyticsService = DisabledAnalyticsService()

    /// サインインしてよいか（接続できないときは、サインインを試みない）
    var allowsSignIn: Bool {
        backend != .unavailable
    }

    /// 接続できないときの窓口
    static var unavailable: Self {
        let server = UnavailableServer()
        return Self(backend: .unavailable, auth: server, rooms: server, functions: server, inMemoryServer: nil)
    }

    /// 擬似のサーバーの窓口。場所検索も擬似にする（Unit テストのホスト・`-uiTesting`・撮影モードでネットワークに出ないように）
    static func inMemory(_ server: InMemoryServer, scenario: DemoScenario) -> Self {
        Self(
            backend: .inMemory(scenario),
            auth: server,
            rooms: server,
            functions: server,
            inMemoryServer: server,
            places: DemoPlaceSearchService(),
            searchArea: InMemorySearchAreaStore(),
            seenDraws: InMemorySeenDrawStore(),
            reportedCandidates: InMemoryReportedCandidateStore()
        )
    }

    /// Firebase の窓口。`FirebaseApp.configure` の後でだけ作る
    /// - Parameter network: 回線の状態（あれば、認証の窓口が中で使う Callable もオフラインのときは送らない窓口に包む）
    static func firebase(network: NetworkStatus? = nil) -> Self {
        let gateway = FirebaseFirestoreGateway()
        let callable = CallableFunctionsClient(transport: FirebaseCallableTransport())
        // 認証の窓口が中で呼ぶ Callable（表示名の登録・アカウントの削除）。`functions` の方は `make` が `requiringOnline` で包む
        let authFunctions: any FunctionsClient = network.map { OnlineRequiredFunctionsClient(base: callable, network: $0) } ?? callable
        return Self(
            backend: .firebase,
            auth: FirebaseAuthService(gateway: gateway, functions: authFunctions),
            rooms: FirestoreRoomRepository(gateway: gateway),
            functions: callable,
            inMemoryServer: nil,
            analytics: FirebaseAnalyticsService()
        )
    }

    /// 起動時の接続の状態と起動のしかたから、窓口を選ぶ。
    ///
    /// - Firebase を初期化した → Firebase の実装
    /// - テスト・撮影のために初期化しなかった → 擬似のサーバー。`-uiTesting`・撮影モードでは `-demo-scenario` のデータを入れる
    ///   （Unit テストのホストは、テストが自分でサーバーを作るので空のまま）
    /// - 設定が無い・読めない → 接続できない窓口
    ///
    /// `network` を渡すと、オンライン必須の操作をオフラインのときに止める窓口に包む（`requiringOnline`。02 の §9）
    static func make(connection: ServerConnection, launch: LaunchContext, network: NetworkStatus? = nil) -> Self {
        let services: Self
        switch connection {
        case .firebase:
            services = firebase(network: network)
        case let .disabled(reason):
            let scenario: DemoScenario = reason == .unitTestHost ? .empty : launch.demoScenario
            services = inMemory(InMemoryServer.demo(scenario), scenario: scenario)
        case .unavailable, .notStarted:
            return unavailable
        }
        return network.map(services.requiringOnline) ?? services
    }
}
