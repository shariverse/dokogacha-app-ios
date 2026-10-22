//
//  RoomSettingsModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-12 ルーム設定（シート。作成者だけ）の状態と操作（02 の F-03・03 の S-12）。
///
/// ルームの購読は、S-07 と同じ値（ルームが無くなったときの `.missing`）を使うため `RoomModel` をそのまま中に持って使う。
/// 入力は「触った項目だけ」を持ち（`edited*`）、触っていない項目は購読で届いた今の設定を出す（ルームが届く前に初期値を決めずに済み、
/// 保存した後に届いた値もそのまま映る）。
///
/// F-03 の変更ルールを画面でも守る（サーバーの `updateRoomSettings` も同じ規則で確かめる）:
/// - 変えられるのは作成者だけ。`closed` のルームはどの項目も変えられない
/// - ルーム名: いつでも（1〜20 文字。S-03 と同じ検証）
/// - 投稿数: 引き上げのみ（Stepper の下限を今の値にする。03 の S-12「現在値未満は選べない」）
/// - 解禁の条件（締切日時を含む）: `open` のときだけ
/// - いいねの効き方: `open`・`unlocked` のときだけ
/// 変えられない項目は今の設定を出して無効にし、送らない。今と同じ値の項目も送らない（変えた項目だけを `UpdateRoomSettingsRequest` に入れる）。
///
/// 締切日時の範囲は S-03 と同じく `DeadlineSelection` で持ち、送る直前と前面に戻ったとき（`refreshDeadlineRange()`）に計算し直す。
/// まだ触っていない今の締切日時は範囲の外でも変えない（送らないので断られない）。
///
/// 保存は二重に送らず、送っている途中はシートを閉じさせない。失敗したら `AppError` の文言のトーストを出し、入力を残す。
/// 成功したら `didSave` を立て、画面は親に知らせてシートを閉じる。ルームが無くなったら `shouldClose` を立てる。
@Observable
final class RoomSettingsModel {
    /// 項目を変えられない理由（画面の補足に出す）
    enum LockReason: Equatable {
        /// 作成者ではない
        case notOwner
        /// ルームが終了している
        case closed
        /// 今の状態では変えられない（解禁の条件は `open` だけ・いいねの効き方は `open`・`unlocked` だけ）
        case status
    }

    /// ルーム名の文字数の範囲（02 の §2.2「1〜20文字」）
    static let nameLength = DomainConstants.Limits.roomNameLength
    /// 1 人あたりの投稿数の範囲（02 の §2.2「1〜10件」）
    static let postLimitRange = DomainConstants.Limits.postLimitRange
    /// いいねの効き方を変えられる状態（02 の F-03「open/unlocked のときのみ」）
    static let likeModeEditableStatuses: Set<RoomStatus> = [.open, .unlocked]

    /// ルームの購読（S-07 と同じもの）
    let room: RoomModel

    /// 触ったルーム名（触っていなければ nil）
    private var editedName: String?
    /// 触った投稿数（触っていなければ nil）
    private var editedPostLimit: Int?
    /// 触った解禁の条件（触っていなければ nil）
    private var editedUnlockRule: UnlockRule?
    /// 触ったいいねの効き方（触っていなければ nil）
    private var editedLikeMode: LikeMode?
    /// 締切日時のピッカーの値と範囲（今の締切日時が無い・触ったときに使う）
    private var deadlineSelection: DeadlineSelection
    /// 締切日時を触ったか
    private var isDeadlineEdited = false

    /// 保存を送っている途中か（二重に送らない・シートを閉じさせない）
    private(set) var isSaving = false
    /// 保存できたか（入ったら画面はシートを閉じる）
    private(set) var didSave = false

    /// 送っている途中で、シートを閉じさせないか（「保存」を押してから送り終えるまで。Task が動き出す前も含める。PR #55 の持ち越し）
    var locksNavigation: Bool {
        isSaving || saveTask != nil
    }

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// 今の時刻（締切の範囲を計算し直すたびに読む）
    @ObservationIgnored private let clock: () -> Date
    /// 「保存」から始めた保存。画面が消えたら（`cancelSave`）止める
    private var saveTask: Task<Void, Never>?

