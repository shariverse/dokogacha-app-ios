//
//  CandidateDetailModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-10 候補の詳細（シート）の状態と操作（02 の F-11・03 の S-10）。
///
/// ルーム・メンバー・候補の購読といいね（F-20）は、S-07 と同じ扱いにするため `RoomModel` をそのまま中に持って使う
/// （候補の行の値・出やすさ・楽観的更新・失敗で戻してトースト、をここで書き直さない）。`lastSeenAt` は書かない
/// （02 の §3.3 の「ルーム画面を離れたとき」は S-07 が書く。S-10 はその上に重ねるシート）。
///
/// 削除（F-11）は確認のダイアログを挟み、Callable の `deleteCandidate` を呼ぶ:
/// - 出すのは投稿した本人か作成者で、ルームが `open`・`unlocked` のとき（`CandidatePermission.canDelete`。ガチャで当選した候補は出さない）
/// - 送っている途中は二度押しを受け付けず、画面は閉じる操作（閉じるボタン・下スワイプ）を止める
/// - 通信エラーや、権限・状態で断られたとき（`AppError` の文言）はトーストを出し、シートは閉じない
/// - 成功したら `shouldClose` を立て、画面はシートを閉じて S-07 に戻る
///
/// 候補が購読から消えたとき（ほかの人が削除した・自分が削除した）・ルームが無くなったときも `shouldClose` を立てる。
///
/// 報告（F-14）は「…」の「この投稿を報告」から理由を選ばせ、Callable の `reportCandidate` を呼ぶ:
/// - 出すのは他人の投稿で、まだ報告していないとき（`CandidatePermission.canReport`・`ReportedCandidateStore`）
/// - 成功したら（もう報告済みと返ったときも）端末に覚え、トースト「報告しました」。ひとことと参考 URL を隠す（`ReportedContent`）
/// - 送っている途中は二度押しを受け付けず、シートを閉じる操作を止める。失敗したら `AppError` の文言のトースト
@Observable
final class CandidateDetailModel {
    /// 報告できたときのトースト（02・03 に文言が無いので、ここで決める）
    static let reportedMessage: LocalizedStringResource = "報告しました"

    /// 候補の ID
    let candidateID: String
    /// ルーム・メンバー・候補の購読といいね（S-07 と同じもの）
    let room: RoomModel

    /// 削除の確認のダイアログを出しているか
    var isConfirmingDelete = false
    /// 削除を送っている途中か（二重に送らない・シートを閉じさせない）
    private(set) var isDeleting = false
    /// 削除できたか
    private(set) var didDelete = false
    /// 報告の理由を選ぶダイアログを出しているか
    var isChoosingReportReason = false
    /// 報告を送っている途中か（二重に送らない・シートを閉じさせない）
    private(set) var isReporting = false

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let mapOpener: any MapOpener
    @ObservationIgnored private let toasts: DGToastCenter
    /// 確認のダイアログから始めた削除。画面が消えたら（`cancelSending`）止める
    @ObservationIgnored private var deleteTask: Task<Void, Never>?
    /// 理由のダイアログから始めた報告。画面が消えたら（`cancelSending`）止める
    @ObservationIgnored private var reportTask: Task<Void, Never>?

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - candidateID: 候補の ID
    ///   - userID: 自分の uid
    ///   - repository: 購読といいねの窓口（Firebase か擬似のサーバー）
    ///   - functions: `deleteCandidate`・`reportCandidate` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 失敗を出すトーストの窓口（シートの中に重ねるもの）
    ///   - mapOpener: 「マップで開く」の窓口（テストでは呼び出しを記録するもの）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    ///   - reportedCandidates: 自分が報告した候補（報告できたら覚え、ひとこととURLを隠す）
    ///   - analytics: Analytics のイベント（05 の §9。いいね）を送る窓口
    init(
        roomID: String,
        candidateID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        mapOpener: any MapOpener = AppleMapsOpener(),
        resubscribeDelay: ResubscribeDelay = .standard,
        reportedCandidates: any ReportedCandidateStore = InMemoryReportedCandidateStore(),
        analytics: any AnalyticsService = DisabledAnalyticsService()
    ) {
        self.candidateID = candidateID
        room = RoomModel(
            roomID: roomID,
            userID: userID,
            repository: repository,
            functions: functions,
            toasts: toasts,
            resubscribeDelay: resubscribeDelay,
            reportedCandidates: reportedCandidates,
            analytics: analytics
        )
        self.functions = functions
        self.mapOpener = mapOpener
        self.toasts = toasts
    }

    // MARK: - 表示の値

    /// 候補（購読の値。まだ届いていない・消えたなら nil）
    var candidate: Identified<Candidate>? {
        room.candidates.first { $0.id == candidateID }
    }

    /// 候補カードの行の値（S-07 と同じ。送っている途中のいいねを映したもの）
    var row: RoomCandidateRow? {
        room.rows.first { $0.id == candidateID }
    }

    /// 場所（地図と「マップで開く」に使う）
    var place: Place? {
        candidate?.place
    }

    /// 参考 URL（`http`・`https` で開けるものだけ。無い・自分が報告した候補なら nil）
    var referenceURL: URL? {
        ReportedContent.visibleURL(candidate?.url, isReported: isReported)
    }

    /// 自分がこの候補を報告したか（ひとこととURLを隠し、「この投稿を報告」を出さない）
    var isReported: Bool {
        room.reportedCandidates.hasReported(roomID: room.roomID, candidateID: candidateID)
    }

