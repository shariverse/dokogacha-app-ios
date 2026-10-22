//
//  ReportedContent.swift
//  Dokogacha
//

import Foundation

/// 報告した候補の、報告した人の画面での見せ方（02 の §3.5「報告した人の画面では、その候補のひとこととURLを非表示にする」）。
///
/// 隠すのは利用者が自由に書いたもの（ひとこと・参考 URL）だけで、場所名・エリア・カテゴリ・いいね・出やすさは残す
/// （候補そのものはガチャの対象のままで、ほかのメンバーの画面は変わらない。削除は投稿した人・作成者・運営が行う）。
/// S-07 の候補カード・S-10 の詳細・S-14 の行き先きっぷが同じ規則で隠す。
nonisolated enum ReportedContent {
    /// 報告した候補を覚える鍵（ルームの ID と候補の ID。どちらも `/` を含まないドキュメントの ID）
    static func key(roomID: String, candidateID: String) -> String {
        "\(roomID)/\(candidateID)"
    }

    /// 画面に出すひとこと。空・報告した候補なら nil
    /// - Parameters:
    ///   - note: 候補のひとこと
    ///   - isReported: 自分がこの候補を報告したか
    static func visibleNote(_ note: String, isReported: Bool) -> String? {
        isReported || note.isEmpty ? nil : note
    }

    /// 画面に出す参考 URL。`http`・`https` で開けるものだけで、無い・報告した候補なら nil
    /// - Parameters:
    ///   - text: 候補の参考 URL
    ///   - isReported: 自分がこの候補を報告したか
    static func visibleURL(_ text: String?, isReported: Bool) -> URL? {
        guard !isReported, let text, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}
