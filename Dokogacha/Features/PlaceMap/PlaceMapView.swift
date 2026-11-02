//
//  PlaceMapView.swift
//  Dokogacha
//

import MapKit
import SwiftUI

/// S-17 場所の地図。投稿しようとしている場所・候補の場所を、アプリの中の大きな地図で確かめる画面（Discussion #193）。
///
/// 上から、ヘッダー（戻る＋場所名）、拡大・移動できる地図（ピン 1 つ。`accent.primary`）、
/// 場所のカード（カテゴリタイル・場所名・「エリア · カテゴリ」）と「元の位置に戻す」を並べる。
/// 現在地は出さない（位置情報の許可を使わない）。アプリの外（Apple のマップ）へ移るボタンは置かない。
/// サーバーには触れないので、オフラインでは地図のタイルが出ないだけで、ほかはそのまま使える。
///
/// 標準のナビゲーションバーは使わず、ヘッダーの「戻る」で前の画面に戻る（03 の §3）。積んだ `NavigationStack` の中で開く。
struct PlaceMapView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// 画面
        static let screen = "placeMap.screen"
        /// 地図（UI テストでは同じ大きさの面）
        static let map = "placeMap.map"
        /// 場所のカード
        static let placeCard = "placeMap.placeCard"
        /// 「元の位置に戻す」
        static let recenter = "placeMap.recenter"
    }

    /// 地図の最小の高さ（文字を大きくして下のカードが伸びても、地図はこれだけ残す。文字がとても大きいときはこの高さに固定する）
    private static let mapMinHeight: CGFloat = 200
    /// 場所名の大きさ（S-09 の場所名と同じ）
    private static let placeNameSize: CGFloat = 18
    /// UI テスト（`-uiTesting`）では地図を出さない（地図のタイルを読みにネットワークへ出ないように。場所は文字で出ている）
    private static let showsMap = !LaunchContext.current.isUITesting

    /// 映す場所
    let place: Place
    /// 場所のカテゴリ（カードのタイルと「エリア · カテゴリ」に使う）
    let category: PlaceCategory

    /// 地図の今の位置（最初はピンを中心にした範囲）
    @State private var position: MapCameraPosition

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - place: 映す場所
    ///   - category: 場所のカテゴリ
    init(place: Place, category: PlaceCategory) {
        self.place = place
        self.category = category
        _position = State(initialValue: .region(PlaceMapCamera.initialRegion(for: place)))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 文字がとても大きいときは、ヘッダー・地図（最小の高さ）・カード・ボタンをまとめてスクロールする
                // （小さい端末ではヘッダーとカードだけで画面の高さを超え、下が切れるため。地図の上のドラッグは地図が受けるので、
                // ヘッダーも中に入れて、文字の上からもスクロールできるようにする）
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        mapArea
                            .frame(height: Self.mapMinHeight)
                            .padding(.horizontal, DGSpacing.screenX)
                        bottomPanel
                    }
                }
            } else {
                VStack(spacing: 0) {
                    header
                    mapArea
                        .frame(minHeight: Self.mapMinHeight, maxHeight: .infinity)
                        .padding(.horizontal, DGSpacing.screenX)
                    bottomPanel
                        // 地図より下のカードとボタンを先に収める（地図は残りの高さいっぱいに広がる）
                        .layoutPriority(1)
                }
            }
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
    }

    /// 上部のヘッダー（戻る＋場所名）
    private var header: some View {
        DGHeader(Text(verbatim: place.name), onBack: { dismiss() })
            .dgContentColumn()
    }

    /// 下部の場所のカードと「元の位置に戻す」
    private var bottomPanel: some View {
        VStack(spacing: DGSpacing.s12) {
            placeCard
            DGButton("元の位置に戻す", icon: "ui-pin", kind: .secondary) {
                recenter()
            }
            .accessibilityHint(Text("地図を場所が真ん中に来る位置に戻します"))
            .accessibilityIdentifier(Identifier.recenter)
        }
        .padding(.horizontal, DGSpacing.screenX)
        .padding(.top, DGSpacing.s12)
        .padding(.bottom, DGSpacing.s14)
        .dgContentColumn()
    }

    // MARK: - 地図

    /// 拡大・移動できる地図（墨色の縁と角丸。ほかのカードと同じ見た目）。UI テストでは同じ大きさの面を出す
    private var mapArea: some View {
        let shape = RoundedRectangle(cornerRadius: DGRadius.md)
        return Group {
            if Self.showsMap {
                map
            } else {
                shape.fill(Color.dgSurfaceCard)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(place.name)の地図"))
        .accessibilityIdentifier(Identifier.map)
    }

    /// ピン 1 つの地図（拡大と移動だけ。回転・傾きは使わない）
    private var map: some View {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        return Map(position: $position, interactionModes: [.pan, .zoom]) {
            Marker(place.name, coordinate: coordinate)
                .tint(Color.dgAccentPrimary)
        }
    }

    /// 地図を最初の範囲（ピンを中心にした範囲）に戻す。「視差効果を減らす」がオンなら動かさずに切り替える
    private func recenter() {
        withAnimation(reduceMotion ? nil : .default) {
            position = .region(PlaceMapCamera.initialRegion(for: place))
        }
    }

    // MARK: - 場所のカード

    /// カテゴリタイル・場所名・「エリア · カテゴリ」のカード
    private var placeCard: some View {
        let style = DGCategoryStyle.of(category)
        let shape = RoundedRectangle(cornerRadius: DGRadius.lg)
        return HStack(spacing: DGSpacing.s12) {
            DGCategoryTile(category: style, size: .large)
            VStack(alignment: .leading, spacing: DGSpacing.s4) {
                Text(verbatim: place.name)
                    .font(.dgBody(Self.placeNameSize, weight: .black, relativeTo: .headline))
                    .foregroundStyle(Color.dgInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: PlaceMapCamera.meta(area: place.area, categoryLabel: String(localized: style.label)))
                    .font(.dg(.bodyCaption))
                    .foregroundStyle(Color.dgTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DGSpacing.cardPadding)
        .background(Color.dgSurfaceCard, in: shape)
        .overlay { shape.strokeBorder(Color.dgInk, lineWidth: DGBorder.regular) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Identifier.placeCard)
    }
}

/// S-17 の地図の範囲と、カードの文言の組み立て（画面の外から確かめられるように分けた純粋な計算）
nonisolated enum PlaceMapCamera {
    /// 最初に映す範囲（中心から上下・左右のメートル。S-10 の地図と同じ広さ）
    static let initialSpanMeters: CLLocationDistance = 1_200

    /// 最初に映す範囲（ピンを中心にした `initialSpanMeters` 四方）
    /// - Parameter place: 映す場所
    static func initialRegion(for place: Place) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            latitudinalMeters: initialSpanMeters,
            longitudinalMeters: initialSpanMeters
        )
    }

    /// カードの 2 行目（「エリア · カテゴリ」。エリアが空ならカテゴリだけ）
    /// - Parameters:
    ///   - area: エリアの表示
    ///   - categoryLabel: カテゴリの名前
    static func meta(area: String, categoryLabel: String) -> String {
        area.isEmpty ? categoryLabel : "\(area) · \(categoryLabel)"
    }
}

#Preview("S-17 場所の地図") {
    NavigationStack {
        PlaceMapView(
            place: Place(name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.728_9, longitude: 139.719_7, mapItemId: nil),
            category: .aquarium
        )
    }
}

#Preview("S-17 文字を最大") {
    NavigationStack {
        PlaceMapView(
            place: Place(name: "サンシャイン水族館", area: "東京・豊島区", latitude: 35.728_9, longitude: 139.719_7, mapItemId: nil),
            category: .aquarium
        )
    }
    .dynamicTypeSize(.accessibility5)
}

#Preview("S-17 長い名前・文字を最大（iPhone SE）", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack {
        PlaceMapView(
            place: Place(
                name: "国営昭和記念公園 こどもの森と日本庭園と花木園",
                area: "東京・立川市",
                latitude: 35.7056,
                longitude: 139.3985,
                mapItemId: nil
            ),
            category: .park
        )
    }
    .dynamicTypeSize(.accessibility5)
}
