//
//  InMemoryServer.swift
//  Dokogacha
//

import Foundation

/// メモリ上の擬似のサーバー。プレビュー・Unit テスト・`-uiTesting`・撮影モードで、Firebase の代わりに使う。
///
/// `AuthService`・`RoomRepository`・`FunctionsClient` のすべてを 1 つで持ち、Callable Functions と同じ検証・状態遷移
/// （backend の `rooms/`・`users/` と、05 の §4 のセキュリティルール）をメモリ上で行う。
/// 状態（`users`・`rooms`・`inviteCodes`・`signedInUserID`）を変えると、購読しているストリームに新しい値が流れる。
///
/// - 時刻（`clock`）・乱数（`randomIndex`）・ID（`makeID`）は注入する（テストで結果を決めるため）
/// - `signedInUserID` はこの端末でサインインしている人。Callable はこの人が呼んだものとして扱う。
///   ほかのメンバーの操作は、`perform(as:)` の中で Callable を呼ぶと再現できる
/// - まだ backend に無い Callable（`addCandidate` など）は `AppError(.notImplemented)` を投げる。backend のタスクで足すときに、ここにも足す
final class InMemoryServer {
    /// ルーム 1 つ分の状態（`rooms/{roomId}` とその下の `members`・`candidates`）
    nonisolated struct RoomRecord: Equatable, Sendable {
        /// ルーム
        var room: Room
        /// メンバー（鍵は uid）
        var members: [String: Member] = [:]
        /// 候補（鍵は候補の ID）
        var candidates: [String: Candidate] = [:]
    }

    /// `users/{uid}`
    var users: [String: UserProfile] = [:] {
        didSet { notifySubscribers() }
    }

    /// `rooms/{roomId}` とその下
    var rooms: [String: RoomRecord] = [:] {
        didSet { notifySubscribers() }
    }

    /// `inviteCodes/{code}`
    var inviteCodes: [String: InviteCodeEntry] = [:] {
        didSet { notifySubscribers() }
    }

    /// この端末でサインインしているユーザー（nil ならサインインしていない）
    var signedInUserID: String? {
        didSet { notifySubscribers() }
    }

    /// ルールで拒まれた直接の書き込み（古い順）。
    ///
    /// 直接の書き込みは Firestore と同じく送った時点で返り、拒まれても投げない（`RoomRepository`）ので、テストはここで確かめる
    var rejectedWrites: [AppError] = []

    /// 今の時刻（サーバーの時刻の代わり）
    let clock: () -> Date
    /// `0..<上限` の整数を返す乱数（招待コード・アバターの色）
    let randomIndex: (Int) -> Int
    /// ドキュメントの ID を作る
    let makeID: () -> String

    /// 購読ごとの、新しい値を流し直す処理
    private var subscribers: [UUID: () -> Void] = [:]
    /// `perform(as:)` の中で Callable を呼ぶ人
    private var actingUserID: String?

    /// 購読している数（購読をやめたら減る。テストでリスナーが外れたことを確かめる）
    var subscriberCount: Int {
        subscribers.count
    }

