//
//  FirestoreDecoding.swift
//  Dokogacha
//

@preconcurrency import FirebaseFirestore
import Foundation
import os

/// Firestore のドキュメント（SDK の値）を、ドメインのモデル（05 の §3）にする。
///
/// - 日時は SDK の `Timestamp` を `Date` にする（`Firestore.Decoder` の既定の `.timestamp`）
/// - **知らない列挙の値**（backend でカテゴリや状態をあとから増やし、古いアプリが受け取ったとき）は、
///   安全な既定に落とせる項目は既定に落としてログに残す（カテゴリ → `town`、役割 → `member`）。
///   落とせない項目（ルームの状態・解禁の条件・いいねの効き方・引き直しの状態）は、そのドキュメントを読めないものとして
///   `FirestoreDecodingError` を投げる。一覧の購読ではそのドキュメントだけを読み飛ばし、ほかのドキュメントは読める
enum FirestoreDecoding {
    private static let logger = Logger(subsystem: "jp.shilokuma.Dokogacha", category: "FirestoreDecoding")

    /// 知らない値を既定に落とす項目
    private struct Fallback {
        /// フィールドの名前
        let field: String
        /// 知っている値
        let knownValues: Set<String>
        /// 知らない値のときに使う値
        let fallback: String
    }

    /// 候補のカテゴリ（02 の §3.1「対応しきれない場合は town にする」と同じ考えで、知らないカテゴリは街歩きにする）
    private static let categoryFallback = Fallback(
        field: "category",
        knownValues: Set(PlaceCategory.allCases.map(\.rawValue)),
        fallback: PlaceCategory.fallback.rawValue
    )

    /// メンバーの役割（知らない役割は、権限の小さい `member` にする）
    private static let roleFallback = Fallback(
        field: "role",
        knownValues: Set(MemberRole.allCases.map(\.rawValue)),
        fallback: MemberRole.member.rawValue
    )

    /// `rooms/{roomId}` を読む
    static func room(_ document: FirestoreDocument) throws -> Identified<Room> {
        try decode(Room.self, document)
    }

    /// `rooms/{roomId}/members/{uid}` を読む
    static func member(_ document: FirestoreDocument) throws -> Identified<Member> {
        try decode(Member.self, document, fallbacks: [roleFallback])
    }

    /// `rooms/{roomId}/candidates/{candidateId}` を読む
    static func candidate(_ document: FirestoreDocument) throws -> Identified<Candidate> {
        try decode(Candidate.self, document, fallbacks: [categoryFallback])
    }

    /// `users/{uid}` を読む
    static func userProfile(_ document: FirestoreDocument) throws -> UserProfile {
        try decode(UserProfile.self, document).value
    }

    /// 一覧を読む。読めないドキュメントは読み飛ばしてログに残す（1 件のせいで一覧ごと読めなくならないように）
    static func list<Value>(
        _ documents: [FirestoreDocument],
        _ read: (FirestoreDocument) throws -> Identified<Value>
    ) -> [Identified<Value>] {
        documents.compactMap { document in
            do {
                return try read(document)
            } catch {
                let reason = String(describing: error)
                logger.error("読めないドキュメントを読み飛ばす: \(document.id, privacy: .public) \(reason, privacy: .public)")
                return nil
            }
        }
    }

    /// 知らない値を既定に落としてから、モデルにする
    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        _ document: FirestoreDocument,
        fallbacks: [Fallback] = []
    ) throws -> Identified<Value> {
        var data = document.data
        for fallback in fallbacks {
            if let value = data[fallback.field] as? String, !fallback.knownValues.contains(value) {
                let field = fallback.field
                logger.notice("知らない値を既定に落とす: \(document.id, privacy: .public) \(field, privacy: .public)=\(value, privacy: .public)")
                data[fallback.field] = fallback.fallback
            }
        }
        do {
            let value = try Firestore.Decoder().decode(Value.self, from: data)
            return Identified(id: document.id, value: value)
        } catch {
            throw FirestoreDecodingError(documentID: document.id, underlying: String(describing: error))
        }
    }
}

/// Firestore のドキュメントをモデルにできなかった（必須の項目が無い・知らない状態の値など）
nonisolated struct FirestoreDecodingError: Error, Equatable, Sendable {
    /// ドキュメントの ID
    let documentID: String
    /// SDK の Decoder のエラーの説明（ログ用）
    let underlying: String
}
