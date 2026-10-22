//
//  InMemoryServer+PastIdeas.swift
//  Dokogacha
//
//  擬似のサーバーの過去のアイデア（`users/{uid}/pastIdeas`。F-13）の購読。
//  読めるのは本人だけ（backend の `firestore.rules` の `match /pastIdeas/{id} { allow read: if request.auth.uid == uid; }`）。
//

import Foundation

extension InMemoryServer {
    /// 自分の過去のアイデアを、元のルームが終了した日時の新しい順（同じなら ID の降順）に購読する。本人でなければ権限のエラーで終わる
    func pastIdeas(userID: String) -> AsyncStream<LiveUpdate<[Identified<PastIdea>]>> {
        subscribe { server in
            guard server.signedInUserID == userID else {
                return .failure(Self.permissionDenied)
            }
            let ideas = (server.pastIdeas[userID] ?? [:])
                .map { Identified(id: $0.key, value: $0.value) }
                .sorted { ($0.sourceClosedAt, $0.id) > ($1.sourceClosedAt, $1.id) }
            return .value(ideas)
        }
    }
}
