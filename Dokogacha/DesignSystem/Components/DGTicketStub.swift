//
//  DGTicketStub.swift
//  Dokogacha
//
//  思い出のきっぷ（`04_design_system.md` の §4 の TicketStub・03 の S-02）。終わったルームを 1 件ずつ出す。
//

import SwiftUI

/// 終わったルームのきっぷの半券。押すと結果画面（閲覧のみ）へ進む。
///
/// 白・線 2・角丸 16。左に「ルーム名 · 日付」「◯◯ ゆき」「外れた候補 N件は次のルームで使えます」、
/// 右端の 78pt を点線（2pt `line.dashedStrong`）で区切り、中央に「済」のハンコ（直径 50）を押す。
/// 外れた候補が 0 件のときは、その行を出さない。
struct DGTicketStub: View {
    /// 角丸
    private static let cornerRadius: CGFloat = DGRadius.md
    /// 右端の半券の幅
    private static let stubWidth: CGFloat = 78
    /// 行き先の名前の大きさ
    private static let destinationSize: CGFloat = 20
    /// 「ゆき」の大きさ
    private static let suffixSize: CGFloat = 13

    /// ルーム名
    let roomName: String
    /// 日付（行き先が決まった日）
    let date: Date
    /// 当選した場所の名前
    let destinationName: String
    /// 外れた候補の数（次のルームに持ち込める候補）
    let leftoverCount: Int
    /// 押したときの処理（結果画面へ進む）
    let action: () -> Void

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        Button(action: action) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: DGSpacing.s4) {
                    Text(verbatim: "\(roomName) · \(DGDateText.monthDay(date, timeZone: timeZone))")
                        .font(.dg(.bodyCaption))
                        .foregroundStyle(Color.dgTextSecondary)
                    destination
                    if leftoverCount > 0 {
                        Text("外れた候補 \(leftoverCount)件は次のルームで使えます")
                            .font(.dg(.bodyCaption))
                            .foregroundStyle(Color.dgTextSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DGSpacing.s14)
                .padding(.horizontal, DGSpacing.s16)
                DGDashedLine(color: .dgLineDashedStrong, axis: .vertical)
                DGStamp("済")
                    .frame(width: Self.stubWidth)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.dgSurfaceCard, in: shape)
            .overlay(shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular))
            .contentShape(shape)
        }
        .buttonStyle(.dgBare)
    }

    /// 「◯◯ ゆき」（場所名は見出し 20、「ゆき」は 13）
    private var destination: some View {
        let name = Text(verbatim: destinationName)
            .font(.dgDisplay(Self.destinationSize, relativeTo: .title3))
        return Text("\(name) ゆき")
            .font(.dgDisplay(Self.suffixSize, relativeTo: .title3))
            .foregroundStyle(Color.dgInk)
    }
}

#Preview("TicketStub 状態ごと") {
    VStack(spacing: DGSpacing.s10) {
        DGTicketStub(
            roomName: "夏の日帰り",
            date: Date(timeIntervalSince1970: 1_787_529_600),
            destinationName: "城ヶ島",
            leftoverCount: 4
        ) {}
        DGTicketStub(
            roomName: "サークルの合宿",
            date: Date(timeIntervalSince1970: 1_792_540_800),
            destinationName: "チームラボプラネッツ TOKYO",
            leftoverCount: 0
        ) {}
    }
    .padding(DGSpacing.screenX)
    .frame(maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("TicketStub 文字を最大") {
    ScrollView {
        DGTicketStub(
            roomName: "夏の日帰り",
            date: Date(timeIntervalSince1970: 1_787_529_600),
            destinationName: "城ヶ島",
            leftoverCount: 4
        ) {}
        .padding(DGSpacing.screenX)
    }
    .background(Color.dgBgBase)
    .dynamicTypeSize(.accessibility5)
}
