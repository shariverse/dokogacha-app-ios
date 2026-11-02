//
//  PostCandidateFlowView.swift
//  Dokogacha
//

import SwiftUI

/// S-09 投稿の確認のシートの中身（Discussion #193 の Q2「シートの中で次の画面へ進む」）。
///
/// シートの中に `NavigationStack` を持ち、根元に S-09、小さな地図を押したら上に S-17 場所の地図を積む
/// （S-17 の「戻る」・端からのスワイプで S-09 に戻る。ひとこと・URL・カテゴリは `AddCandidateModel` が持つので残る）。
/// S-17 へ進むときはシートをラージに広げ（積んでいる間はラージだけ）、戻ったら進む前の大きさに戻す。文字がとても大きいときはラージだけ。
/// 送っている途中は、端からのスワイプで戻らせない（`NavigationLock`。S-05・S-06 の `JoinRoomFlowView` と同じ）。
/// トーストは S-17 を積んでいても見えるよう、スタックの外に重ねる（`AddCandidateModel.sheetToasts`）。
struct PostCandidateFlowView: View {
    /// S-08 と同じ画面の状態
    @Bindable var model: AddCandidateModel

    /// 積んでいる S-17 の行き先
    @State private var path: [PlaceMapDestination] = []
    /// シートの今の大きさ
    @State private var detent: PresentationDetent = .medium
    /// S-17 へ進む前のシートの大きさ（戻ったらこの大きさに戻す）
    @State private var detentBeforeMap: PresentationDetent?
    /// 送っている途中なら、端からのスワイプで S-09 に戻らせない
    @State private var navigationLock = NavigationLock()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack(path: $path) {
            PostCandidateView(model: model) { destination in
                openMap(destination)
            }
            // ナビゲーションバーを隠しても、S-17 から端のスワイプで S-09 に戻れるようにする
            .background(InteractivePopGesture(lock: navigationLock))
            .navigationDestination(for: PlaceMapDestination.self) { destination in
                PlaceMapView(place: destination.place, category: destination.category)
            }
        }
        .environment(\.navigationLock, navigationLock)
        .presentationDetents(detents, selection: $detent)
        .presentationDragIndicator(.visible)
        .dgToast(model.sheetToasts)
        .onChange(of: path) { _, path in
            if path.isEmpty, let detentBeforeMap {
                // 積んでいる間に文字をとても大きくしたなどで、元の大きさが今は選べないならラージにする
                detent = detents.contains(detentBeforeMap) ? detentBeforeMap : .large
                self.detentBeforeMap = nil
            }
        }
        .onChange(of: dynamicTypeSize.isAccessibilitySize, initial: true) { _, isAccessibilitySize in
            if isAccessibilitySize {
                detent = .large
            }
        }
    }

    /// シートの大きさの選択肢（文字がとても大きいときはラージだけ。03 の S-09）。
    /// S-17 を積んでいる間もラージだけにする（ミディアムでは地図・カード・ボタンが収まらないため）
    private var detents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize || !path.isEmpty ? [.large] : [.medium, .large]
    }

    /// シートをラージに広げて、S-17 を積む
    private func openMap(_ destination: PlaceMapDestination) {
        detentBeforeMap = detent
        detent = .large
        path.append(destination)
    }
}

/// S-17 場所の地図の行き先（映す場所とカテゴリ）
nonisolated struct PlaceMapDestination: Hashable, Sendable {
    /// 映す場所
    let place: Place
    /// 場所のカテゴリ
    let category: PlaceCategory
}
