//
//  DeepLinkRouterTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// 招待リンク（Universal Links）で開かれたときに、招待コードを覚えて受け渡すこと（タスク 34・05 の §7）を確かめる。
/// URL からコードを取り出す判定そのものは `InviteLinkTests` で確かめる
struct DeepLinkRouterTests {
    /// 招待リンクを受け取ると招待コードを覚え、受け取ったら消す（同じコードで 2 回開かない）
    @Test
    func remembersInviteCodeUntilTaken() throws {
        let router = DeepLinkRouter()
        let url = try #require(URL(string: "https://dokogacha.app/r/qw5-8rt"))
        #expect(router.handle(url))
        #expect(router.pendingInviteCode?.value == "QW58RT")

        #expect(router.takePendingInviteCode()?.value == "QW58RT")
        #expect(router.pendingInviteCode == nil)
        #expect(router.takePendingInviteCode() == nil)
    }

    /// 招待リンクでない URL は無視し、覚えていたコードも消さない
    @Test
    func ignoresOtherURLsAndKeepsPendingCode() throws {
        let router = DeepLinkRouter()
        router.handle(try #require(URL(string: "https://dokogacha.app/r/QW58RT")))
        for link in ["https://example.com/r/DK729Q", "https://dokogacha.app/terms", "https://dokogacha.app/r/OOOOOO"] {
            #expect(!router.handle(try #require(URL(string: link))))
        }
        #expect(router.pendingInviteCode?.value == "QW58RT")
    }

    /// 開く前に別の招待リンクが届いたら、新しいほうを開く
    @Test
    func replacesPendingCodeWithNewerLink() throws {
        let router = DeepLinkRouter()
        router.handle(try #require(URL(string: "https://dokogacha.app/r/QW58RT")))
        router.handle(try #require(URL(string: "https://dokogacha.app/r/DK729Q")))
        #expect(router.takePendingInviteCode()?.value == "DK729Q")
    }

    /// Universal Links の `NSUserActivity`（`NSUserActivityTypeBrowsingWeb`）の `webpageURL` を読み、ほかの種類は無視する
    @Test
    func readsBrowsingWebActivity() throws {
        let router = DeepLinkRouter()
        let other = NSUserActivity(activityType: "jp.shilokuma.Dokogacha.other")
        other.webpageURL = URL(string: "https://dokogacha.app/r/QW58RT")
        #expect(!router.handle(other))
        #expect(router.pendingInviteCode == nil)

        let browsing = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        #expect(!router.handle(browsing))
        browsing.webpageURL = URL(string: "https://dokogacha.app/r/QW58RT")
        #expect(router.handle(browsing))
        #expect(router.pendingInviteCode?.value == "QW58RT")
    }

    /// UI テスト・撮影モードでは、起動引数 `-open-url` の URL を起動の直後に開いたことにする（ほかの起動では読まない）
    @Test
    func readsOpenURLArgumentOnlyForUITestingAndScreenshots() {
        let link = "https://dokogacha.app/r/QW58RT"
        let uiTesting = LaunchContext(arguments: ["Dokogacha", "-uiTesting", "-open-url", link], environment: [:])
        #expect(uiTesting.openURL?.absoluteString == link)
        let screenshot = LaunchContext(arguments: ["-screenshot-demo", "-open-url", link], environment: [:])
        #expect(screenshot.openURL?.absoluteString == link)
        #expect(LaunchContext(arguments: ["Dokogacha", "-open-url", link], environment: [:]).openURL == nil)
        #expect(LaunchContext(arguments: ["-uiTesting", "-open-url"], environment: [:]).openURL == nil)
        #expect(LaunchContext(arguments: ["-uiTesting"], environment: [:]).openURL == nil)
    }

    /// 招待リンクで開く S-05・S-06 は、ホームの「招待コードで参加」と同じくシートで出す
    @Test
    func inviteLinkRouteIsSheet() throws {
        let code = try #require(InviteCode("QW58RT"))
        #expect(AppRoute.joinByInviteLink(code).presentation == .sheet)
        #expect(AppRoute.joinByInviteLink(code) != AppRoute.joinByCode)
        #expect(AppRoute.joinByInviteLink(code).inviteLinkCode == code)
        #expect(AppRoute.joinByCode.inviteLinkCode == nil)
    }
}
