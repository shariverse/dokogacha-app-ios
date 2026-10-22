//
//  HomeMemoryTickets.swift
//  Dokogacha
//

import SwiftUI

/// ホーム（S-02）の「思い出のきっぷ」の一覧（03 の S-02 の 3・02 の §6.5 F-44）。見出しと空の表示は `HomeView` が出す。
///
/// 終了したルームを新しい順に TicketStub（ルーム名・日付、「◯◯ ゆき」、「外れた候補 N件は次のルームで使えます」、「済」のハンコ）で並べる。
/// 最初は 5 枚までで、6 枚目からは「すべて見る」を押すとその場に続けて出す（03 に「すべて見る」の行き先の画面が無いため、一覧を広げる）。
/// きっぷを押すと S-14 結果（閲覧のみ。`closed` のルームなので引き直し・決定は出ない）を開く（03 の §2）。
/// 一覧や当選した候補がまだ届いていないときは、きっぷの形を保った読み込み中の表示にする（03 の §3）。
struct HomeMemoryTickets: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 「すべて見る」
        static let showAll = "home.memories.showAll"

        /// 思い出のきっぷ
        static func ticket(_ roomID: String) -> String {
            "home.memory.\(roomID)"
        }
    }

    /// ホームの状態（思い出のきっぷの購読は `HomeModel.observe()` が行う）
    let model: HomeModel
    /// 行き先を開く（S-14 をフルスクリーンカバーで出す）
    let navigate: (AppRoute) -> Void

    var body: some View {
        if model.isMemoriesLoading {
            loadingTicket
        } else {
            VStack(spacing: DGSpacing.s10) {
                ForEach(model.visibleMemoryTickets) { ticket in
                    ticketStub(ticket)
                }
                if model.hasMoreMemories {
                    DGButton("すべて見る", kind: .secondary) {
                        model.showAllMemoriesTapped()
                    }
                    .accessibilityIdentifier(Identifier.showAll)
                }
            }
        }
    }

    /// 思い出のきっぷ 1 枚。押すと S-14 結果（閲覧のみ）へ
    private func ticketStub(_ ticket: MemoryTicket) -> some View {
        DGTicketStub(
            roomName: ticket.roomName,
            date: ticket.date,
            destinationName: ticket.destinationName,
            leftoverCount: ticket.leftoverCount
        ) {
            navigate(.result(roomID: ticket.id, drawID: ticket.drawID))
        }
        .accessibilityHint(Text("行き先きっぷを開きます"))
        .accessibilityIdentifier(Identifier.ticket(ticket.id))
    }

    /// 一覧・当選した候補が届くまでの、きっぷの形を保った読み込み中の表示
    private var loadingTicket: some View {
        DGTicketStub(
            roomName: String(localized: "読み込み中"),
            date: Date(timeIntervalSince1970: 0),
            destinationName: String(localized: "読み込み中"),
            leftoverCount: 0
        ) {}
        .redacted(reason: .placeholder)
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("読み込み中"))
    }
}
