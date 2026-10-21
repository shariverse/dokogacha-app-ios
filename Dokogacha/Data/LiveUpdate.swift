//
//  LiveUpdate.swift
//  Dokogacha
//

import Foundation

/// 購読（Firestore のリアルタイムの更新・擬似のサーバーの変更）で流れてくる出来事。
///
/// 購読は `AsyncStream<LiveUpdate<Value>>` で返す。値が変わるたびに `.value` が流れ、
/// 購読できなくなったら（ルームから外されて読めなくなった・通信が切れたなど）`.failure` が流れて終わる。
/// ドキュメントを読めなかったとき（知らない状態の値など）は `.failure(.unreadableData)` を流し、購読は続ける。
///
/// エラーを `AsyncThrowingStream` で投げずに値で流すのは、iOS 17 では `AsyncThrowingStream` のエラーの型を
/// `AppError` に絞れず、画面が毎回 `any Error` を変換することになるため。
nonisolated enum LiveUpdate<Value: Sendable>: Sendable {
    /// いまの値
    case value(Value)
    /// 購読が失敗した
    case failure(AppError)

    /// 値（失敗なら nil）
    var value: Value? {
        if case let .value(value) = self {
            return value
        }
        return nil
    }

    /// 失敗（値なら nil）
    var error: AppError? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }
}

nonisolated extension LiveUpdate: Equatable where Value: Equatable {}
