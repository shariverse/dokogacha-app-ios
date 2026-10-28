//
//  FirebaseAuthServiceProfileTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import FirebaseFirestore
import Foundation
import Testing

/// `FirebaseAuthService.profile(userID:)` が、キャッシュから届いた「ドキュメントが無い」を「未登録」にしないことを、擬似の SDK の窓口で確かめる。
///
/// 登録済みのユーザーがオフラインで起動してキャッシュが空だと、SDK はキャッシュから「無い」を返す。これを未登録とみなすと S-01 が出て、
/// 入れ直した表示名がオンラインに戻ったときに元の表示名を上書きしてしまう。
struct FirebaseAuthServiceProfileTests {
    typealias FakeGateway = FirestoreRoomRepositoryTests.FakeGateway

    static let path = "users/me"

    /// backend の `saveProfile` が書く形のプロフィール
    static let profileDocument = FirestoreDocument(id: "me", data: [
        "displayName": "たくみ",
        "avatarColor": "#2F6FD0",
        "adFree": false,
        "fcmTokens": [String](),
        "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_790_000_000))
    ])

    static func makeService(_ gateway: FakeGateway) -> FirebaseAuthService {
        FirebaseAuthService(gateway: gateway, functions: InMemoryServer.demo(.empty))
    }

    /// キャッシュの「無い」は流さず、その後に届いた値（キャッシュのドキュメント）が最初に流れる
    @Test
    func ignoresMissingDocumentFromCache() async throws {
        let gateway = FakeGateway()
        var iterator = Self.makeService(gateway).profile(userID: "me").makeAsyncIterator()

        gateway.sendDocument(nil, path: Self.path, isFromCache: true)
        gateway.sendDocument(Self.profileDocument, path: Self.path, isFromCache: true)
        let first = try #require(await iterator.next())
        #expect(first.value??.displayName == "たくみ")
    }

    /// サーバーから「無い」が届いたら、未登録（nil）を流す（S-01 を出してよい）
    @Test
    func deliversMissingDocumentFromServer() async throws {
        let gateway = FakeGateway()
        var iterator = Self.makeService(gateway).profile(userID: "me").makeAsyncIterator()
        // キャッシュの「無い」の後のサーバーの「無い」は中身が同じなので、メタデータの変化も受け取るよう頼んでいる
        #expect(gateway.includesMetadataChanges[Self.path] == true)

        gateway.sendDocument(nil, path: Self.path, isFromCache: true)
        gateway.sendDocument(nil, path: Self.path, isFromCache: false)
        #expect(await iterator.next() == .value(nil))
    }

    /// キャッシュにドキュメントがあれば（オフラインでも登録済みと分かる）、そのまま流す
    @Test
    func deliversCachedProfile() async throws {
        let gateway = FakeGateway()
        var iterator = Self.makeService(gateway).profile(userID: "me").makeAsyncIterator()

        gateway.sendDocument(Self.profileDocument, path: Self.path, isFromCache: true)
        let first = try #require(await iterator.next())
        #expect(first.value??.avatarColor == "#2F6FD0")
    }

    /// キャッシュにあったドキュメントがサーバーで消えていたら（アカウントの削除など）、キャッシュの値の後に未登録（nil）を流す（PR #40 の持ち越し）
    @Test
    func deliversServerRemovalAfterCachedProfile() async throws {
        let gateway = FakeGateway()
        var iterator = Self.makeService(gateway).profile(userID: "me").makeAsyncIterator()

        gateway.sendDocument(Self.profileDocument, path: Self.path, isFromCache: true)
        let first = try #require(await iterator.next())
        #expect(first.value??.displayName == "たくみ")
        gateway.sendDocument(nil, path: Self.path, isFromCache: false)
        #expect(await iterator.next() == .value(nil))
    }
}
