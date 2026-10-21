//
//  FirebaseFirestoreGateway.swift
//  Dokogacha
//

@preconcurrency import FirebaseFirestore
import Foundation
import os

/// Firestore の SDK を使う `FirestoreGateway`。`FirebaseApp.configure` の後でだけ作る。
///
/// SDK のリスナーは既定でメインスレッドに結果を返すので、`handler` は MainActor で呼ばれる。
final class FirebaseFirestoreGateway: FirestoreGateway {
    /// サーバーで拒まれた書き込みを残すログ（完了は待たないので、画面には出さない）
    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "Firestore")

    private let firestore: Firestore

    /// Firestore を受け取って作る（既定はアプリの既定のインスタンス。Emulator への接続は `FirebaseBootstrap` で済ませてある）
    init(firestore: Firestore = .firestore()) {
        self.firestore = firestore
    }

    func listenDocument(
        path: String,
        includeMetadataChanges: Bool,
        handler: @escaping (Result<FirestoreDocumentSnapshot, ServerFailure>) -> Void
    ) -> any FirestoreListenerToken {
        let reference = firestore.document(path)
        let registration = reference.addSnapshotListener(includeMetadataChanges: includeMetadataChanges) { snapshot, error in
            guard let snapshot else {
                handler(.failure(Self.failure(from: error)))
                return
            }
            handler(.success(FirestoreDocumentSnapshot(
                document: snapshot.exists ? Self.document(snapshot) : nil,
                isFromCache: snapshot.metadata.isFromCache
            )))
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

    func update(path: String, fields: [String: FirestoreFieldUpdate]) {
        let data: [String: Any] = fields.mapValues(Self.sdkValue)
        // 完了は待たない（オフラインでは、つながるまで呼ばれない）。拒まれたらログに残す
        firestore.document(path).updateData(data) { error in
            guard let error else {
                return
            }
            let failure = Self.failure(from: error)
            Self.logger.error("直接の書き込みが拒まれた: \(path, privacy: .private) code=\(failure.code.rawValue)")
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
            return ServerFailure(code: error.code == NSURLErrorCancelled ? .cancelled : .unavailable)
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
