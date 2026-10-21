//
//  FirebaseFirestoreGateway.swift
//  Dokogacha
//

@preconcurrency import FirebaseFirestore
import Foundation

/// Firestore の SDK を使う `FirestoreGateway`。`FirebaseApp.configure` の後でだけ作る。
///
/// SDK のリスナーは既定でメインスレッドに結果を返すので、`handler` は MainActor で呼ばれる。
final class FirebaseFirestoreGateway: FirestoreGateway {
    private let firestore: Firestore

    /// Firestore を受け取って作る（既定はアプリの既定のインスタンス。Emulator への接続は `FirebaseBootstrap` で済ませてある）
    init(firestore: Firestore = .firestore()) {
        self.firestore = firestore
    }

    func listenDocument(
        path: String,
        handler: @escaping (Result<FirestoreDocument?, ServerFailure>) -> Void
    ) -> any FirestoreListenerToken {
        let registration = firestore.document(path).addSnapshotListener { snapshot, error in
            guard let snapshot else {
                handler(.failure(Self.failure(from: error)))
                return
            }
            handler(.success(snapshot.exists ? Self.document(snapshot) : nil))
        }
        return FirebaseListenerToken(registration: registration)
    }

    func listenQuery(
        _ query: FirestoreQuerySpec,
        handler: @escaping (Result<[FirestoreDocument], ServerFailure>) -> Void
    ) -> any FirestoreListenerToken {
        let registration = makeQuery(query).addSnapshotListener { snapshot, error in
            guard let snapshot else {
                handler(.failure(Self.failure(from: error)))
                return
            }
            handler(.success(snapshot.documents.map(Self.document)))
        }
        return FirebaseListenerToken(registration: registration)
    }

    func update(path: String, fields: [String: FirestoreFieldUpdate]) async throws {
        let data: [String: Any] = fields.mapValues(Self.sdkValue)
        let reference = firestore.document(path)
        // SDK の非同期の API に `[String: Any]`（Sendable でない）を渡さないよう、完了のコールバックで待つ
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            reference.updateData(data) { error in
                if let error {
                    continuation.resume(throwing: Self.failure(from: error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 条件から SDK のクエリを作る
    private func makeQuery(_ query: FirestoreQuerySpec) -> Query {
        var result: Query = firestore.collection(query.collectionPath)
        for filter in query.filters {
            switch filter {
            case let .arrayContains(field, value):
                result = result.whereField(field, arrayContains: value)
            case let .isIn(field, values):
                result = result.whereField(field, in: values)
            }
        }
        if let order = query.order {
            result = result.order(by: order.field, descending: order.descending)
        }
        return result
    }

    /// スナップショットの中身を取り出す。
    ///
    /// 自分が書いたばかりの `serverTimestamp()`（`lastSeenAt` など）は、サーバーが確定するまで既定では nil になり、
    /// 必須の日時が無いドキュメントとして読めなくなる。`.estimate`（端末の時刻での見込み）にして読めるようにする
    private static func document(_ snapshot: DocumentSnapshot) -> FirestoreDocument {
        FirestoreDocument(id: snapshot.documentID, data: snapshot.data(with: .estimate) ?? [:])
    }

    /// 書き込む値を SDK の値にする
    private static func sdkValue(_ update: FirestoreFieldUpdate) -> Any {
        switch update {
        case let .bool(value):
            value
        case .serverTimestamp:
            FieldValue.serverTimestamp()
        case let .arrayUnion(values):
            FieldValue.arrayUnion(values)
        case let .arrayRemove(values):
            FieldValue.arrayRemove(values)
        }
    }

    /// SDK のエラーを `ServerFailure` にする（Firestore のエラーの番号は gRPC の番号と同じ）
    nonisolated private static func failure(from error: (any Error)?) -> ServerFailure {
        guard let error = error as NSError? else {
            return ServerFailure(code: .unknown)
        }
        if error.domain == FirestoreErrorDomain {
            return ServerFailure(code: ServerErrorCode(grpcCode: error.code))
        }
        if error.domain == NSURLErrorDomain {
            return ServerFailure(code: .unavailable)
        }
        return ServerFailure(code: .unknown)
    }
}

/// SDK の `ListenerRegistration` を包む札。MainActor に閉じ込めるので `Sendable` になる
@MainActor
final class FirebaseListenerToken: FirestoreListenerToken {
    private let registration: any ListenerRegistration

    /// SDK の札を包む
    init(registration: any ListenerRegistration) {
        self.registration = registration
    }

    func remove() {
        registration.remove()
    }
}
