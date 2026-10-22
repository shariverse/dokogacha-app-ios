//
//  AnalyticsEvent.swift
//  Dokogacha
//
//  Firebase Analytics に送るイベント（05 の §9 の表）を型で表す。
//

import Foundation

/// Analytics のイベント（05 の §9）。名前とパラメータの綴りはここだけに書く。
///
/// パラメータに入れられるのは、選択肢（enum）・数・真偽だけにして、表示名・ルーム名・ひとことなどの自由入力の文字や
/// ユーザー・ルームの ID を型の上で入れられないようにする（個人情報を Analytics に送らない）。
/// 真偽は Analytics に真偽の型が無いので、`1`・`0` の数で送る（Firebase の推奨。集計で足し合わせられる）。
nonisolated enum AnalyticsEvent: Equatable, Sendable {
    /// ルームを作った（F-02）
    case roomCreate(postLimit: Int, unlockRule: UnlockRule, likeMode: LikeMode)
    /// ルームに参加した（F-04。すでにメンバーだったときは送らない）
    case roomJoin(via: RoomJoinVia)
    /// 候補を追加した（F-10・F-13）
    case candidateAdd(source: CandidateAddSource, category: PlaceCategory)
    /// いいねを付けた・外した（F-20）
    case likeToggle(on: Bool)
    /// 準備OKを付けた・外した（F-30）
    case readyToggle(on: Bool)
    /// ガチャが解禁された（F-31・F-32）
    case roomUnlock(rule: UnlockRule, forced: Bool)
    /// ガチャを回した（F-40。回した人だけが送る）
    case gachaDraw(candidateCount: Int, isReroll: Bool, rare: Bool)
    /// 行き先きっぷを共有しようとした（F-42。共有シートを開いた）
    case ticketShare
    /// 引き直しを提案した（F-43）
    case rerollPropose
    /// 引き直しの投票の結果が出た（F-43）
    case rerollResult(passed: Bool)
    /// ルームを終了した（F-44。作成者が決めたら `auto` は false）
    case roomClose(auto: Bool)
    /// 広告非表示を買った（F-51）
    case purchaseRemoveAds

    /// イベントの名前（05 の §9 の表の綴り）
    var name: String {
        switch self {
        case .roomCreate: "room_create"
        case .roomJoin: "room_join"
        case .candidateAdd: "candidate_add"
        case .likeToggle: "like_toggle"
        case .readyToggle: "ready_toggle"
        case .roomUnlock: "room_unlock"
        case .gachaDraw: "gacha_draw"
        case .ticketShare: "ticket_share"
        case .rerollPropose: "reroll_propose"
        case .rerollResult: "reroll_result"
        case .roomClose: "room_close"
        case .purchaseRemoveAds: "purchase_remove_ads"
        }
    }

    /// パラメータ（05 の §9 の表の綴り）。無いイベントは空
    var parameters: [String: AnalyticsParameterValue] {
        switch self {
        case let .roomCreate(postLimit, unlockRule, likeMode):
            ["post_limit": .int(postLimit), "unlock_rule": .string(unlockRule.rawValue), "like_mode": .string(likeMode.rawValue)]
        case let .roomJoin(via):
            ["via": .string(via.rawValue)]
        case let .candidateAdd(source, category):
            ["source": .string(source.rawValue), "category": .string(category.rawValue)]
        case let .likeToggle(on), let .readyToggle(on):
            ["on": .bool(on)]
        case let .roomUnlock(rule, forced):
            ["rule": .string(rule.rawValue), "forced": .bool(forced)]
        case let .gachaDraw(candidateCount, isReroll, rare):
            ["candidate_count": .int(candidateCount), "is_reroll": .bool(isReroll), "rare": .bool(rare)]
        case let .rerollResult(passed):
            ["passed": .bool(passed)]
        case let .roomClose(auto):
            ["auto": .bool(auto)]
        case .ticketShare, .rerollPropose, .purchaseRemoveAds:
            [:]
        }
    }
}

/// Analytics のパラメータの値（Analytics が受け付ける文字列と数だけ）
nonisolated enum AnalyticsParameterValue: Equatable, Sendable {
    /// 文字列（選択肢の `rawValue`）
    case string(String)
    /// 整数（真偽も `1`・`0` で送る）
    case int(Int)

    /// 真偽を `1`・`0` の数にする
    static func bool(_ value: Bool) -> Self {
        .int(value ? 1 : 0)
    }
}

/// ルームに参加した道（`room_join` の `via`）
nonisolated enum RoomJoinVia: String, CaseIterable, Sendable {
    /// 招待リンク（Universal Links）で開いた
    case link
    /// ホームの「招待コードで参加」でコードを入れた
    case code
    /// 前回のメンバーへの招待の通知（`inviteLastMembers`）を開いた
    case push
}

/// 候補を追加した道（`candidate_add` の `source`）
nonisolated enum CandidateAddSource: String, CaseIterable, Sendable {
    /// 場所を検索して追加した
    case search
    /// 過去のアイデアから持ち込んだ
    case past
}

extension AnalyticsEvent {
    /// 届いたルームの変化から、解禁（`room_unlock`）と引き直しの結果（`reroll_result`）のイベントを決める。
    ///
    /// どちらもサーバー（Functions のトリガー・締切の判定）が状態を変えるので、操作した端末では分からない。
    /// ルームの画面を出している間に、購読で `open` → `unlocked`・引き直しの投票中 → 可決・否決 に変わるのを見た端末が送る。
    /// 画面を開いたときの最初の値（`previous` が nil）では送らない（前の状態が分からず、開くたびに送ってしまうため）
    /// - Parameters:
    ///   - previous: 前に届いていたルーム（まだ届いていなければ nil）
    ///   - current: 届いたルーム
    /// - Returns: 送るイベント（無ければ空）
    static func roomChanges(previous: Room?, current: Room) -> [Self] {
        guard let previous else {
            return []
        }
        var events: [Self] = []
        if previous.status == .open, current.status == .unlocked {
            events.append(.roomUnlock(rule: current.settings.unlockRule, forced: current.forcedUnlock))
        }
        if previous.reroll.status == .voting, current.reroll.status == .passed || current.reroll.status == .rejected {
            events.append(.rerollResult(passed: current.reroll.status == .passed))
        }
        return events
    }

    /// 自分が回したガチャ（`gacha_draw`）。当選した候補の確率は、回したときに画面に出していた候補のいいねから
    /// `drawGacha` と同じ式（`Probability.odds`）で求め、レア当選かは `WinRarity` で決める。
    /// - Parameters:
    ///   - winnerID: 当選した候補の ID
    ///   - candidates: 回したときの候補（引き直しで外れた候補を含んでよい）
    ///   - room: 回したときのルーム（いいねの効き方・引き直しで外れた候補）
    static func gachaDraw(winnerID: String, candidates: [Identified<Candidate>], room: Room) -> Self {
        let excluded = Set(room.excludedCandidateIds)
        let table = Probability.odds(
            of: candidates.map { OddsInput(id: $0.id, likeCount: $0.likedBy.count) },
            mode: room.settings.likeMode,
            excluding: excluded
        )
        let candidateCount = table.odds.count
        let rare = table[winnerID].map { WinRarity.isRare(probability: $0.probability, candidateCount: candidateCount) } ?? false
        return .gachaDraw(candidateCount: candidateCount, isReroll: !excluded.isEmpty, rare: rare)
    }
}
