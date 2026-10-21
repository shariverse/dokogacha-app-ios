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
    /// ルーム・メンバー・候補
    let rooms: any RoomRepository
    /// Callable Functions
    let functions: any FunctionsClient
    /// 擬似のサーバー（擬似のときだけ。UI テストのシナリオやプレビューで状態を足すのに使う）
    let inMemoryServer: InMemoryServer?

    /// サインインしてよいか（接続できないときは、サインインを試みない）
    var allowsSignIn: Bool {
        backend != .unavailable
    }

    /// 接続できないときの窓口
    static var unavailable: Self {
        let server = UnavailableServer()
        return Self(backend: .unavailable, auth: server, rooms: server, functions: server, inMemoryServer: nil)
    }

    /// 擬似のサーバーの窓口
    static func inMemory(_ server: InMemoryServer, scenario: DemoScenario) -> Self {
        Self(backend: .inMemory(scenario), auth: server, rooms: server, functions: server, inMemoryServer: server)
    }

    /// Firebase の窓口。`FirebaseApp.configure` の後でだけ作る
    static func firebase() -> Self {
        let gateway = FirebaseFirestoreGateway()
        let functions = CallableFunctionsClient(transport: FirebaseCallableTransport())
        return Self(
            backend: .firebase,
            auth: FirebaseAuthService(gateway: gateway, functions: functions),
            rooms: FirestoreRoomRepository(gateway: gateway),
            functions: functions,
            inMemoryServer: nil
        )
    }

    /// 起動時の接続の状態と起動のしかたから、窓口を選ぶ。
    ///
    /// - Firebase を初期化した → Firebase の実装
    /// - テスト・撮影のために初期化しなかった → 擬似のサーバー。`-uiTesting`・撮影モードでは `-demo-scenario` のデータを入れる
    ///   （Unit テストのホストは、テストが自分でサーバーを作るので空のまま）
    /// - 設定が無い・読めない → 接続できない窓口
    static func make(connection: ServerConnection, launch: LaunchContext) -> Self {
        switch connection {
        case .firebase:
            return firebase()
        case let .disabled(reason):
            let scenario: DemoScenario = reason == .unitTestHost ? .empty : launch.demoScenario
            return inMemory(InMemoryServer.demo(scenario), scenario: scenario)
        case .unavailable, .notStarted:
            return unavailable
        }
    }
}
