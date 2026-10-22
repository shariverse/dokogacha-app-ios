//
//  DGDestinationTicketTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 行き先きっぷの VoiceOver のラベル（1 つにまとめたもの）を確かめる
struct DGDestinationTicketTests {
    /// 2026/10/21 の日本時間 13 時
    static let drawnAt = Date(timeIntervalSince1970: 1_792_555_200)
    static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    /// 帯・行き先・エリアとカテゴリ・ひとこと・下段・抽選日を上から 1 つに読む
    @Test
    func accessibilityTextReadsWholeTicket() {
        let ticket = DGDestinationTicket(
            roomName: "11月の日帰り旅行",
            destinationName: "高尾山",
            meta: "東京・八王子市 · 自然",
            category: .nature,
            note: "紅葉シーズンにちょうどいい",
            author: .member("みさき"),
            likeCount: 4,
            percent: 16,
            drawnAt: Self.drawnAt
        )
        #expect(ticket.accessibilityText(timeZone: Self.tokyo) == "行き先きっぷ、11月の日帰り旅行。高尾山 ゆき。東京・八王子市 · 自然。紅葉シーズンにちょうどいい。"
            + "投稿 みさきさん、いいね 4、当選確率 16%。10月21日に決定")
    }

    /// ひとことが無ければ読まない。自分の投稿は「あなた」
    @Test
    func accessibilityTextSkipsEmptyNote() {
        let ticket = DGDestinationTicket(
            roomName: "ごはん会",
            destinationName: "横浜中華街",
            meta: "神奈川・横浜市 · グルメ",
            category: .food,
            note: "",
            author: .me,
            likeCount: 0,
            percent: 5,
            drawnAt: Self.drawnAt
        )
        #expect(ticket.accessibilityText(timeZone: Self.tokyo) == "行き先きっぷ、ごはん会。横浜中華街 ゆき。神奈川・横浜市 · グルメ。投稿 あなた、いいね 0、当選確率 5%。10月21日に決定")
    }
}
