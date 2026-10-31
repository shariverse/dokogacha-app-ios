//
//  TicketShareImage.swift
//  Dokogacha
//

import SwiftUI

/// 「きっぷを共有」で共有シートに渡す画像（02 の §6.3「行き先きっぷを画像にして共有シートで送る（`ImageRenderer` で生成）。
/// 画像にはアプリ名と App Store のURL（仮）を入れる」・04 の §4「このきっぷを 3倍の解像度で書き出し、下に
/// 『ドコガチャ｜友達旅行・おでかけの行き先ガチャ』を追加する」）。
///
/// 画像は「きっぷを共有」が押されたときに作り、共有シート（`ActivityShareSheet`）に渡す（画面を描くたびに書き出さない）。
nonisolated struct TicketShareImage: Sendable {
    /// きっぷの値
    let ticket: ResultTicket

    /// 共有する画像（書き出せなければ nil）
    @MainActor
    func image() -> UIImage? {
        Self.renderer(for: ticket).uiImage
    }

    /// 共有する画像の PNG（書き出せなければ nil）
    @MainActor
    func pngData() -> Data? {
        image()?.pngData()
    }

    /// 画像を書き出す `ImageRenderer`（3 倍の解像度・幅は `TicketShareCard.width`）
    @MainActor
    static func renderer(for ticket: ResultTicket) -> ImageRenderer<TicketShareCard> {
        let renderer = ImageRenderer(content: TicketShareCard(ticket: ticket))
        renderer.scale = TicketShareCard.scale
        renderer.proposedSize = ProposedViewSize(width: TicketShareCard.width, height: nil)
        return renderer
    }
}

/// 共有画像の中身（きっぷと、その下のアプリ名・App Store の URL）。
///
/// 端末の文字の大きさによらず同じ画像にするため、Dynamic Type は標準の大きさに固定する。ハンコは押した後の形で止める
struct TicketShareCard: View {
    /// 画像の幅（pt。03 の基準の iPhone 15 の画面の幅）
    static let width: CGFloat = 390
    /// 書き出す解像度の倍率（04 の §4「3倍の解像度」）
    static let scale: CGFloat = 3

    /// きっぷの値
    let ticket: ResultTicket

    var body: some View {
        VStack(spacing: DGSpacing.s14) {
            ResultTicketView(ticket: ticket, stampAnimatesIn: false)
            VStack(spacing: DGSpacing.s4) {
                Text("ドコガチャ｜友達旅行・おでかけの行き先ガチャ")
                    .font(.dg(.bodyTitle))
                    .foregroundStyle(Color.dgInk)
                Text(verbatim: DomainConstants.Web.appStoreURL)
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(DGSpacing.s24)
        .frame(width: Self.width)
        .background(Color.dgBgBase)
        .dynamicTypeSize(.large)
    }
}

/// `ResultTicket` を行き先きっぷの部品（`DGDestinationTicket`）で描く（画面と共有画像で同じ見た目にする）
struct ResultTicketView: View {
    /// きっぷの値
    let ticket: ResultTicket
    /// 表示したときにハンコを押す動きをするか
    var stampAnimatesIn = false
    /// ハンコの押し具合（0〜1。演出の時刻に合わせて外から決めるとき。`ResultRevealStage`）
    var stampProgress: Double?

    var body: some View {
        let style = DGCategoryStyle.of(ticket.category)
        DGDestinationTicket(
            roomName: ticket.roomName,
            destinationName: ticket.destinationName,
            meta: ticket.area.isEmpty ? String(localized: style.label) : "\(ticket.area) · \(String(localized: style.label))",
            category: style,
            note: ticket.note,
            author: ticket.author,
            likeCount: ticket.likeCount,
            percent: ticket.percent,
            drawnAt: ticket.drawnAt,
            stampAnimatesIn: stampAnimatesIn,
            stampProgress: stampProgress
        )
    }
}
