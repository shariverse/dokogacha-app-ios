//
//  PlaceLocalityTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// MapKit の結果の市区町村（`locality`・`subLocality`）を、同梱の市区町村の名前と突き合わせることを確かめる（`PlaceLocality`。Issue #160）。
///
/// `locality` の形は Mac の MapKit で確かめたもの（政令指定都市の「中区, 横浜市」「札幌市中央区」、郡の「足柄下郡箱根町」など）
struct PlaceLocalityTests {
    /// 突き合わせの 1 件（`locality`・`subLocality`・市区町村の名前・合うか）
    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        let locality: String?
        let subLocality: String?
        let municipality: String
        let matches: Bool?

        var testDescription: String {
            "\(locality ?? "nil") / \(subLocality ?? "nil") → \(municipality)"
        }

        init(_ locality: String?, _ subLocality: String?, _ municipality: String, _ matches: Bool?) {
            self.locality = locality
            self.subLocality = subLocality
            self.municipality = municipality
            self.matches = matches
        }
    }

    nonisolated static let cases: [Case] = [
        // 23 区・市・町村
        Case("渋谷区", "宇田川町", "渋谷区", true),
        Case("渋谷区", "宇田川町", "新宿区", false),
        Case("鎌ケ谷市", nil, "鎌ケ谷市", true),
        Case("鎌ヶ谷市", nil, "鎌ケ谷市", true),
        Case("桧原村", nil, "檜原村", true),
        // 政令指定都市（区の付き方が揺れる）
        Case("中区, 横浜市", "山下町", "横浜市", true),
        Case("横浜市", "金沢区", "横浜市", true),
        Case("札幌市中央区", "大通西", "札幌市", true),
        Case("北区, 大阪市", "中之島", "大阪市", true),
        Case("川崎区, 川崎市", "日進町", "横浜市", false),
        // 郡の町村
        Case("足柄下郡箱根町", "強羅", "箱根町", true),
        Case("箱根町", "二ノ平", "箱根町", true),
        Case("足柄下郡", "箱根町", "箱根町", true),
        Case("足柄下郡", "湯河原町", "箱根町", false),
        Case("赤穂郡上郡町", nil, "上郡町", true),
        Case("諏訪郡富士見町", "落合", "富士見町", true),
        // 名前に「郡」を含む市（郡の町村と取り違えない）
        Case("郡山市", nil, "郡山市", true),
        Case("大和郡山市", nil, "郡山市", false),
        // 町名の subLocality は、locality が郡でなければ見ない
        Case("八王子市", "日野町", "日野市", false),
        // 分からない（無い・英語の端末）
        Case(nil, nil, "渋谷区", nil),
        Case("Shibuya", "Shibuya", "渋谷区", nil),
        Case("Hakone, Ashigarashimo-Gun", "Gora", "箱根町", nil)
    ]

    /// `locality`・`subLocality` が市区町村に合うか（分からなければ nil）
    @Test(arguments: Self.cases)
    func matchesMunicipality(case: Case) {
        let matches = PlaceLocality.matches(locality: `case`.locality, subLocality: `case`.subLocality, municipality: `case`.municipality)
        #expect(matches == `case`.matches)
    }

    /// 画面に出す市区町村は、政令指定都市を「横浜市中区」の形にし、郡を外す。英語の名前は最初の 1 つ
    @Test
    func displayNames() {
        #expect(PlaceLocality.displayName(locality: "渋谷区", subLocality: "宇田川町") == "渋谷区")
        #expect(PlaceLocality.displayName(locality: "中区, 横浜市", subLocality: "山下町") == "横浜市中区")
        #expect(PlaceLocality.displayName(locality: "北区, 大阪市", subLocality: nil) == "大阪市北区")
        #expect(PlaceLocality.displayName(locality: "札幌市中央区", subLocality: "大通西") == "札幌市中央区")
        #expect(PlaceLocality.displayName(locality: "足柄下郡箱根町", subLocality: "強羅") == "箱根町")
        #expect(PlaceLocality.displayName(locality: "赤穂郡上郡町", subLocality: nil) == "上郡町")
        #expect(PlaceLocality.displayName(locality: "足柄下郡", subLocality: "箱根町") == "箱根町")
        #expect(PlaceLocality.displayName(locality: "郡山市", subLocality: nil) == "郡山市")
        #expect(PlaceLocality.displayName(locality: "大和郡山市", subLocality: nil) == "大和郡山市")
        #expect(PlaceLocality.displayName(locality: "上郡町", subLocality: nil) == "上郡町")
        #expect(PlaceLocality.displayName(locality: "Hakone, Ashigarashimo-Gun", subLocality: "Gora") == "Hakone")
        #expect(PlaceLocality.displayName(locality: " ", subLocality: "箱根町") == nil)
        #expect(PlaceLocality.displayName(locality: nil, subLocality: nil) == nil)
    }
}
