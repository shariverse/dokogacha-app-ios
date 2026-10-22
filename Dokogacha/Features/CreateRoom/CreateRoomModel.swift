//
//  CreateRoomModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-03 ルーム作成（F-02）の状態と操作。
///
/// 入力の初期値は 02 の §2.2 の表（ルーム名は空・投稿数 3・解禁の条件「全員OK」・締切 3 日後の 21:00・いいねの効き方「共感ブースト」）。
/// ルーム名の検証は `NameValidation`（backend の `createRoom` と同じ規則）、締切日時の範囲は `RoomDeadline` で行う。
/// 締切日時の範囲は「今」から決まるので、送る直前（`submit()`）と前面に戻ったとき（画面が `refreshDeadlineRange()` を呼ぶ）に
/// 計算し直し、範囲の外になった日時を範囲の中に収める（`DeadlineSelection`。画面を開いたまま時間がたっても、断られる値を送らない）。
/// 作成は Callable の `createRoom` を通し、成功したら `createdRoom` に招待画面（S-04）の行き先を入れる（画面がそれを見て進む）。
@Observable
final class CreateRoomModel {
    /// ルーム名の入力が正しくない理由（空のときは理由を出さず、ボタンを無効にするだけ）
    enum NameIssue: Equatable {
        /// 文字数が上限を超えた（値は上限）
        case tooLong(limit: Int)
        /// 改行などの使えない文字が入っている
        case forbiddenCharacter
    }

    /// ルーム名の文字数の範囲（02 の §2.2「1〜20文字。必須」）
    static let nameLength = DomainConstants.Limits.roomNameLength
    /// 1 人あたりの投稿数の範囲（02 の §2.2「1〜10件」）
    static let postLimitRange = DomainConstants.Limits.postLimitRange

    /// 入力中のルーム名
    var name = ""
    /// 1 人あたりの投稿数
    var postLimit = DomainConstants.Limits.defaultPostLimit {
        didSet {
            // 部品（DGStepper）の外から範囲の外の値が入っても、範囲の中に戻す
            let clamped = DGStepperRule.clamped(postLimit, in: Self.postLimitRange)
            if clamped != postLimit {
                postLimit = clamped
            }
        }
    }
    /// 解禁の条件
    var unlockRule = UnlockRule.all
    /// 締切日時と、その選べる範囲（解禁の条件が「締切日時」のときだけ送る）
    private var deadlineSelection: DeadlineSelection
    /// いいねの効き方
    var likeMode = LikeMode.boost

    /// 締切日時（解禁の条件が「締切日時」のときだけ送る）
    var deadline: Date {
        get { deadlineSelection.date }
        set { deadlineSelection.date = newValue }
    }

    /// 締切日時に選べる範囲（日時ピッカーの範囲。最後に計算し直した時刻から決めたもの）
    var deadlineRange: ClosedRange<Date> {
        deadlineSelection.range
    }

    /// 作成を送っている途中か（二重に送らないため、ボタンと入力を止める）
    private(set) var isSubmitting = false
    /// 作成したルーム（招待画面の行き先）。入ったら画面は S-04 へ進む
    private(set) var createdRoom: InviteDestination?

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// 作成できたら `room_create` を送る窓口
    @ObservationIgnored private let analytics: any AnalyticsService
    /// 今の時刻（締切の範囲を計算し直すたびに読む）
    @ObservationIgnored private let clock: () -> Date
    /// ボタンから始めた作成。画面が消えたら（`cancelSubmit`）止める
    @ObservationIgnored private var submitTask: Task<Void, Never>?

    /// - Parameters:
    ///   - functions: `createRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - clock: 今の時刻（締切の範囲と初期値を決める。テストで進める）
    ///   - calendar: 暦（締切の初期値「3日後の21:00」を端末のタイムゾーンで決める）
    ///   - analytics: Analytics のイベント（05 の §9）を送る窓口
    init(
        functions: any FunctionsClient,
        toasts: DGToastCenter,
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        analytics: any AnalyticsService = DisabledAnalyticsService()
    ) {
        self.functions = functions
        self.toasts = toasts
        self.analytics = analytics
        self.clock = clock
        let now = clock()
        deadlineSelection = DeadlineSelection(date: RoomDeadline.defaultDeadline(now: now, calendar: calendar), now: now)
    }

    /// 送るルーム名（前後の空白を取り除いたもの）。受け付けない入力なら nil
    var validatedName: String? {
        NameValidation.validated(name, length: Self.nameLength)
    }

