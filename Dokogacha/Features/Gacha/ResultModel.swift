//
//  ResultModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-14 結果（行き先きっぷ）の状態と操作（02 の §6.3 F-42・03 の S-14）。
///
/// ルーム・メンバー・候補の購読は、S-07 と同じ値（候補の行・投稿者の表示）にするため `RoomModel` をそのまま中に持って使う
/// （`CandidateDetailModel` と同じ）。抽選の記録（`draws/{drawId}`）は作られた後は変わらないので、最初に届いた値だけを読んで購読をやめる。
/// 購読は画面の `.task` で `observe()` を呼び、画面が消えたら止まる。
///
/// - 「マップで開く」: 当選した候補の座標と名前で地図のアプリを開く（候補は座標が必須なので、名前で検索する場合分けは要らない。候補を読めるまでは押せない）
/// - 「きっぷを共有」: 画面が `TicketShareImage` を共有シートに渡す（画像は共有するときに作る）
/// - 引き直し（F-43）: 欄に出すものは `rerollPanel`（`RerollPanelState`）。提案・投票は Callable（`proposeReroll`・`voteReroll`）で送り、
///   結果はルームの購読で受け取る（可決すると `unlocked` に戻り、画面は「もう一度引けます」から S-13 に進む）
/// - `closed` のルームは閲覧のみ（引き直し・「この行き先で決定」F-44（タスク 30）は出さない）
@Observable
final class ResultModel {
    /// 読み込みの状態
    enum LoadState: Equatable {
        /// まだ抽選の記録・ルーム・当選した候補が届いていない
        case loading
        /// きっぷを出せる
        case loaded
        /// ルームが無い・読めなくなった（削除された・メンバーから外れた）
        case missing
    }

    /// 抽選の ID
    let drawID: String
    /// ルーム・メンバー・候補の購読（S-07 と同じもの）
    let room: RoomModel
    /// 届いた抽選の記録（まだなら nil）
    private(set) var draw: Draw?
    /// 引き直しの提案・投票を送っている途中か（送っている間はボタンを押せない）
    private(set) var isSendingReroll = false

