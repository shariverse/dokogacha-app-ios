//
//  FirestoreRoomRepository+PastIdeas.swift
//  Dokogacha
//

import Foundation

extension FirestorePath {
    /// `users/{uid}/pastIdeas`
    static func pastIdeas(_ userID: String) -> String {
        "\(user(userID))/pastIdeas"
    }
}

extension FirestoreRoomRepository {
    /// 自分の過去のアイデアを、元のルームが終了した日時の新しい順に購読する（05 の §3 のインデックス `sourceClosedAt desc`）。
    ///
    /// 単一のフィールドの並べ替えなので、Firestore が自動で作るインデックスで足りる
    func pastIdeas(userID: String) -> AsyncStream<LiveUpdate<[Identified<PastIdea>]>> {
        let query = FirestoreQuerySpec(
            collectionPath: FirestorePath.pastIdeas(userID),
            order: .init(field: "sourceClosedAt", descending: true)
        )
        return FirestoreSubscription.query(query, gateway: gateway) { FirestoreDecoding.list($0, FirestoreDecoding.pastIdea) }
    }
}
