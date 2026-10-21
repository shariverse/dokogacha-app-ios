//
//  HomePlaceholderView.swift
//  Dokogacha
//

import SwiftUI

/// S-02 ホームができるまでの仮の画面（タスク 13 で `HomeView` に差し替える）。
///
/// 起動の流れ（S-01 の後・2 回目の起動）でホームに進んだことを確かめられるよう、ロゴだけを置き、UI テスト用の ID を付ける。
struct HomePlaceholderView: View {
    /// UI テストが探す ID
    static let identifier = "home.screen"

    /// 自分のプロフィール（ホームで使う）
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading) {
            DGLogo()
        }
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.top, DGSpacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dgBgBase.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.identifier)
    }
}
