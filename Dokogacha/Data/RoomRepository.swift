//
//  RoomRepository.swift
//  Dokogacha
//

import Foundation

/// ルーム・メンバー・候補の購読と、クライアントから直接書いてよい項目の書き込み（05 の §4・§6）。
///
/// 画面の Model はこの protocol だけを見る。Firebase の実装は `FirestoreRoomRepository`
/// （`addSnapshotListener` を `AsyncStream` にしたもの）、プレビュー・Unit テスト・`-uiTesting` では `InMemoryServer`。
///
/// 購読は `Task` の中で `for await` で読み、`Task` を cancel する（画面が消える）とリスナーを外す。
/// 整合性が要る書き込み（作成・参加・候補の追加など）は `FunctionsClient` を通し、ここでは
/// 05 の §4 の「自分の準備OK」「いいね」「lastSeenAt」だけを書く。
///
/// 直接の書き込み（`setReady`・`setLike`・`markSeen`）は、**送った時点で返る**（サーバーの完了は待たない）:
/// - Firestore はローカルのキャッシュに書いた時点で購読に新しい値を流し、つながったらサーバーに送る。
///   完了を待つとオフラインの間は戻らず、cancel にも反応しないので、キャッシュに書けたら成功とみなす
/// - サーバーで拒まれたとき（ルールで permission-denied。例: 引いた後の準備OK）は投げない。SDK がキャッシュの値を元に戻し、
///   購読に元の値が流れるので、画面は購読の値をそのまま映せばよい（失敗はログに残す）
/// - 投げるのは、送る前に分かる失敗だけ（サーバーに接続できない構成の `UnavailableServer` など）
protocol RoomRepository {
    /// ホームの進行中のルーム（`open`・`unlocked`・`drawn`）を、作成日時の新しい順に購読する（05 の §6）
    func activeRooms(userID: String) -> AsyncStream<LiveUpdate<[Identified<Room>]>>

    /// ルームを購読する。
    ///
    /// 読めるのはメンバーだけ（セキュリティルール）。無いルーム（招待のリンクの先が消えたなど）を購読すると、ルールが
    /// `memberIds` を読めずに permission-denied になり、`.failure` を流して終わる（画面は「ルームが見つからない」とまとめて扱う）。
    /// 購読している間にルームが消えたときは nil が流れることがある
    func room(id roomID: String) -> AsyncStream<LiveUpdate<Identified<Room>?>>

    /// ルームのメンバー（ID は uid）を、参加の早い順に購読する
    func members(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Member>]>>

    /// ルームの候補を、投稿の新しい順に購読する（F-12）
    func candidates(roomID: String) -> AsyncStream<LiveUpdate<[Identified<Candidate>]>>

    /// 自分の準備OKを変える（F-30。`open`・`unlocked` のときだけ）
    func setReady(_ ready: Bool, roomID: String, userID: String) async throws

    /// 他人の候補へのいいねを付ける・外す（F-20。`likedBy` に自分の uid を足す・取り除く）
    func setLike(_ liked: Bool, candidateID: String, roomID: String, userID: String) async throws

    /// 自分がルームを最後に見た日時（`lastSeenAt`）をサーバーの今の時刻にする（F-12 の NEW の判定）
    func markSeen(roomID: String, userID: String) async throws
}
