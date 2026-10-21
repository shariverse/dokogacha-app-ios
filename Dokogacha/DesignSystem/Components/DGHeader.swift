//
//  DGHeader.swift
//  Dokogacha
//
//  画面のヘッダー（03 の §3「ナビゲーションバーは標準のものを使わず、各画面の上部にヘッダーを置く」）。
//

import SwiftUI

/// 画面の上部のヘッダー。左に戻るボタン（44×44）、続けてタイトル（`display.header`）、右端に任意の要素を置く。
///
/// 高さは 60（03 の §3）。文字を大きくしたときはタイトルが折り返して高さが伸びる。
/// 標準のナビゲーションバーを隠した画面（`.toolbar(.hidden, for: .navigationBar)`）の上に置く。
struct DGHeader<Trailing: View>: View {
    /// ヘッダーの高さ（03 の §3）
    static var height: CGFloat { 60 }
    /// 戻るアイコンの一辺
    private static var backIconSize: CGFloat { 24 }

    /// タイトル
    let title: Text
    /// 戻るボタンを押したときの処理。nil なら戻るボタンを出さない
    let onBack: (() -> Void)?
    /// 右端の要素
    let trailing: Trailing

    @ScaledMetric(relativeTo: .headline) private var backIconSize = DGHeader.backIconSize

    /// - Parameters:
    ///   - title: タイトル
    ///   - onBack: 戻るボタンを押したときの処理（nil なら戻るボタンを出さない）
    ///   - trailing: 右端の要素
    init(_ title: Text, onBack: (() -> Void)?, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DGSpacing.s4) {
            if let onBack {
                Button(action: onBack) {
                    Image("ui-back")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: backIconSize, height: backIconSize)
                        .foregroundStyle(Color.dgInk)
                        .frame(minWidth: DGMetrics.minTapTarget, minHeight: DGMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dgBare)
                .accessibilityLabel(Text("戻る"))
            }
            title
                .font(.dg(.displayHeader))
                .foregroundStyle(Color.dgInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            trailing
        }
        .padding(.horizontal, DGSpacing.s4)
        .frame(minHeight: Self.height)
    }
}

extension DGHeader where Trailing == EmptyView {
    /// 右端の要素が無いヘッダー
    /// - Parameters:
    ///   - title: タイトル
    ///   - onBack: 戻るボタンを押したときの処理（nil なら戻るボタンを出さない）
    init(_ title: Text, onBack: (() -> Void)?) {
        self.init(title, onBack: onBack) { EmptyView() }
    }
}

#Preview("Header") {
    VStack(spacing: 0) {
        DGHeader(Text(verbatim: "ルームを作る")) {}
        DGHeader(Text(verbatim: "年末の旅行")) {} trailing: {
            DGStatusChip(status: .open)
        }
        DGHeader(Text(verbatim: "ルームを作る")) {}
            .dynamicTypeSize(.accessibility5)
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.dgBgBase)
}