    /// ルーム名の文字数（検証と同じ数え方。前後の空白を除き、見えない文字だけなら 0）
    var nameCount: Int {
        let trimmed = NameValidation.trimWhitespace(name)
        return NameValidation.isInvisibleOnly(trimmed) ? 0 : trimmed.count
    }

    /// ルーム名の文字数の上限
    var nameLimit: Int {
        Self.nameLength.upperBound
    }

    /// ルーム名の入力が正しくない理由。正しいとき・空のときは nil
    var nameIssue: NameIssue? {
        guard validatedName == nil, nameCount > 0 else {
            return nil
        }
        if nameCount > nameLimit {
            return .tooLong(limit: nameLimit)
        }
        // 上限の範囲で通らないのは、使えない文字（制御文字など）か、長すぎる結合文字のとき
        return .forbiddenCharacter
    }

    /// 締切日時のピッカーを出すか（03 の S-03「「締切日時」選択時は下に日時ピッカーを表示」）
    var showsDeadlinePicker: Bool {
        unlockRule == .deadline
    }

    /// 送る入力。ルーム名が正しくない・締切日時が範囲の外なら nil
    var request: CreateRoomRequest? {
        guard let validatedName, Self.postLimitRange.contains(postLimit) else {
            return nil
        }
        if unlockRule == .deadline, !deadlineSelection.isInRange {
            return nil
        }
        return CreateRoomRequest(
            name: validatedName,
            postLimit: postLimit,
            unlockRule: unlockRule,
            deadline: deadline,
            likeMode: likeMode
        )
    }

    /// 「ルームを作成」を押せるか（F-02 の AC「ルーム名が空のときは押せない」。送っている途中・作成済みのときも押せない）
    var canSubmit: Bool {
        request != nil && !isSubmitting && createdRoom == nil
    }

    /// 入力を変えられるか（送っている途中・作成済みのときは変えさせない）
    var isEditable: Bool {
        !isSubmitting && createdRoom == nil
    }

    /// 締切日時の範囲を今の時刻で計算し直し、範囲の外になった締切日時を範囲の中に収める（画面が前面に戻ったときに呼ぶ）。
    ///
    /// 送っている途中・作成済みのときは入力を変えない
    func refreshDeadlineRange() {
        guard isEditable else {
            return
        }
        deadlineSelection.refresh(now: clock())
    }

    /// 「ルームを作成」が押された・キーボードの完了が押された。作成を始める（送っている途中なら何もしない）。
    ///
    /// `isSubmitting` は Task が動き出してから立つので、Task が始まる前に続けて押されたときのために、
    /// 始めた Task が残っている間も押せないことにする
    func submitTapped() {
        guard canSubmit, submitTask == nil else {
            return
        }
        submitTask = Task {
            await submit()
            // cancel された Task は `cancelSubmit` が外し済み（その後に始めた Task を外さない）
            if !Task.isCancelled {
                submitTask = nil
            }
        }
    }

    /// 画面が消えたとき、送っている途中の作成を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）。
    ///
    /// Task は self を持つので、画面の `onDisappear` から必ず呼ぶ（Model の `deinit` では止められない）
    func cancelSubmit() {
        submitTask?.cancel()
        submitTask = nil
    }

    /// ルームを作る。押せない状態なら何もしない。
    ///
    /// 送る前に締切日時の範囲を計算し直す（画面を開いてから時間がたち、選んだ日時が下限を割っていたら下限に上げて送る）。
    /// 成功したら `createdRoom` に S-04 の行き先を入れる。失敗したらトースト（文言は `AppError`）を出して、
    /// 入力をそのままにもう一度押せるようにする。cancel（画面を閉じた）のときは、結果によらず何もしない
    func submit() async {
        if unlockRule == .deadline {
            refreshDeadlineRange()
        }
        guard canSubmit, let request else {
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await functions.createRoom(request)
            guard !Task.isCancelled else {
                return
            }
            // サーバーは必ず正しい形のコードを返す。万一読めなければ、招待画面に進まずに失敗として扱う
            guard let code = InviteCode(response.inviteCode) else {
                throw AppError(.unreadableData)
            }
            createdRoom = InviteDestination(roomID: response.roomId, roomName: request.name, inviteCode: code)
            analytics.log(.roomCreate(postLimit: request.postLimit, unlockRule: request.unlockRule, likeMode: request.likeMode))
        } catch {
            toasts.showFailure(error)
        }
    }
}