    /// - Parameters:
    ///   - roomID: ルームの ID
    ///   - userID: 自分の uid
    ///   - repository: 購読の窓口（Firebase か擬似のサーバー）
    ///   - functions: `updateRoomSettings` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 失敗を出すトーストの窓口（シートの中に重ねるもの）
    ///   - clock: 今の時刻（締切の範囲と、条件を「締切日時」に変えたときの初期値を決める。テストで進める）
    ///   - calendar: 暦（締切の初期値「3日後の21:00」を端末のタイムゾーンで決める）
    ///   - resubscribeDelay: 購読が失敗したとき、やり直すまでの待ち方（テストでは待たないものを渡す）
    init(
        roomID: String,
        userID: String,
        repository: any RoomRepository,
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
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
        self.clock = clock
        let now = clock()
        deadlineSelection = DeadlineSelection(date: RoomDeadline.defaultDeadline(now: now, calendar: calendar), now: now)
    }

    // MARK: - 今の設定と、変えられるか

    /// 購読で届いた今のルーム（届く前は nil）
    private var current: Room? {
        room.room
    }

    /// ルームが届いたか（届くまでは読み込み中の形で出す）
    var isLoaded: Bool {
        current != nil
    }

    /// どの項目も変えられない理由（作成者でない・終了している）。変えられるなら nil
    var formLock: LockReason? {
        guard let current else {
            return nil
        }
        if current.ownerId != room.userID {
            return .notOwner
        }
        return current.status == .closed ? .closed : nil
    }

    /// ルーム名を変えられるか（作成者・`closed` 以外）
    var isNameEditable: Bool {
        isLoaded && formLock == nil && !isSaving
    }

    /// 投稿数を変えられるか（作成者・`closed` 以外・まだ上限でない）
    var isPostLimitEditable: Bool {
        guard let current, isNameEditable else {
            return false
        }
        return current.settings.postLimit < Self.postLimitRange.upperBound
    }

    /// 解禁の条件を変えられない理由（変えられるなら nil）
    var unlockRuleLock: LockReason? {
        guard let current else {
            return nil
        }
        return formLock ?? (current.status == .open ? nil : .status)
    }

    /// いいねの効き方を変えられない理由（変えられるなら nil）
    var likeModeLock: LockReason? {
        guard let current else {
            return nil
        }
        return formLock ?? (Self.likeModeEditableStatuses.contains(current.status) ? nil : .status)
    }

    /// 解禁の条件を変えられるか
    var isUnlockRuleEditable: Bool {
        isLoaded && unlockRuleLock == nil && !isSaving
    }

    /// いいねの効き方を変えられるか
    var isLikeModeEditable: Bool {
        isLoaded && likeModeLock == nil && !isSaving
    }

    // MARK: - 入力（画面のつなぎ先）

    /// ルーム名（触っていなければ今の名前）
    var name: String {
        get { editedName ?? current?.name ?? "" }
        set { editedName = newValue }
    }

    /// ルーム名の検証の結果（S-03 と同じ数え方）
    var nameCheck: NameInputCheck {
        NameInputCheck(name, length: Self.nameLength)
    }

    /// 投稿数（触っていなければ今の値）。選べる範囲（`postLimitChoices`。今の値〜10）の外の値は範囲の端に戻す
    var postLimit: Int {
        get { DGStepperRule.clamped(editedPostLimit ?? currentPostLimit, in: postLimitChoices) }
        set { editedPostLimit = DGStepperRule.clamped(newValue, in: postLimitChoices) }
    }

    /// 投稿数に選べる範囲（今の値〜10。F-03「引き上げのみ可」）
    var postLimitChoices: ClosedRange<Int> {
        DGStepperRule.clamped(currentPostLimit, in: Self.postLimitRange)...Self.postLimitRange.upperBound
    }

    /// 今の投稿数（「今は n件まで」）
    var currentPostLimit: Int {
        current?.settings.postLimit ?? Self.postLimitRange.lowerBound
    }

    /// 解禁の条件（触っていなければ今の値。変えられない状態では今の値）
    var unlockRule: UnlockRule {
        get {
            let live = current?.settings.unlockRule ?? .all
            return unlockRuleLock == nil ? editedUnlockRule ?? live : live
        }
        set { editedUnlockRule = newValue }
    }

    /// 締切日時のピッカーを出すか（解禁の条件が「締切日時」のとき）
    var showsDeadlinePicker: Bool {
        unlockRule == .deadline
    }

    /// ピッカーの値を使うか（今の締切日時が無い・触った）。使わなければ今の締切日時を出す
    private var usesSelectedDeadline: Bool {
        isDeadlineEdited || unlockRuleDeadline == nil
    }

    /// 今の締切日時（今の条件が「締切日時」のときだけ）
    private var unlockRuleDeadline: Date? {
        guard let current, current.settings.unlockRule == .deadline else {
            return nil
        }
        return current.settings.deadlineAt
    }

