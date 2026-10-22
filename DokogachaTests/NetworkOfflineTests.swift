//
//  NetworkOfflineTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// オフライン（02 の §9）: 回線の状態の判定・オンライン必須の操作を止める窓口・起動の流れ・いいね/準備OK のトーストを確かめる
struct NetworkOfflineTests {
    /// テストから経路の状態を流せる監視
    final class ControlledNetworkPathMonitor: NetworkPathMonitoring {
        let stream: AsyncStream<NetworkPathStatus>
        let continuation: AsyncStream<NetworkPathStatus>.Continuation

        init() {
            (stream, continuation) = AsyncStream.makeStream(of: NetworkPathStatus.self)
        }

        nonisolated func statuses() -> AsyncStream<NetworkPathStatus> {
            stream
        }
    }

    /// 決めた状態で始めた回線の状態
    static func network(_ status: NetworkPathStatus) async -> NetworkStatus {
        let network = NetworkStatus()
        network.start(monitor: FixedNetworkPathMonitor(status: status))
        _ = await AsyncTestSupport.eventually { network.reachability != .unknown }
        return network
    }

    // MARK: - 判定

    /// 経路の状態から回線の状態を決める（オンデマンドの経路はオンラインとみなす）
    @Test(arguments: [
        (NetworkPathStatus.satisfied, NetworkReachability.online),
        (.unsatisfied, .offline),
        (.requiresConnection, .online)
    ])
    func reachabilityFromPathStatus(status: NetworkPathStatus, expected: NetworkReachability) {
        #expect(NetworkReachability(pathStatus: status) == expected)
    }

