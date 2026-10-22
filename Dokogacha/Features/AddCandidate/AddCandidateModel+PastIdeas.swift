//
//  AddCandidateModel+PastIdeas.swift
//  Dokogacha
//

import Foundation

/// S-08 の「過去のアイデア」のタブ（02 の §3.4 F-13・03 の S-08）。
///
/// 自分の過去のアイデアをルームごとにまとめて並べ（`PastIdeaList.groups`）、各行の「持ち込む」「追加済み」「上限」を
/// 「場所を探す」と同じ判定（`PlaceAddAvailability`。F-10 の上限・重複・状態）で決める。
/// 「持ち込む」で S-09 を開き（場所は前回のまま・カテゴリは前回のものから選び直せる）、`addCandidate` に `fromPastIdeaId` を渡して
/// 自分の投稿として追加する（いいねは 0 から。02 の §3.4）。持ち込んでも過去のアイデアは消さない
extension AddCandidateModel {
    /// ルームごとの過去のアイデア（新しいルーム順）
    var pastIdeaGroups: [PastIdeaGroup] {
        PastIdeaList.groups(pastIdeas)
    }

    /// 過去のアイデアが 1 件も無いと分かったか（03 の S-08 の 0 件の表示を出す）
    var isPastIdeasEmpty: Bool {
        hasLoadedPastIdeas && pastIdeas.isEmpty
    }

    /// 過去のアイデアの行の状態（「持ち込む」「追加済み」「上限」）。候補がまだ届いていなければ押せない
    func availability(of idea: Identified<PastIdea>) -> PlaceAddAvailability {
        availability(of: PastIdeaList.draftPlace(idea))
    }

    /// 「持ち込む」が押された。持ち込めれば S-09 を開き、同じ場所をほかの人が投稿していれば重複の確認を出す
    /// （「場所を探す」の「追加」と同じ。送っている途中・いいねを送っている途中は開かない）
    func bringTapped(_ idea: Identified<PastIdea>) {
        guard draft == nil, duplicatePrompt == nil, finish == nil, !isLiking else {
            return
        }
        let place = PastIdeaList.draftPlace(idea)
        switch availability(of: place) {
        case .addable:
            note = ""
            url = ""
            draft = Draft(place: place, category: place.category, pastIdeaID: idea.id)
        case let .duplicate(candidateID):
            duplicatePrompt = DuplicatePrompt(candidateID: candidateID)
        case .added, .limitReached, .unavailable:
            break
        }
    }
}
