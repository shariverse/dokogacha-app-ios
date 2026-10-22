//
//  DGLikeButtonStatusTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Foundation
import Testing

/// いいねボタンの状態ごとの文言・VoiceOver の読み・押せるか・ハートの絵を確かめる（04 の §4・02 の F-20）
struct DGLikeButtonStatusTests {
    /// ハートの下の文言は 04 の §4 の「いいね／いいね済／自分」。受け付けないときも、いいねしたかどうかは残す
    @Test
    func titles() {
        #expect(String(localized: DGLikeButton.Status.notLiked.title) == "いいね")
        #expect(String(localized: DGLikeButton.Status.liked.title) == "いいね済")
        #expect(String(localized: DGLikeButton.Status.mine.title) == "自分")
        #expect(String(localized: DGLikeButton.Status.locked.title) == "いいね")
        #expect(String(localized: DGLikeButton.Status.lockedLiked.title) == "いいね済")
    }

    /// VoiceOver は押すと何が起きるか、押せないときはなぜ押せないかを読む
    @Test
    func accessibilityLabels() {
        #expect(String(localized: DGLikeButton.Status.notLiked.accessibilityLabel) == "いいね")
        #expect(String(localized: DGLikeButton.Status.liked.accessibilityLabel) == "いいねを取り消す")
        #expect(String(localized: DGLikeButton.Status.mine.accessibilityLabel) == "自分の投稿にはいいねできません")
        #expect(String(localized: DGLikeButton.Status.locked.accessibilityLabel) == "いいねの受付は終わりました")
        #expect(
            String(localized: DGLikeButton.Status.lockedLiked.accessibilityLabel) == "いいね済み。いいねの受付は終わりました"
        )
    }

    /// 押せるのは未いいね・いいね済みだけ。自分の投稿（F-20 の AC「自分の投稿のいいねボタンは押せない」）と、
    /// いいねを受け付けないルーム（`drawn`・`closed`）では押せない
    @Test
    func onlyOpenStatusesAreEnabled() {
        let enabled = DGLikeButton.Status.allCases.filter(\.isEnabled)
        #expect(enabled == [.notLiked, .liked])
        #expect(!DGLikeButton.Status.mine.isEnabled)
    }

    /// いいね済み（受け付けないときを含む）だけ、塗りつぶしたハートにする
    @Test
    func heartIconFollowsLiked() {
        #expect(DGLikeButton.Status.notLiked.heartIconName == "ui-heart")
        #expect(DGLikeButton.Status.liked.heartIconName == "ui-heart-fill")
        #expect(DGLikeButton.Status.mine.heartIconName == "ui-heart")
        #expect(DGLikeButton.Status.locked.heartIconName == "ui-heart")
        #expect(DGLikeButton.Status.lockedLiked.heartIconName == "ui-heart-fill")
        #expect(DGLikeButton.Status.allCases.filter(\.isLiked) == [.liked, .lockedLiked])
    }
}