    /// バナーはオフラインと分かったときだけ。オンライン必須の操作は、分からないうちは止めない
    @Test
    func bannerAndOperationsByReachability() {
        #expect(NetworkReachability.offline.showsOfflineBanner)
        #expect(!NetworkReachability.online.showsOfflineBanner)
        #expect(!NetworkReachability.unknown.showsOfflineBanner)
        #expect(!NetworkReachability.offline.allowsOnlineOperations)
        #expect(NetworkReachability.online.allowsOnlineOperations)
        #expect(NetworkReachability.unknown.allowsOnlineOperations)
        #expect(throws: AppError(.offline)) {
            try NetworkReachability.offline.requireOnline()
        }
        #expect(throws: Never.self) {
            try NetworkReachability.unknown.requireOnline()
        }
    }

    /// オフラインの文言は通信エラーと分けて出し、もう一度で通る見込みのある失敗として扱う
    @Test
    func offlineErrorMessage() {
        let error = AppError(.offline)
        #expect(error.message == "オフラインのため操作できません")
        #expect(error.isRetryable)
        #expect(!error.isCancellation)
        #expect(AppError.Reason(serverReason: "app/offline") == nil)
    }

    /// 監視が流した状態を映す（同じ値が続いても替えない）
    @Test
    func networkStatusFollowsMonitor() async {
        let monitor = ControlledNetworkPathMonitor()
        let network = NetworkStatus()
        #expect(network.reachability == .unknown)
        network.start(monitor: monitor)
        monitor.continuation.yield(.unsatisfied)
        #expect(await AsyncTestSupport.eventually { network.isOffline })
        monitor.continuation.yield(.satisfied)
        #expect(await AsyncTestSupport.eventually { network.reachability == .online })
        monitor.continuation.finish()
    }

    /// `-network-offline` は UI テスト・撮影モードのときだけ効く
    @Test
    func launchArgumentForOffline() {
        let uiTesting = LaunchContext(arguments: ["app", "-uiTesting", "-network-offline"], environment: [:])
        #expect(uiTesting.networkOffline)
        let normal = LaunchContext(arguments: ["app", "-network-offline"], environment: [:])
        #expect(!normal.networkOffline)
        #expect(!LaunchContext(arguments: ["app", "-uiTesting"], environment: [:]).networkOffline)
    }

    // MARK: - オンライン必須の操作を止める窓口

    /// オフラインなら Callable を送らずに `offline` を投げる。オンラインなら送る
    @Test
    func functionsAreBlockedWhileOffline() async throws {
        let server = InMemoryServer.demo(.empty)
        let request = CreateRoomRequest(name: "年末の旅行", postLimit: 3, unlockRule: .all, deadline: nil, likeMode: .boost)
        let offline = OnlineRequiredFunctionsClient(base: server, network: await Self.network(.unsatisfied))
        let before = server.rooms.count
        await #expect(throws: AppError(.offline)) {
            _ = try await offline.createRoom(request)
        }
        #expect(server.rooms.count == before)

        let online = OnlineRequiredFunctionsClient(base: server, network: await Self.network(.satisfied))
        _ = try await online.createRoom(request)
        #expect(server.rooms.count == before + 1)
    }

    /// オフラインでも購読（閲覧）と `lastSeenAt` は通し、いいね・準備OKだけを止める
    @Test
    func directWritesAreBlockedButReadsPassWhileOffline() async throws {
        let server = RoomModelTests.makeServer()
        let repository = OnlineRequiredRoomRepository(base: server, network: await Self.network(.unsatisfied))
        await #expect(throws: AppError(.offline)) {
            try await repository.setLike(
                true,
                candidateID: RoomModelTests.shrine,
                roomID: DemoScenario.roomID,
                userID: DemoScenario.myUserID
            )
        }
        await #expect(throws: AppError(.offline)) {
            try await repository.setReady(true, roomID: DemoScenario.roomID, userID: DemoScenario.myUserID)
        }
        try await repository.markSeen(roomID: DemoScenario.roomID, userID: DemoScenario.myUserID)
        var iterator = repository.room(id: DemoScenario.roomID).makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.value??.id == DemoScenario.roomID)
    }

    /// 起動の窓口を回線の状態つきで作ると、オンライン必須の操作を止める窓口に包む
    @Test
    func dataServicesWrapWithNetwork() async {
        let network = await Self.network(.unsatisfied)
        let services = DataServices.make(
            connection: .disabled(.uiTesting),
            launch: LaunchContext(arguments: ["app", "-uiTesting"], environment: [:]),
            network: network
        )
        #expect(services.functions is OnlineRequiredFunctionsClient)
        #expect(services.rooms is OnlineRequiredRoomRepository)
        #expect(services.places is OnlineRequiredPlaceSearchService)
        let unwrapped = DataServices.make(connection: .disabled(.uiTesting), launch: LaunchContext(arguments: [], environment: [:]))
        #expect(!(unwrapped.functions is OnlineRequiredFunctionsClient))
    }

    // MARK: - 画面

    /// オフラインでいいね・準備OKを押したら、楽観的な表示を戻して「オフラインのため操作できません」を 1 回だけ出す
    @Test
    func likeAndReadyWhileOfflineShowOfflineToast() async throws {
        let server = RoomModelTests.makeServer()
        let network = await Self.network(.unsatisfied)
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = RoomModelTests.makeModel(OnlineRequiredRoomRepository(base: server, network: network), toasts: toasts)
        let observing = Task { await model.observe() }
        defer { observing.cancel() }
        #expect(await RoomModelTests.waitUntilLoaded(model))

        await model.toggleLike(RoomModelTests.shrine)
        #expect(model.pendingLikes.isEmpty)
        #expect(try RoomModelTests.row(model, RoomModelTests.shrine).likeStatus == .notLiked)
        #expect(toasts.current?.text == "オフラインのため操作できません")

        await model.toggleReady()
        #expect(model.pendingReady == nil)
        // 同じ文言は続けて並べない
        #expect(toasts.queue.pending.isEmpty)
        let likedBy = server.rooms[DemoScenario.roomID]?.candidates[RoomModelTests.shrine]?.likedBy ?? []
        #expect(!likedBy.contains(DemoScenario.myUserID))
    }
}
