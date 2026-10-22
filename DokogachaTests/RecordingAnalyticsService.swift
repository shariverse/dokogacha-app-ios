//
//  RecordingAnalyticsService.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation

/// 送ったイベントを順に覚える `AnalyticsService`（画面の Model のテストで、操作から送るイベントを確かめる）
final class RecordingAnalyticsService: AnalyticsService {
    /// 送ったイベント（送った順）
    private(set) var events: [AnalyticsEvent] = []

    /// 送ったイベントの名前（送った順）
    var names: [String] {
        events.map(\.name)
    }

    func log(_ event: AnalyticsEvent) {
        events.append(event)
    }
}
