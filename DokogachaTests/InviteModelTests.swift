//
//  InviteModelTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// S-04 招待の表示の形（`ABC-123`）・招待リンク・共有の文面・コピーと、ルームを作った後の積み方（03 の §1）を確かめる
struct InviteModelTests {
    /// 「年末の旅行」・コード `DK729Q` の作成したルーム
    static func destination() throws -> InviteDestination {
        InviteDestination(roomID: "room-1", roomName: "年末の旅行", inviteCode: try #require(InviteCode("DK729Q")))
    }

    /// クリップボードの代わりに、書いた文字列を記録する
    final class Clipboard {
        private(set) var copied: [String] = []

        func copy(_ text: String) {
            copied.append(text)
        }
    }

    /// テストで使う画面の値と、その窓口
    struct Fixture {
        let model: InviteModel
        let toasts: DGToastCenter
        let clipboard: Clipboard
    }

    /// コピーした文字列を記録する画面の値
    static func make() throws -> Fixture {
        let clipboard = Clipboard()
        let toasts = DGToastCenter(visibleFor: .seconds(3_600))
        let model = InviteModel(destination: try destination(), toasts: toasts) { clipboard.copy($0) }
        return Fixture(model: model, toasts: toasts, clipboard: clipboard)
    }

    /// 招待コードは 3 文字ずつハイフンで区切って出し、ルーム名と最大人数を出す
    @Test
    func displaysCodeWithHyphen() throws {
        let model = try Self.make().model
        #expect(model.roomName == "年末の旅行")
        #expect(model.codeText == "DK7-29Q")
        #expect(model.maxMembers == 20)
    }

    /// 招待リンクは `https://dokogacha.app/r/{ハイフンなしのコード}`
    @Test
    func inviteLinkUsesProvisionalDomain() throws {
        let model = try Self.make().model
        #expect(model.inviteURL.absoluteString == "https://dokogacha.app/r/DK729Q")
    }

    /// 共有の文面は 03 の S-04 の 3 のとおり（1 行目が誘いの文、2 行目が招待リンク）
    @Test
    func shareMessageFollowsSpec() throws {
        let model = try Self.make().model
        #expect(model.shareMessage == "「年末の旅行」で行き先ガチャやろう！行きたい場所を投稿してね\nhttps://dokogacha.app/r/DK729Q")
    }

    /// コピーすると、表示と同じハイフン付きのコードを書き、トーストで知らせる
    @Test
    func copyCodeWritesDisplayTextAndShowsToast() throws {
        let fixture = try Self.make()
        fixture.model.copyCode()
        #expect(fixture.clipboard.copied == ["DK7-29Q"])
        #expect(fixture.toasts.current?.text == "招待コードをコピーしました")
    }

    // MARK: 積み方（03 の §1）

    /// ルームを作ったら S-03 を外し、作ったルームの上に S-04 を積む（S-04 から戻るとルーム、その次はホーム）
    @Test
    func pathAfterCreatingReplacesCreateRoomWithRoomAndInvite() throws {
        let created = try Self.destination()
        #expect(AppRoute.pathAfterCreating(created, from: [.createRoom]) == [.room(id: "room-1"), .invite(created)])
        // S-03 より下に積んでいたものは残す
        #expect(
            AppRoute.pathAfterCreating(created, from: [.settings, .createRoom])
                == [.settings, .room(id: "room-1"), .invite(created)]
        )
    }

    /// 「ルームへ進む」で S-04 を外してルームを出す。上が S-04 でなければ変えない
    @Test
    func pathOpeningRoomPopsInvite() throws {
        let created = try Self.destination()
        #expect(AppRoute.pathOpeningRoom(from: [.room(id: "room-1"), .invite(created)]) == [.room(id: "room-1")])
        #expect(AppRoute.pathOpeningRoom(from: [.room(id: "room-1")]) == [.room(id: "room-1")])
        #expect(AppRoute.pathOpeningRoom(from: []).isEmpty)
    }

    /// S-04 はプッシュで出す
    @Test
    func inviteIsPushed() throws {
        #expect(AppRoute.invite(try Self.destination()).presentation == .push)
    }
}