    /// 時刻・乱数・ID を注入して作る
    init(
        clock: @escaping () -> Date = { Date() },
        randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) },
        makeID: @escaping () -> String = { UUID().uuidString },
        signedInUserID: String? = nil
    ) {
        self.clock = clock
        self.randomIndex = randomIndex
        self.makeID = makeID
        self.signedInUserID = signedInUserID
    }

    /// ほかの人（`userID`）が Callable を呼んだものとして `body` を実行する（テスト・デモのデータを作るとき）
    func perform<Result>(as userID: String, _ body: () async throws -> Result) async rethrows -> Result {
        let previous = actingUserID
        actingUserID = userID
        defer { actingUserID = previous }
        return try await body()
    }

    /// Callable を呼んだ人（`perform(as:)` の中ならその人、そうでなければサインインしている人）。いなければ `unauthenticated`
    func callerID() throws -> String {
        guard let userID = actingUserID ?? signedInUserID else {
            throw Self.error(.unauthenticated)
        }
        return userID
    }

    // MARK: 購読

    /// 状態から読んだ値を購読する。値が変わったときだけ流す。`finishWhen` が true になる値を流したら終わる
    func observe<Value: Sendable & Equatable>(
        _ read: @escaping (InMemoryServer) -> Value,
        finishWhen shouldFinish: @escaping (Value) -> Bool = { _ in false }
    ) -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        var last: Value?
        subscribers[id] = { [weak self] in
            guard let self else {
                return
            }
            let value = read(self)
            guard value != last else {
                return
            }
            last = value
            continuation.yield(value)
            if shouldFinish(value) {
                subscribers[id] = nil
                continuation.finish()
            }
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        subscribers[id]?()
        return stream
    }

    /// `LiveUpdate` を流す購読。失敗（読めない・権限が無い）を流したら終わる（Firestore のリスナーと同じ）
    func subscribe<Value: Sendable & Equatable>(
        _ read: @escaping (InMemoryServer) -> LiveUpdate<Value>
    ) -> AsyncStream<LiveUpdate<Value>> {
        observe(read) { $0.error != nil }
    }

    /// 状態が変わったので、すべての購読に流し直す
    private func notifySubscribers() {
        for refresh in Array(subscribers.values) {
            refresh()
        }
    }

    // MARK: エラー

    /// backend の `appError(reason)` と同じ形のエラー（理由と、`errors.ts` の gRPC の分類）
    static func error(_ reason: AppError.Reason) -> AppError {
        AppError.server(ServerFailure(code: grpcCode(for: reason), reason: reason.rawValue))
    }

    /// セキュリティルールで拒まれたときのエラー（Firestore は理由を付けない）
    static let permissionDenied = AppError.server(ServerFailure(code: .permissionDenied))

    /// `errors.ts` の `APP_ERRORS` の gRPC の分類
    private static func grpcCode(for reason: AppError.Reason) -> ServerErrorCode {
        switch reason {
        case .unauthenticated:
            .unauthenticated
        case .invalidArgument:
            .invalidArgument
        case .profileRequired, .roomAlreadyDecided, .ownerCannotLeave, .cannotRemoveOwner:
            .failedPrecondition
        case .inviteCodeNotFound, .roomNotFound, .memberNotFound:
            .notFound
        case .roomFull:
            .resourceExhausted
        case .notRoomMember, .notRoomOwner, .permissionDenied:
            .permissionDenied
        case .inviteCodeUnavailable, .network, .serverUnavailable:
            .unavailable
        case .internal, .unreadableData, .notImplemented:
            .internal
        }
    }
}

// MARK: - AuthService

extension InMemoryServer: AuthService {
    var currentUserID: String? {
        signedInUserID
    }

    func userIDChanges() -> AsyncStream<String?> {
        observe { $0.signedInUserID }
    }

    func signInAnonymously() async throws -> String {
        if let signedInUserID {
            return signedInUserID
        }
        let userID = "user-\(makeID())"
        signedInUserID = userID
        return userID
    }

    func profile(userID: String) -> AsyncStream<LiveUpdate<UserProfile?>> {
        // ルール: 自分の `users/{uid}` だけを読める
        subscribe { server in
            guard server.signedInUserID == userID else {
                return .failure(Self.permissionDenied)
            }
            return .value(server.users[userID])
        }
    }

    func saveDisplayName(_ displayName: String) async throws -> SaveProfileResponse {
        try await saveProfile(SaveProfileRequest(displayName: displayName))
    }

    func linkWithApple(_ credential: AppleIDCredential) async throws {
        throw AppError(.notImplemented)
    }

    /// サーバー側でサインアウトされたことを再現する（ユーザーの削除・トークンの更新の失敗）
    func simulateSignOut() {
        signedInUserID = nil
    }
}
