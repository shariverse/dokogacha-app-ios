//
//  DrawReplay.swift
//  Dokogacha
//

import Foundation

/// ほかの人がガチャを回したときに、S-07 から S-13 を開いて同じ演出を再生するかの判定（02 の §6.2・F-41）。
///
/// 画面を出している間に、ルームが `drawn` でない状態から `drawn` に変わり、その抽選の演出をまだ見ていなければ再生する。
/// 開いたときにすでに `drawn` のルーム（アプリを開いていなかった人）は再生しない（結果の画面を直接出す。03 の §2・タスク 28）
nonisolated enum DrawReplay {
    /// 再生する抽選の ID。再生しないなら nil
    /// - Parameters:
    ///   - previous: 出していたルームの状態（まだ届いていなければ nil）
    ///   - room: 届いたルーム
    ///   - hasSeen: その抽選の演出を、この端末で見終えたか
    static func drawID(previous: RoomStatus?, room: Room, hasSeen: (String) -> Bool) -> String? {
        guard let previous, previous != .drawn, room.status == .drawn,
              let drawID = room.currentDrawId, !drawID.isEmpty, !hasSeen(drawID) else {
            return nil
        }
        return drawID
    }

    /// S-07 を開いたときに、結果の画面（S-14）を自動で出す抽選の ID（03 の §2「ルームが drawn の状態でルーム画面を開いたら、結果画面を自動で表示する」・
    /// 02 の §6.2「アプリを開いていなかった人は、次に開いたときに結果画面を直接表示する」）。出さないなら nil。
    ///
    /// 画面を開いて最初に届いたルーム（`previous` が nil）が `drawn`・`closed`（閲覧のみ）のときだけ出す。
    /// 画面を出している間に `drawn` になったときは `drawID(previous:room:hasSeen:)` で S-13 の演出を再生する（その後で S-14 に進む）
    /// - Parameters:
    ///   - previous: 出していたルームの状態（まだ届いていなければ nil）
    ///   - room: 届いたルーム
    static func resultDrawID(previous: RoomStatus?, room: Room) -> String? {
        guard previous == nil, room.status == .drawn || room.status == .closed,
              let drawID = room.currentDrawId, !drawID.isEmpty else {
            return nil
        }
        return drawID
    }
}