    /// いいねした人の名前（いいねした順。メンバーをまだ読めていない人・退出した人は除く）
    var likerNames: [String] {
        row?.likers.map(\.name).filter { !$0.isEmpty } ?? []
    }

    /// 「この候補を削除」を出すか（投稿した本人か作成者で、ルームが `open`・`unlocked`。ガチャで当選した候補は出さない）
    var canDelete: Bool {
        guard let candidate, let current = room.room else {
            return false
        }
        return CandidatePermission.canDelete(
            postedBy: candidate.postedBy,
            ownerID: current.ownerId,
            roomStatus: current.status,
            userID: room.userID,
            isDrawn: CandidatePermission.isDrawn(candidateID: candidateID, in: current)
        )
    }

    /// 「…」のメニューに「この投稿を報告」を出すか（他人の投稿で、まだ報告していないとき）
    var canReport: Bool {
        guard let candidate, !isReported else {
            return false
        }
        return CandidatePermission.canReport(postedBy: candidate.postedBy, userID: room.userID)
    }

    /// 送っている途中の操作があるか（閉じるボタンと下スワイプを止める）
    var isSending: Bool {
        isDeleting || isReporting
    }

    /// シートを閉じるか（削除できた・候補が購読から消えた・ルームが無くなった）
    var shouldClose: Bool {
        didDelete || room.loadState == .missing || (room.hasLoadedCandidates && candidate == nil)
    }

    // MARK: - 購読

    /// ルーム・メンバー・候補を購読し、呼んだ `Task` が cancel されるまで続ける（画面の `.task` から呼ぶ）
    func observe() async {
        await room.observe()
    }

    // MARK: - いいね・マップ・報告

    /// いいねボタンが押された（S-07 と同じ。押せない候補・送っている途中なら何もしない）
    func likeTapped() {
        room.likeTapped(candidateID)
    }

    /// 「マップで開く」が押された。場所の座標と名前で地図のアプリを開く
    func openInMapsTapped() {
        guard let place else {
            return
        }
        mapOpener.open(place)
    }

    /// 「この投稿を報告」が押された。理由を選ぶダイアログを出す（報告できないとき・送っている途中なら出さない）
    func reportTapped() {
        guard canReport, !isReporting else {
            return
        }
        isChoosingReportReason = true
    }

    /// 理由のダイアログで理由が選ばれた。報告を始める（送っている途中なら何もしない）
    func reportReasonChosen(_ reason: ReportReason) {
        guard reportTask == nil else {
            return
        }
        reportTask = Task { [weak self] in
            await self?.report(reason: reason)
            if !Task.isCancelled {
                self?.reportTask = nil
            }
        }
    }

    /// 候補を報告する（`reportCandidate`）。報告できない・送っている途中なら何もしない。
    ///
    /// 成功したら（サーバーがもう報告済みと返したときも）報告した候補として覚え、トースト「報告しました」を出す。
    /// 覚えるのは cancel を確かめる前にする（サーバーには報告が残っているので、画面を閉じた後でも端末で隠す。PR #91 の持ち越し）。
    /// 失敗したら `AppError` の文言のトーストを出す（cancel のときは出さない）
    func report(reason: ReportReason) async {
        guard canReport, !isReporting else {
            return
        }
        isReporting = true
        defer { isReporting = false }
        do {
            try await functions.reportCandidate(
                ReportCandidateRequest(roomId: room.roomID, candidateId: candidateID, reason: reason)
            )
            room.reportedCandidates.markReported(roomID: room.roomID, candidateID: candidateID)
            guard !Task.isCancelled else {
                return
            }
            toasts.show(Self.reportedMessage)
        } catch {
            toasts.showFailure(error)
        }
    }

    // MARK: - 削除

    /// 「この候補を削除」が押された。確認のダイアログを出す（削除できないとき・送っている途中なら出さない）
    func deleteTapped() {
        guard canDelete, !isDeleting, !didDelete else {
            return
        }
        isConfirmingDelete = true
    }

    /// 確認のダイアログで「削除する」が押された。削除を始める（送っている途中なら何もしない）。
    ///
    /// `isDeleting` は Task が動き出してから立つので、Task が始まる前に続けて押されたときのために、
    /// 始めた Task が残っている間も受け付けない
    func confirmDeleteTapped() {
        guard deleteTask == nil else {
            return
        }
        deleteTask = Task { [weak self] in
            await self?.delete()
            // cancel された Task は `cancelSending` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                self?.deleteTask = nil
            }
        }
    }

    /// 画面が消えたとき、送っている途中の削除と報告を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）
    func cancelSending() {
        deleteTask?.cancel()
        deleteTask = nil
        reportTask?.cancel()
        reportTask = nil
    }

    /// 候補を削除する（`deleteCandidate`）。削除できない状態・送っている途中なら何もしない。
    ///
    /// 成功したら `didDelete` を立てる。失敗したら `AppError` の文言のトーストを出す（cancel のときは出さない）
    func delete() async {
        guard canDelete, !isDeleting, !didDelete else {
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await functions.deleteCandidate(CandidateRequest(roomId: room.roomID, candidateId: candidateID))
            guard !Task.isCancelled else {
                return
            }
            didDelete = true
        } catch {
            toasts.showFailure(error)
        }
    }
}
