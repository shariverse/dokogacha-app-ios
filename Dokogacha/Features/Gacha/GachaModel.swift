//
//  GachaModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-13 ガチャの状態（ルームと候補の購読・抽選・演出の段階・触覚の合図）。
///
/// **自分が回す（F-40・F-41）**: レバーを押すと回転中にし、同時に Callable の `drawGacha` を呼ぶ。結果が返り、かつ回転（1.6 秒）が終わったら
/// カプセルを落とし、少し見せてから自動で開ける（02 の §6.2。カプセルを押す操作は無い。Issue #158）。送っている途中・演出の途中はレバーを押せない（二重に回さない）。
/// 失敗したら演出を止めて待機に戻し、トーストを出す（通信のエラーは「通信できませんでした。もう一度回してください」、
/// `room-not-unlocked`・`no-candidates` などの理由は `AppError` の文言）。ほかの人と同時に回して先を越されたとき（`alreadyDrawn`）は、
/// 先に回した人の名前を出して同じ結果を見せる。
///
/// **ほかの人が回した（F-41）**: 待機中にルームの購読で `drawn` と `currentDrawId` が届いたら、`draws/{drawId}` の `drawnByName` を読み、
/// 「◯◯さんが回しました！」を出して同じ演出（揺れ → カプセルの落下 → 開ける）を自動で再生する。
/// 演出を見終えた抽選は端末に覚え（`SeenDrawStore`）、もう一度開いたときは揺れと落下を飛ばし、取り出し口のカプセルを開けるところから始める。
///
/// **時間**: 演出の時間は `GachaTimeline` で、待つ処理（`sleep`）は注入する（テストでは待たないものを渡す）。
/// 「視差効果を減らす」（`reducesMotion`）では待たずに次の段階へ進み、回転中の刻みの触覚も鳴らさない（04 の §5「すべて即時切り替え」）。
/// 見た目の動き（揺れ・回転・落下・拡大縮小）は画面（`GachaView`）が段階から作る。
///
/// 購読は画面の `.task` で `observe()` を呼び、画面が消えたら止まる。演出の `Task` は Model が持ち、画面が消えたら `stop()` で止める。
@Observable
final class GachaModel {
    /// 待つ処理（秒数の `Duration` を受け取る）
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// 通信のエラーで回せなかったときのトースト（02 の §6.2「通信できませんでした。もう一度回してください」）
    static let drawFailureMessage: LocalizedStringResource = "通信できませんでした。もう一度回してください"

    /// ルームの ID
    let roomID: String
    /// 自分の uid
    let userID: String
    /// 購読で届いたルーム
    private(set) var room: Room?
    /// 購読で届いた候補（投稿の新しい順）
    private(set) var candidates: [Identified<Candidate>] = []
    /// 演出の段階
    private(set) var phase: GachaPhase = .idle
    /// ほかの人が回したときの、回した人の表示名（自分が回したときは nil）
    private(set) var drawnByName: String?
    /// 演出している抽選の ID（まだ無ければ nil）
    private(set) var drawID: String?
    /// 当選した候補の ID（まだ無ければ nil）
    private(set) var winnerCandidateID: String?
    /// 自分の `drawGacha` を送ってから演出が終わるまでか（二重に回さない）
    private(set) var isDrawing = false
    /// 最後に出した合図（画面の `sensoryFeedback` が見る）
    private(set) var cue: GachaCueEvent?
    /// 「視差効果を減らす」か（画面が環境の値を入れる。UI テストでは常に true）
    var reducesMotion = false

    /// 合図を出すたびに呼ぶ処理（サウンドを足すときのフック。テストでは合図の順を覚える）
    @ObservationIgnored var cueHandler: ((GachaCue) -> Void)?

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let seenDraws: any SeenDrawStore
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay
    /// 自分が回せたら `gacha_draw` を送る窓口
    @ObservationIgnored private let analytics: any AnalyticsService
    /// いま動かしている演出（回す・再生する・開ける）
    @ObservationIgnored private var playTask: Task<Void, Never>?
    /// いま失敗している購読（トーストを 1 回にする）
    @ObservationIgnored private var failingSources: Set<Source> = []
    /// 合図の通し番号
    @ObservationIgnored private var cueSequence = 0