    @ObservationIgnored private let repository: any RoomRepository
    @ObservationIgnored private let functions: any FunctionsClient
    /// 送っている途中の引き直しの提案・投票（画面が消えたら `cancelSending` で止める）
    @ObservationIgnored private var rerollTask: Task<Void, Never>?
    @ObservationIgnored private let mapOpener: any MapOpener
    @ObservationIgnored private let toasts: DGToastCenter
    @ObservationIgnored private let resubscribeDelay: ResubscribeDelay

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - drawID: 抽選の ID（`rooms.currentDrawId`）
    ///   - userID: 自分の uid
    ///   - repository: 購読の窓口（Firebase か擬似のサーバー）
    ///   - functions: Callable の窓口（引き直しの提案・投票。終了はタスク 30 で使う）
    ///   - toasts: 失敗を出すトーストの窓口（フルスクリーンカバーの中に重ねるもの）
    ///   - mapOpener: 「マップで開く」の窓口（テストでは呼び出しを記録するもの）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        roomID: String,
        drawID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        mapOpener: any MapOpener = AppleMapsOpener(),
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        self.drawID = drawID
        room = RoomModel(
            roomID: roomID,
            userID: userID,
            repository: repository,
            functions: functions,
            toasts: toasts,
            resubscribeDelay: resubscribeDelay
        )
        self.repository = repository
        self.functions = functions
        self.mapOpener = mapOpener
        self.toasts = toasts
        self.resubscribeDelay = resubscribeDelay
    }

    // MARK: - 表示の値

    /// 当選した候補の行（抽選の記録と候補が届くまでは nil）
    var winner: RoomCandidateRow? {
        guard let draw else {
            return nil
        }
        return room.rows.first { $0.id == draw.candidateId }
    }

    /// きっぷに出す値（そろうまでは nil）
    var ticket: ResultTicket? {
        guard let draw, let current = room.room, let winner else {
            return nil
        }
        return ResultTicket.make(draw: draw, room: current, winner: winner)
    }

    /// 読み込みの状態
    var loadState: LoadState {
        if room.loadState == .missing {
            return .missing
        }
        return ticket == nil ? .loading : .loaded
    }

    /// 閲覧のみか（`closed` のルーム。03 の S-14「閲覧のみのときは 5・6 を表示しない」）
    var isReadOnly: Bool {
        room.room?.status == .closed
    }

    /// 引き直しの欄に出すもの（03 の S-14 の 5）
    var rerollPanel: RerollPanelState {
        RerollPanelState.make(room: room.room, drawID: drawID, userID: room.userID)
    }

    /// 「マップで開く」を押せるか（当選した候補を読めている）
    var canOpenMap: Bool {
        winnerPlace != nil
    }

    /// 当選した場所
    private var winnerPlace: Place? {
        guard let draw else {
            return nil
        }
        return room.candidates.first { $0.id == draw.candidateId }?.place
    }

    // MARK: - 購読

    /// ルーム・メンバー・候補と抽選の記録を購読し、呼んだ `Task` が cancel されるまで続ける（画面の `.task` から呼ぶ）
    func observe() async {
        async let rooms: Void = room.observe()
        async let record: Void = loadDraw()
        _ = await (rooms, record)
    }

    /// 抽選の記録を、最初に届いた値まで読む。失敗したら（読めない・通信エラー）少し待って読み直す。
    ///
    /// permission-denied はルームの購読が「ルームが見つかりません」にするので、ここでは読み直さずトーストも出さない
    private func loadDraw() async {
        var isFailing = false
        while !Task.isCancelled {
            for await update in repository.draw(roomID: room.roomID, drawID: drawID) {
                guard !Task.isCancelled else {
                    return
                }
                switch update {
                case let .value(value?):
                    draw = value
                    return
                case .value(nil):
                    continue
                case let .failure(error) where error.isPermissionDenied:
                    return
                case let .failure(error):
                    if !isFailing, !error.isCancellation {
                        toasts.show(text: error.message)
                    }
                    isFailing = true
                }
            }
            guard await resubscribeDelay.wait() else {
                return
            }
        }
    }

    // MARK: - 操作

    /// 「マップで開く」が押された。当選した場所の座標と名前で地図のアプリを開く（読めていなければ何もしない）
    func openInMapsTapped() {
        guard let winnerPlace else {
            return
        }
        mapOpener.open(winnerPlace)
    }

    // MARK: - 引き直し（F-43）

    /// 「引き直しを提案（過半数の賛成で1回まで）」が押された。提案を送る（送っている途中・提案できないときは何もしない）
    func proposeRerollTapped() {
        start { model in
            await model.proposeReroll()
        }
    }

    /// 投票の「賛成」「反対」が押された。票を送る（送っている途中・投票中でない・同じ票なら何もしない）
    /// - Parameter approve: 賛成なら true
    func voteTapped(approve: Bool) {
        start { model in
            await model.vote(approve: approve)
        }
    }

    /// 引き直しを提案する（`proposeReroll`）。提案者は自動で賛成になる。失敗したら `AppError` の文言のトーストを出す
    func proposeReroll() async {
        guard rerollPanel == .proposable, !isSendingReroll else {
            return
        }
        await sendReroll {
            try await functions.proposeReroll(RoomRequest(roomId: room.roomID))
        }
    }

    /// 引き直しに投票する（`voteReroll`）。投票中だけ送り、今の票と同じなら送らない。失敗したら `AppError` の文言のトーストを出す
    /// - Parameter approve: 賛成なら true
    func vote(approve: Bool) async {
        guard case let .voting(_, _, myVote) = rerollPanel, myVote != (approve ? .approve : .reject), !isSendingReroll else {
            return
        }
        await sendReroll {
            try await functions.voteReroll(VoteRerollRequest(roomId: room.roomID, approve: approve))
        }
    }

    /// 画面が消えたとき、送っている途中の提案・投票を止める（cancel ではトーストを出さない）
    func cancelSending() {
        rerollTask?.cancel()
        rerollTask = nil
    }

    /// 提案・投票の Task を始める。始めた Task が残っている間は受け付けない（二重に送らない）
    private func start(_ action: @escaping (ResultModel) async -> Void) {
        guard rerollTask == nil else {
            return
        }
        rerollTask = Task { [weak self] in
            guard let self else {
                return
            }
            await action(self)
            // cancel された Task は `cancelSending` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                rerollTask = nil
            }
        }
    }

    /// 送っている途中の印を立てて Callable を呼び、失敗したら `AppError` の文言のトーストを出す（cancel・画面が消えた後は出さない）
    private func sendReroll(_ operation: () async throws -> Void) async {
        isSendingReroll = true
        defer { isSendingReroll = false }
        do {
            try await operation()
        } catch {
            let appError = AppError.wrapping(error)
            if !appError.isCancellation, !Task.isCancelled {
                toasts.show(text: appError.message)
            }
        }
    }
}
