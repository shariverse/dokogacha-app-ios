//
//  FirestoreGateway.swift
//  Dokogacha
//

import Foundation

/// Firestore の SDK の窓口。購読（`addSnapshotListener`）と更新（`updateData`）だけを持つ。
///
/// `FirestoreRoomRepository` はこの protocol を通して SDK を使う。テストでは擬似の実装に差し替えて、
/// スナップショットを流したときの変換と、購読をやめたときにリスナーが外れることを確かめる。
/// 値は SDK のまま（`[String: Any]`）渡し、モデルへの変換（`Timestamp` → `Date` を含む）は `FirestoreDecoding` が行う。
protocol FirestoreGateway {
    /// ドキュメントを購読する。ドキュメントが無いときは nil を渡す。失敗したら `ServerFailure` を渡す（SDK はその後リスナーを外す）
    func listenDocument(
        path: String,
        handler: @escaping (Result<FirestoreDocument?, ServerFailure>) -> Void
    ) -> any FirestoreListenerToken

    /// クエリを購読する。失敗したら `ServerFailure` を渡す
    func listenQuery(
        _ query: FirestoreQuerySpec,
        handler: @escaping (Result<[FirestoreDocument], ServerFailure>) -> Void
    ) -> any FirestoreListenerToken

    /// ドキュメントのフィールドを更新する。失敗したら `ServerFailure` を投げる
    func update(path: String, fields: [String: FirestoreFieldUpdate]) async throws
}

/// 購読を外すための札（SDK の `ListenerRegistration`）。
///
/// `AsyncStream` の `onTermination`（どのスレッドからも呼ばれる）から外せるよう `Sendable` にし、
/// 外すのは MainActor に戻ってから行う（`remove` は MainActor で呼ぶ）。
@MainActor
protocol FirestoreListenerToken: Sendable {
    /// リスナーを外す
    func remove()
}

/// Firestore のドキュメント 1 つ（中身は SDK の値のまま。日時は `Timestamp`）
struct FirestoreDocument {
    /// ドキュメントの ID
    let id: String
    /// ドキュメントの中身
    let data: [String: Any]
}

/// Firestore のクエリの条件（このアプリで使う形だけ）
nonisolated struct FirestoreQuerySpec: Equatable, Sendable {
    /// 絞り込みの条件
    nonisolated enum Filter: Equatable, Sendable {
        /// 配列のフィールドが値を含む（`array-contains`）
        case arrayContains(field: String, value: String)
        /// フィールドが値のどれか（`in`）
        case isIn(field: String, values: [String])
    }

    /// 並べ替えの条件
    nonisolated struct Order: Equatable, Sendable {
        /// 並べ替えるフィールド
        var field: String
        /// 降順か
        var descending: Bool
    }

    /// コレクションのパス
    var collectionPath: String
    /// 絞り込みの条件（すべてを満たすもの）
    var filters: [Filter] = []
    /// 並べ替えの条件
    var order: Order?
}

/// クライアントから直接書くフィールドの値（05 の §4 の「準備OK」「いいね」「lastSeenAt」に要るものだけ）
nonisolated enum FirestoreFieldUpdate: Equatable, Sendable {
    /// 真偽値
    case bool(Bool)
    /// サーバーの今の時刻（`FieldValue.serverTimestamp()`。ルールが `request.time` と比べる）
    case serverTimestamp
    /// 配列に値を足す（`FieldValue.arrayUnion`）
    case arrayUnion([String])
    /// 配列から値を取り除く（`FieldValue.arrayRemove`）
    case arrayRemove([String])
}

/// Firestore のパス（05 の §3）
nonisolated enum FirestorePath {
    /// `users`
    static let users = "users"
    /// `rooms`
    static let rooms = "rooms"

    /// `users/{uid}`
    static func user(_ userID: String) -> String {
        "\(users)/\(userID)"
    }

    /// `rooms/{roomId}`
    static func room(_ roomID: String) -> String {
        "\(rooms)/\(roomID)"
    }

    /// `rooms/{roomId}/members`
    static func members(_ roomID: String) -> String {
        "\(room(roomID))/members"
    }

    /// `rooms/{roomId}/members/{uid}`
    static func member(_ userID: String, roomID: String) -> String {
        "\(members(roomID))/\(userID)"
    }

    /// `rooms/{roomId}/candidates`
    static func candidates(_ roomID: String) -> String {
        "\(room(roomID))/candidates"
    }

    /// `rooms/{roomId}/candidates/{candidateId}`
    static func candidate(_ candidateID: String, roomID: String) -> String {
        "\(candidates(roomID))/\(candidateID)"
    }

    /// ドキュメントの ID の最大の長さ（backend の `MAX_ID_LENGTH`）
    static let maxDocumentIDLength = 128

    /// ドキュメントの ID として使えるか（backend の `requireDocumentId` と同じ条件）。
    ///
    /// 空でない・長すぎない・`/` を含まない・`.`・`..` でない・`__…__` でない。
    /// 入力の ID でパスを組み立てるので、別のコレクションを指さないように確かめる。
    static func isValidDocumentID(_ id: String) -> Bool {
        let reserved = id.count >= 4 && id.hasPrefix("__") && id.hasSuffix("__")
        return !id.isEmpty && id.utf16.count <= maxDocumentIDLength && !id.contains("/") && id != "." && id != ".." && !reserved
    }
}
