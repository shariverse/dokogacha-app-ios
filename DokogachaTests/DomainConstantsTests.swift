//
//  DomainConstantsTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 02 の上限と 06 の §4 の仮決めの値が、資料どおりであることを確かめる。
///
/// TypeScript 側の `backend/functions/src/domain/constants.test.ts` と同じ値を確かめる。
struct DomainConstantsTests {
    /// 02 の上限・入力の範囲
    @Test
    func limits() {
        typealias Limits = DomainConstants.Limits
        #expect(Limits.maxMembers == 20)
        #expect(Limits.displayNameLength == 1...10)
        #expect(Limits.roomNameLength == 1...20)
        #expect(Limits.postLimitRange == 1...10)
        #expect(Limits.defaultPostLimit == 3)
        #expect(Limits.maxCandidates == 200)
        #expect(Limits.noteMaxLength == 40)
        #expect(Limits.duplicateDistanceMeters == 100)
        #expect(Limits.deadlineEarliestFromNow == 3_600)
        #expect(Limits.deadlineLatestFromNow == 30 * 86_400)
        #expect(Limits.defaultDeadlineDaysLater == 3)
        #expect(Limits.defaultDeadlineHour == 21)
        #expect(Limits.rerollsPerRoom == 1)
    }

    /// 06 の §4 の仮決め
    @Test
    func provisionalValues() {
        #expect(DomainConstants.RemoveAds.productID == "remove_ads")
        #expect(DomainConstants.RemoveAds.priceYen == 480)
        #expect(DomainConstants.Web.domain == "dokogacha.app")
        #expect(DomainConstants.Web.inviteLinkPathPrefix == "/r/")
        #expect(DomainConstants.Web.ogpTitle == "ドコガチャに招待されました")
        #expect(DomainConstants.Schedule.rerollVotingDuration == 24 * 3_600)
        #expect(DomainConstants.Schedule.autoCloseAfterDraw == 7 * 86_400)
        #expect(DomainConstants.Schedule.deadlineCheckInterval == 5 * 60)
        #expect(DomainConstants.Schedule.newCandidatesDigestHour == 20)
        #expect(DomainConstants.Schedule.newCandidatesDigestMinute == 0)
        #expect(DomainConstants.Schedule.newCandidatesDigestPerDay == 1)
        #expect(TimeZone(identifier: DomainConstants.Schedule.timeZoneIdentifier)?.secondsFromGMT() == 9 * 3_600)
        #expect(DomainConstants.Popularity.closeCallMinLikes == 3)
        #expect(DomainConstants.Popularity.popularRatio == 0.6)
        #expect(DomainConstants.Popularity.popularMinLikes == 2)
        #expect(DomainConstants.Popularity.allLikedMinOtherMembers == 2)
    }

    /// 場所検索の範囲に、日本の端（与那国島・宗谷岬・根室）と主な都市が入る
    @Test
    func searchRegionCoversJapan() {
        typealias Region = DomainConstants.SearchRegion
        let latitudes = (Region.centerLatitude - Region.latitudeDelta / 2)...(Region.centerLatitude + Region.latitudeDelta / 2)
        let longitudes = (Region.centerLongitude - Region.longitudeDelta / 2)...(Region.centerLongitude + Region.longitudeDelta / 2)
        let places: [(Double, Double)] = [(24.47, 122.99), (45.52, 141.94), (43.33, 145.58), (35.68, 139.77), (26.21, 127.68)]
        for (latitude, longitude) in places {
            #expect(latitudes.contains(latitude) && longitudes.contains(longitude), "(\(latitude), \(longitude)) が範囲の外")
        }
    }
}