    /// 購読の種類
    private enum Source: Hashable {
        case room
        case candidates
    }

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - userID: 自分の uid
    ///   - repository: ルーム・候補・抽選の記録の購読の窓口
    ///   - functions: `drawGacha` を呼ぶ窓口
    ///   - toasts: エラーを出すトーストの窓口（フルスクリーンカバーの中に重ねるもの）
    ///   - seenDraws: 演出を見終えた抽選を覚える窓口
    ///   - sleep: 演出の時間を待つ処理（テストでは待たないものを渡す）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方
    ///   - analytics: Analytics のイベント（05 の §9）を送る窓口
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        seenDraws: any SeenDrawStore,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        resubscribeDelay: ResubscribeDelay = .standard,
        analytics: any AnalyticsService = DisabledAnalyticsService()
    ) {
        self.roomID = roomID
        self.userID = userID
        self.repository = repository
        self.functions = functions
        self.toasts = toasts
        self.seenDraws = seenDraws
        self.sleep = sleep
        self.resubscribeDelay = resubscribeDelay
        self.analytics = analytics
    }

    // MARK: - 表示の値

    /// 抽選の対象の候補（引き直しで外れた候補を除く。投稿の古い順）
    var drawableCandidates: [Identified<Candidate>] {
        let excluded = Set(room?.excludedCandidateIds ?? [])
        return candidates
            .filter { !excluded.contains($0.id) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// 「カプセル N個」の N（抽選の対象の候補の数）
    var capsuleCount: Int {
        drawableCandidates.count
    }

    /// ドームに入れるカプセルの色の番号（候補の投稿の古い順の `colorIndex`）
    var capsuleColorIndexes: [Int] {
        drawableCandidates.map(\.colorIndex)
    }

    /// 当選したカプセルの色の番号（候補をまだ読めていなければ 0）
    var winnerColorIndex: Int {
        candidates.first { $0.id == winnerCandidateID }?.colorIndex ?? 0
    }

    /// 引き直しの抽選か（除外した候補がある）
    var isReroll: Bool {
        !(room?.excludedCandidateIds.isEmpty ?? true)
    }

    /// レバーを回せるか（待機中・`unlocked`・候補がある・まだ抽選していない・送っている途中でない）
    var canTurnLever: Bool {
        phase == .idle && !isDrawing && drawID == nil && room?.status == .unlocked && capsuleCount > 0
    }

    /// 画面を閉じてよいか（演出の途中・送っている途中は閉じない。抽選は終わっているので、途中で閉じると結果を見ないまま戻るため）
    var canClose: Bool {
        !phase.isAnimating && !isDrawing
    }

    // MARK: - 購読

    /// ルームと候補を購読し、呼んだ `Task` が cancel されるまで続ける
    func observe() async {
        async let room: Void = followRoom()
        async let candidates: Void = followCandidates()
        _ = await (room, candidates)
    }

    /// ルームを購読し続ける
    private func followRoom() async {
        await follow(.room, subscribe: { repository.room(id: roomID) }, apply: applyRoom)
    }

    /// 候補を購読し続ける
    private func followCandidates() async {
        await follow(.candidates, subscribe: { repository.candidates(roomID: roomID) }, apply: applyCandidates)
    }

    /// 演出を止める（画面が消えた）
    func stop() {
        playTask?.cancel()
        playTask = nil
    }

    /// 購読を続ける。失敗で終わったら、少し待って購読し直す
    private func follow<Value: Sendable>(
        _ source: Source,
        subscribe: () -> AsyncStream<LiveUpdate<Value>>,
        apply: (Value) -> Void
    ) async {
        while !Task.isCancelled {
            for await update in subscribe() {
                guard !Task.isCancelled else {
                    return
                }
                switch update {
                case let .value(value):
                    failingSources.remove(source)
                    apply(value)
                case let .failure(error):
                    noteFailure(error, from: source)
                }
            }
            guard await resubscribeDelay.wait() else {
                return
            }
        }
    }

    /// 購読の失敗を覚え、どの購読も失敗していなかったときだけトーストを出す
    private func noteFailure(_ error: AppError, from source: Source) {
        guard !error.isCancellation else {
            return
        }
        let wasHealthy = failingSources.isEmpty
        failingSources.insert(source)
        if wasHealthy {
            toasts.show(text: error.message)
        }
    }

    /// 届いた候補を映す
    private func applyCandidates(_ value: [Identified<Candidate>]) {
        candidates = value
    }

    /// 届いたルームを映し、ほかの人が回していたら演出を始める
    private func applyRoom(_ value: Identified<Room>?) {
        room = value?.value
        replayIfDrawnByOthers()
    }

    // MARK: - 自分が回す

    /// レバーが押された。回して演出を始める（`turnLever()` を `Task` で動かす）
    func leverTapped() {
        guard canTurnLever else {
            return
        }
        playTask = Task { [weak self] in
            await self?.turnLever()
        }
    }

    /// ガチャを回す（`drawGacha`）。回転の演出と並べて送り、結果が返って回転が終わったらカプセルを落とす。
    /// 回せないとき（`canTurnLever` でない）は何もしない
    func turnLever() async {
        guard canTurnLever else {
            return
        }
        isDrawing = true
        defer { isDrawing = false }
        drawnByName = nil
        phase = .spinning
        emit(.leverPulled)
        let spin = Task { [weak self] in
            await self?.playSpin()
        }
        let response: DrawGachaResponse
        do {
            response = try await functions.drawGacha(RoomRequest(roomId: roomID))
        } catch {
            spin.cancel()
            phase = .idle
            isDrawing = false
            let appError = AppError.wrapping(error)
            // タイムアウトなどで失敗しても、サーバーでは書き込み済みのことがある。送っている途中に届いた drawn は見送っているので、
            // ここで確かめて再生する（drawn ならトーストは出さない。まだ届いていなければ、届いたときに `applyRoom` が再生する）
            if room?.status == .drawn {
                replayIfDrawnByOthers()
            } else if !appError.isCancellation {
                toasts.show(text: Self.failureMessage(for: appError))
            }
            return
        }
        drawID = response.drawId
        winnerCandidateID = response.candidateId
        if response.alreadyDrawn {
            // 同時に回して先を越された。先に回した人の名前で、同じ結果を見せる
            drawnByName = await drawerName(of: response.drawId)
        } else if let room {
            analytics.log(.gachaDraw(winnerID: response.candidateId, candidates: candidates, room: room))
        }
        await withTaskCancellationHandler {
            await spin.value
        } onCancel: {
            spin.cancel()
        }
        guard !Task.isCancelled else {
            return
        }
        await dispense()
    }

    /// 回せなかったときのトーストの文言。回せない理由が分かるもの（解禁していない・候補が無い・オフラインなど）はその文言、
    /// 通信のエラー・理由の分からないものは「通信できませんでした。もう一度回してください」
    static func failureMessage(for error: AppError) -> String {
        switch error.reason {
        case .roomNotUnlocked, .noCandidates, .roomAlreadyDecided, .roomNotFound, .notRoomMember, .roomClosed, .permissionDenied,
             .offline:
            error.message
        default:
            String(localized: drawFailureMessage)
        }
    }

    // MARK: - ほかの人が回した

    /// 待機中に、ほかの人が回した（ルームが `drawn` で、まだ扱っていない抽選がある）なら演出を始める。
    /// 見終えた抽選なら揺れと落下を飛ばし、取り出し口のカプセルを開けるところから始める
    private func replayIfDrawnByOthers() {
        guard let room, room.status == .drawn, let drawID = room.currentDrawId, !drawID.isEmpty,
              phase == .idle, !isDrawing, self.drawID == nil else {
            return
        }
        self.drawID = drawID
        winnerCandidateID = room.winnerCandidateId
        if seenDraws.hasSeen(drawID: drawID) {
            playTask = Task { [weak self] in
                await self?.openCapsule()
            }
            return
        }
        playTask = Task { [weak self] in
            await self?.replay(drawID: drawID)
        }
    }

    /// ほかの人が回した抽選の演出を再生する（回した人の名前を読んでから、揺れ → 落下 → 開ける）
    private func replay(drawID: String) async {
        drawnByName = await drawerName(of: drawID)
        guard !Task.isCancelled else {
            return
        }
        phase = .spinning
        await playSpin()
        guard !Task.isCancelled else {
            return
        }
        await dispense()
    }

    /// 抽選の記録の、回した人の表示名（読めなければ nil。そのときは「ガラガラ…」で演出する）。
    ///
    /// 自分が回した抽選（送ったのに失敗として返ってきた後に再生するとき）も nil にし、「たくみさんが回しました！」と自分の名前を出さない
    private func drawerName(of drawID: String) async -> String? {
        // 記録は作られた後は変わらないので、最初に届いた値だけを読んで購読をやめる
        var updates = repository.draw(roomID: roomID, drawID: drawID).makeAsyncIterator()
        guard case let .value(draw?)? = await updates.next(), draw.drawnBy != userID else {
            return nil
        }
        return draw.drawnByName
    }

    // MARK: - 演出

    /// 回転中の時間を待ち、0.2 秒ごとに刻みの合図を出す（視差効果を減らすなら待たない）。cancel されたら途中で終わる
    private func playSpin() async {
        guard !reducesMotion else {
            return
        }
        for _ in 0..<GachaTimeline.tickCount {
            guard await wait(GachaTimeline.tickInterval) else {
                return
            }
            emit(.spinTick)
        }
        _ = await wait(GachaTimeline.tickInterval)
    }

    /// カプセルを取り出し口に落とし、底に当たったら合図を出して見終えた抽選として覚え、少し見せてから開ける
    private func dispense() async {
        guard let drawID else {
            return
        }
        phase = .dropping
        if !reducesMotion {
            guard await wait(GachaTimeline.landingDelay) else {
                return
            }
        }
        emit(.capsuleLanded)
        seenDraws.markSeen(drawID: drawID)
        if !reducesMotion {
            guard await wait(GachaTimeline.openDelay) else {
                return
            }
        }
        await openCapsule()
    }

    // MARK: - 開ける

    /// カプセルを開ける（`open` の 0.5 秒の後に開け終える）。cancel されたら途中で終わる
    private func openCapsule() async {
        guard !Task.isCancelled else {
            return
        }
        phase = .opening
        if !reducesMotion {
            guard await wait(GachaTimeline.openDuration) else {
                return
            }
        }
        emit(.capsuleOpened)
        phase = .opened
    }

    // MARK: - 道具

    /// 秒数だけ待つ。cancel されたら false
    private func wait(_ seconds: Double) async -> Bool {
        do {
            try await sleep(.seconds(seconds))
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    /// 合図を出す
    private func emit(_ value: GachaCue) {
        cueSequence += 1
        cue = GachaCueEvent(sequence: cueSequence, cue: value)
        cueHandler?(value)
    }
}

// クラスの本体が SwiftLint の `type_body_length` を超えないよう、読むだけの計算を分ける
extension GachaModel {
    /// タイトルとサブ文言。作成者が抽選の前に途中で終了したら「このルームは終了しています」（Discussion #155）
    var caption: GachaCaption {
        GachaCaption.make(
            phase: phase,
            drawnByName: drawnByName,
            status: room?.status,
            isReroll: isReroll,
            capsuleCount: capsuleCount,
            endedWithoutResult: room.map(RoomClosing.endedWithoutResult) ?? false
        )
    }
}
