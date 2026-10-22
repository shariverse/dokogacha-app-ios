//
//  JoinConfirmModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-06 参加確認（F-04）の状態と操作。
///
/// 表示する値は S-05 で `previewRoom` が返したもの（メンバー以外はルームを購読できないため、ここでは購読しない）。
/// 「参加する」で Callable の `joinRoom` を呼び、成功したら `joinedRoomID` に参加したルームの ID を入れる（画面がそれを見てルームへ進む）。
/// 確かめてから押すまでの間に満員・決定後になったときなど、失敗はトースト（文言は `AppError`）で出し、もう一度押せるようにする。
@Observable
final class JoinConfirmModel {
    /// 確かめたルームの値
    let preview: RoomPreview
    /// 参加に送る招待コード
    let inviteCode: InviteCode

    /// 参加を送っている途中か（二重に送らないため、ボタンを止める）
    private(set) var isJoining = false
    /// 参加したルームの ID。入ったら画面はルーム（S-07）へ進む
    private(set) var joinedRoomID: String?

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// どの道で参加したか（`room_join` の `via`）
    @ObservationIgnored private let via: RoomJoinVia
    /// 参加できたら `room_join` を送る窓口
    @ObservationIgnored private let analytics: any AnalyticsService
    /// ボタンから始めた参加。画面が消えたら（`cancelJoin`）止める。始めた時点から戻る・閉じる操作を止めるので、画面からも見る
    private var joinTask: Task<Void, Never>?

    /// - Parameters:
    ///   - destination: 確かめたルームと招待コード
    ///   - functions: `joinRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 失敗を出すトーストの窓口
    ///   - via: どの道で参加の画面を開いたか（招待リンク・招待コード・前回のメンバーへの招待の通知）
    ///   - analytics: Analytics のイベント（05 の §9）を送る窓口
    init(
        destination: JoinConfirmDestination,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        via: RoomJoinVia = .code,
        analytics: any AnalyticsService = DisabledAnalyticsService()
    ) {
        preview = destination.preview
        inviteCode = destination.inviteCode
        self.functions = functions
        self.toasts = toasts
        self.via = via
        self.analytics = analytics
    }

    /// 「参加する」を押せるか（送っている途中・参加済みのときは押せない）
    var canJoin: Bool {
        !isJoining && joinedRoomID == nil
    }

    /// 参加を送っている途中か（押してから送り終えるまで。戻る・閉じる・下スワイプを止める。PR #49 の持ち越し）。
    ///
    /// 送っている途中に閉じると、サーバーでは参加済みになるのに画面はルームへ進まない
    var locksNavigation: Bool {
        isJoining || joinTask != nil
    }

    /// 「参加する」が押された。参加を始める（送っている途中なら何もしない）。
    ///
    /// `isJoining` は Task が動き出してから立つので、Task が始まる前に続けて押されたときのために、
    /// 始めた Task が残っている間も押せないことにする
    func joinTapped() {
        guard canJoin, joinTask == nil else {
            return
        }
        joinTask = Task {
            await join()
            // cancel された Task は `cancelJoin` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                joinTask = nil
            }
        }
    }

    /// 画面が消えたとき、送っている途中の参加を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）。
    ///
    /// Task は self を持つので、画面の `onDisappear` から必ず呼ぶ（Model の `deinit` では止められない）
    func cancelJoin() {
        joinTask?.cancel()
        joinTask = nil
    }

    /// ルームに参加する。押せない状態なら何もしない。
    ///
    /// 成功したら（もとからメンバーだったときも）`joinedRoomID` を入れる。失敗したらトーストを出す。
    /// cancel（画面を閉じた）のときは、結果によらず何もしない
    func join() async {
        guard canJoin else {
            return
        }
        isJoining = true
        defer { isJoining = false }
        do {
            let response = try await functions.joinRoom(JoinRoomRequest(inviteCode: inviteCode.value))
            guard !Task.isCancelled else {
                return
            }
            joinedRoomID = response.roomId
            if !response.alreadyMember {
                analytics.log(.roomJoin(via: via))
            }
        } catch {
            toasts.showFailure(error)
        }
    }
}