    /// 締切日時（触っていなければ今の締切日時。今の条件が「締切日時」でなければ 3 日後の 21:00）
    var deadline: Date {
        get { usesSelectedDeadline ? deadlineSelection.date : unlockRuleDeadline ?? deadlineSelection.date }
        set {
            deadlineSelection.date = newValue
            isDeadlineEdited = true
        }
    }

    /// 締切日時に選べる範囲（日時ピッカーの範囲。最後に計算し直した時刻から決めたもの）
    var deadlineRange: ClosedRange<Date> {
        deadlineSelection.range
    }

    /// いいねの効き方（触っていなければ今の値。変えられない状態では今の値）
    var likeMode: LikeMode {
        get {
            let live = current?.settings.likeMode ?? .boost
            return likeModeLock == nil ? editedLikeMode ?? live : live
        }
        set { editedLikeMode = newValue }
    }

    // MARK: - 送る値

    /// 送る入力（変えた項目だけ）。何も変えていない・入力が正しくない・変えられない状態なら nil
    var request: UpdateRoomSettingsRequest? {
        guard let current, formLock == nil else {
            return nil
        }
        var request = UpdateRoomSettingsRequest(roomId: room.roomID)
        if editedName != nil {
            guard let validated = nameCheck.validatedName else {
                return nil
            }
            request.name = validated == current.name ? nil : validated
        }
        if postLimit != current.settings.postLimit {
            request.postLimit = postLimit
        }
        if unlockRuleLock == nil {
            guard applyUnlockRule(to: &request, current: current) else {
                return nil
            }
        }
        if likeModeLock == nil, likeMode != current.settings.likeMode {
            request.likeMode = likeMode
        }
        return request == UpdateRoomSettingsRequest(roomId: room.roomID) ? nil : request
    }

    /// 解禁の条件と締切日時の変更を入力に入れる。送る締切日時が範囲の外なら false（送れない）
    private func applyUnlockRule(to request: inout UpdateRoomSettingsRequest, current: Room) -> Bool {
        let rule = unlockRule
        let ruleChanged = rule != current.settings.unlockRule
        if ruleChanged {
            request.unlockRule = rule
        }
        guard rule == .deadline, ruleChanged || (usesSelectedDeadline && deadline != unlockRuleDeadline) else {
            return true
        }
        guard deadlineSelection.isInRange else {
            return false
        }
        request.deadlineAt = CallableTime.milliseconds(from: deadline)
        return true
    }

    /// 「保存」を押せるか（変えた項目がある・入力が正しい・送っている途中でない・保存済みでない）
    var canSave: Bool {
        request != nil && !isSaving && !didSave
    }

    /// シートを閉じるか（ルームが無くなった・自分が外された）
    var shouldClose: Bool {
        room.loadState == .missing
    }

    // MARK: - 購読

    /// ルームを購読し、呼んだ `Task` が cancel されるまで続ける（画面の `.task` から呼ぶ）
    func observe() async {
        await room.observe()
    }

    /// 締切日時の範囲を今の時刻で計算し直す（画面が前面に戻ったとき・送る直前）。
    ///
    /// ピッカーの値を使っているときは範囲の外になった値を範囲の中に収める。まだ触っていない今の締切日時は変えない
    func refreshDeadlineRange() {
        guard !isSaving else {
            return
        }
        if usesSelectedDeadline {
            deadlineSelection.refresh(now: clock())
        } else {
            deadlineSelection.refreshRange(now: clock())
        }
    }

    // MARK: - 保存

    /// 「保存」が押された。保存を始める（送っている途中・始めた Task が残っている間は何もしない）
    func saveTapped() {
        guard canSave, saveTask == nil else {
            return
        }
        saveTask = Task { [weak self] in
            await self?.save()
            // cancel された Task は `cancelSave` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                self?.saveTask = nil
            }
        }
    }

    /// 画面が消えたとき、送っている途中の保存を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）
    func cancelSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    /// 変えた項目を保存する（`updateRoomSettings`）。押せない状態なら何もしない。
    ///
    /// 送る前に締切日時の範囲を計算し直す。成功したら `didSave` を立てる。失敗したら `AppError` の文言のトーストを出し、入力を残す
    func save() async {
        refreshDeadlineRange()
        guard canSave, let request else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await functions.updateRoomSettings(request)
            guard !Task.isCancelled else {
                return
            }
            didSave = true
        } catch {
            toasts.showFailure(error)
        }
    }
}
