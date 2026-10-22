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
}
