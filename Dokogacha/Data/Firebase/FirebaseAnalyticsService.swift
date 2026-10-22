//
//  FirebaseAnalyticsService.swift
//  Dokogacha
//

@preconcurrency import FirebaseAnalytics
import Foundation

/// Firebase Analytics に送る `AnalyticsService`。`FirebaseApp.configure` の後でだけ作る。
///
/// 収集を止めている構成（Debug・Emulator）では、SDK がイベントを捨てる（`FirebaseTelemetry`）
final class FirebaseAnalyticsService: AnalyticsService {
    func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters.isEmpty ? nil : Self.sdkParameters(event.parameters))
    }

    /// SDK に渡す形（値は `String`・`Int`）にする
    private static func sdkParameters(_ parameters: [String: AnalyticsParameterValue]) -> [String: Any] {
        parameters.mapValues { value -> Any in
            switch value {
            case let .string(text):
                text
            case let .int(number):
                number
            }
        }
    }
}
