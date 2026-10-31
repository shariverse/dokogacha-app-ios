//
//  MembersModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-11 メンバー一覧（シート）の状態と操作（02 の F-05・03 の S-11）。
///
/// ルーム・メンバー・候補の購読は、S-07 と同じ値（準備OKの楽観的な表示・ルームが無くなったときの `.missing`）を使うため
/// `RoomModel` をそのまま中に持って使う（S-10 の `CandidateDetailModel` と同じ形）。`lastSeenAt` は書かない。
///
/// - 行はメンバーの参加の早い順。アバター・名前・準備OK・投稿数・「作成者」の印を出す
/// - 作成者は、自分以外のメンバーを削除できる（行のスワイプ → 確認 → Callable の `removeMember`）。作成者は削除できない
/// - 作成者以外は「ルームから退出」できる（確認 → Callable の `leaveRoom` → 成功したらホームへ）。作成者には出さない（F-05「作成者は退出できない」）
/// - 「招待する」は S-04 と同じ文面を共有シートで送る。参加できる状態（`open`・`unlocked`）で満員でないときだけ押せる
///
/// 退出・削除は二重に送らず、送っている途中はシートを閉じさせない。失敗したら `AppError` の文言のトーストを出す（シートは閉じない）。
/// ルームが無くなった・自分が外されたとき（購読が `.missing`）は `shouldClose` を立て、画面はシートを閉じる。
@Observable
final class MembersModel {
    /// 一覧の 1 行
    struct Row: Identifiable, Equatable {
        /// メンバーの uid
        let id: String
        /// 表示名
        let name: String
        /// アバターの色の位置（`AvatarPalette` の色。知らない色なら nil）
        let avatarColorIndex: Int?
        /// 準備OKか（自分は送っている途中の値）
        let isReady: Bool
        /// このルームに投稿した候補の数
        let postCount: Int
        /// 作成者か
        let isOwner: Bool
        /// 自分か
        let isMe: Bool
        /// 自分が削除できるか（自分が作成者で、この行が自分以外）
        let canRemove: Bool
    }

    /// 確認のダイアログから始める操作
    private enum Action {
        /// 自分が退出する
        case leave
        /// 作成者がメンバーを削除する
        case remove(memberID: String)
    }

    /// ルーム・メンバー・候補の購読（S-07 と同じもの）
    let room: RoomModel

    /// 退出の確認のダイアログを出しているか
    var isConfirmingLeave = false
    /// 削除の確認を出しているメンバー（出していなければ nil）
    var memberPendingRemoval: Row?
    /// 退出・削除を送っている途中か（二重に送らない・シートを閉じさせない）
    private(set) var isSending = false
    /// 退出できたか（入ったら画面はホームへ戻る）
    private(set) var didLeave = false

