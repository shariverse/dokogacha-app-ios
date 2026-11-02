//
//  ScreenshotDemo+PlaceMap.swift
//  Dokogacha
//

import SwiftUI

extension ScreenshotDemo {
    /// S-17 場所の地図を、デモの候補（はるかのサンシャイン水族館）の場所で開く（`NavigationStack` の根元に置いて出す）。
    ///
    /// サーバーには触れない画面なので、デモのデータ（`-demo-scenario`）によらず同じ場所を出す。
    /// 地図のタイルは通信で読むので、タイルが出るまで待ってから撮る
    struct PlaceMapScene: View {
        /// 映す場所（`DemoScenario` の `demo-candidate-1` と同じ）
        static let place = Place(name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.728_9, longitude: 139.719_7, mapItemId: nil)

        var body: some View {
            NavigationStack {
                PlaceMapView(place: Self.place, category: .aquarium)
            }
        }
    }
}
