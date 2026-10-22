//
//  DGCandidateCardOddsTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// 出やすさの計算の結果から部品の見た目への対応（`DGCandidateCard+Odds.swift`）を確かめる。
struct DGCandidateCardOddsTests {
    /// レベルごとのチップの文言が 02 の §4.3 の表のとおり
    @Test
    func levelLabels() {
        #expect(DGLevelStyle.of(.flat).label.key == "平等")
        #expect(DGLevelStyle.of(.high).label.key == "出やすい")
        #expect(DGLevelStyle.of(.mid).label.key == "ふつう")
        #expect(DGLevelStyle.of(.low).label.key == "レア")
    }

    /// 人気の強調の種類がリボンの種類に対応する（02 の §4.4 の文言）
    @Test
    func highlightRibbons() {
        #expect(DGCandidateCard.Highlight(.popular) == .popular)
        #expect(DGCandidateCard.Highlight(.allLiked) == .allLiked)
        #expect(DGCandidateCard.Highlight(.popular).title.key == "みんな推し")
        #expect(DGCandidateCard.Highlight(.allLiked).title.key == "全員いいね")
    }
}