    /// 送っている途中で、シートを閉じさせないか（確認で押してから送り終えるまで。Task が動き出す前も含める。PR #55 の持ち越し）
    var locksNavigation: Bool {
        isSending || sendTask != nil
    }

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// 確認のダイアログから始めた退出・削除。画面が消えたら（`cancelSending`）止める
    private var sendTask: Task<Void, Never>?

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - userID: 自分の uid
    ///   - repository: 購読の窓口（Firebase か擬似のサーバー）
    ///   - functions: `leaveRoom`・`removeMember` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 失敗を出すトーストの窓口（シートの中に重ねるもの）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        resubscribeDelay: ResubscribeDelay = .standard
    ) {
        room = RoomModel(
            roomID: roomID,
            userID: userID,
            repository: repository,
            functions: functions,
            toasts: toasts,
            resubscribeDelay: resubscribeDelay
        )
        self.functions = functions
        self.toasts = toasts
    }

    // MARK: - 表示の値

    /// メンバーの行（参加の早い順）
    var rows: [Row] {
        guard let current = room.room else {
            return []
        }
        let postCounts = Dictionary(grouping: room.candidates) { $0.postedBy }.mapValues(\.count)
        let iAmOwner = current.ownerId == room.userID
        return room.displayedMembers.map { member in
            let isOwner = member.id == current.ownerId
            return Row(
                id: member.id,
                name: member.displayName,
                avatarColorIndex: AvatarPalette.index(of: member.avatarColor),
                isReady: member.ready,
                postCount: postCounts[member.id] ?? 0,
                isOwner: isOwner,
                isMe: member.id == room.userID,
                canRemove: iAmOwner && !isOwner && member.id != room.userID
            )
        }
    }

    /// メンバーの人数
    var memberCount: Int {
        room.memberCount
    }

    /// 1 ルームに参加できる人数（「最大20人」）
    var maxMembers: Int {
        DomainConstants.Limits.maxMembers
    }

    /// 「ルームから退出」を出すか（作成者以外。F-05「作成者は退出できない」）。ルームが届くまでは出さない
    var canLeave: Bool {
        guard let current = room.room else {
            return false
        }
        return current.ownerId != room.userID
    }

    /// 「招待する」で送る文面（S-04 と同じ）。参加できない状態（`drawn`・`closed`）・満員（20 人）・ルームが届くまでは nil
    /// （S-07 の招待の「＋」と同じ判定。`RoomModel.inviteAvailability`）
    var shareMessage: String? {
        room.inviteDestination.map { InviteModel.shareMessage(roomName: $0.roomName, inviteCode: $0.inviteCode) }
    }

    /// シートを閉じるか（ルームが無くなった・自分が外された）。
    ///
    /// 退出を送っている途中・退出できたときは閉じない（退出すると購読も読めなくなるが、そのときは `didLeave` で親がホームへ戻す）
    var shouldClose: Bool {
        room.loadState == .missing && !isSending && !didLeave
    }

    // MARK: - 購読

    /// ルーム・メンバー・候補を購読し、呼んだ `Task` が cancel されるまで続ける（画面の `.task` から呼ぶ）
    func observe() async {
        await room.observe()
    }

    // MARK: - 退出

    /// 「ルームから退出」が押された。確認のダイアログを出す（退出できないとき・送っている途中なら出さない）
    func leaveTapped() {
        guard canLeave, !isSending, !didLeave else {
            return
        }
        isConfirmingLeave = true
    }

    /// 確認のダイアログで「退出する」が押された。退出を始める（始めた Task が残っている間は受け付けない）
    func confirmLeaveTapped() {
        start(.leave)
    }

    /// ルームから退出する（`leaveRoom`）。退出できない・送っている途中なら何もしない。
    ///
    /// 成功したら `didLeave` を立てる。失敗したら `AppError` の文言のトーストを出す（cancel のときは出さない）
    func leave() async {
        guard canLeave, !isSending, !didLeave else {
            return
        }
        await send {
            try await functions.leaveRoom(RoomRequest(roomId: room.roomID))
            didLeave = true
        }
    }

    // MARK: - 削除

    /// 行の「削除」が押された（作成者のスワイプ）。確認のダイアログを出す（削除できない行・送っている途中なら出さない）
    func removeTapped(_ row: Row) {
        guard row.canRemove, !isSending else {
            return
        }
        memberPendingRemoval = row
    }

    /// 削除の確認を出しているメンバーが一覧から消えた（退出した・ほかの端末で削除した）・削除できなくなったら、確認を閉じる。
    ///
    /// ダイアログはそのメンバーの行に付くので、行が消えるとダイアログも消える。確認中のメンバーを残さない。画面が一覧の変化で呼ぶ
    func closeUnavailableRemoval() {
        guard let pending = memberPendingRemoval else {
            return
        }
        if !rows.contains(where: { $0.id == pending.id && $0.canRemove }) {
            memberPendingRemoval = nil
        }
    }

    /// 確認のダイアログで「削除する」が押された。そのメンバーの削除を始める（始めた Task が残っている間は受け付けない）
    /// - Parameter row: 確認のダイアログに出していたメンバー（ダイアログが閉じて `memberPendingRemoval` が消えた後でも使えるように受け取る）
    func confirmRemoveTapped(_ row: Row) {
        memberPendingRemoval = nil
        start(.remove(memberID: row.id))
    }

    /// メンバーを削除する（`removeMember`）。作成者でない・作成者を指した・送っている途中なら何もしない。
    ///
    /// 成功したら何もしない（購読からそのメンバーが消える）。失敗したら `AppError` の文言のトーストを出す
    func remove(memberID: String) async {
        guard !isSending, rows.contains(where: { $0.id == memberID && $0.canRemove }) else {
            return
        }
        await send {
            try await functions.removeMember(RemoveMemberRequest(roomId: room.roomID, memberId: memberID))
        }
    }

    // MARK: - 送信の共通

    /// 画面が消えたとき、送っている途中の退出・削除を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）
    func cancelSending() {
        sendTask?.cancel()
        sendTask = nil
    }

    /// 退出・削除の Task を始める。`isSending` は Task が動き出してから立つので、始めた Task が残っている間も受け付けない
    private func start(_ action: Action) {
        guard sendTask == nil else {
            return
        }
        sendTask = Task { [weak self] in
            switch action {
            case .leave:
                await self?.leave()
            case let .remove(memberID):
                await self?.remove(memberID: memberID)
            }
            // cancel された Task は `cancelSending` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                self?.sendTask = nil
            }
        }
    }

    /// 送っている途中の印を立てて Callable を呼び、失敗したら `AppError` の文言のトーストを出す（cancel・画面が消えた後は出さない）
    private func send(_ operation: () async throws -> Void) async {
        isSending = true
        defer { isSending = false }
        do {
            try await operation()
        } catch {
            toasts.showFailure(error)
        }
    }
}
