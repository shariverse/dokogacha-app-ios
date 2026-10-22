//
//  DGChoiceOption.swift
//  Dokogacha
//
//  TabSwitch と SegmentedChoice の選択肢（`04_design_system.md` の §4）。
//

import SwiftUI

/// 選択肢 1 つ分（選んだときの値と文言）。`DGTabSwitch`・`DGSegmentedChoice` に並べる。
struct DGChoiceOption<Value: Hashable>: Identifiable {
    /// 選んだときに選択の値として入る値
    let value: Value
    /// ボタンの文言（03 の表記）
    let title: LocalizedStringKey

    var id: Value { value }

    /// - Parameters:
    ///   - title: ボタンの文言
    ///   - value: 選んだときに選択の値として入る値
    init(_ title: LocalizedStringKey, value: Value) {
        self.title = title
        self.value = value
    }
}
