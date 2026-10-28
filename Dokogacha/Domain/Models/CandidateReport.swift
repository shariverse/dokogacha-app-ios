//
//  CandidateReport.swift
//  Dokogacha
//

import Foundation

/// 投稿の報告（`reports/{id}`。05 の §5 の `reportCandidate`・F-14）。Functions だけが作る。
nonisolated struct CandidateReport: Codable, Sendable, Equatable {
    /// 報告された候補のルームの ID
    var roomId: String
    /// 報告された候補の ID
    var candidateId: String
    /// 報告した人の uid
    var reporterId: String
    /// 理由
    var reason: ReportReason
    /// 報告した日時
    var createdAt: Date
}

/// 報告の理由（F-14 の「不適切な内容／スパム／その他」）。`rawValue` は Firestore の `reason` の値。
nonisolated enum ReportReason: String, CaseIterable, Codable, Sendable {
    /// 不適切な内容
    case inappropriate
    /// スパム
    case spam
    /// その他
    case other
}
