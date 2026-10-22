//
//  JoinByCodeModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// S-05 招待コードで参加（F-04）の状態と操作。
///
/// 入力は打つたび・貼り付けるたびに `InviteCode.inputText(_:)` で正規化する（03 の S-05「ハイフンは自動挿入、英大文字に自動変換、貼り付け対応」）。
/// 「参加する」は、参加の前にルームを確かめる Callable の `previewRoom` を呼び、結果で行き先（`outcome`）を決める:
/// まだメンバーでなければ S-06 参加確認、すでにメンバーならそのままルーム（03 の S-06「すでにメンバーなら確認を出さずにルーム画面へ」）。
///
/// F-04 の AC のエラー（「招待コードが見つかりません」・満員・「もう行き先が決まっています」）は入力欄の下に出し（`errorMessage`）、
/// 通信のエラーなど、入力を直しても変わらないものはトーストで出す。
@Observable
final class JoinByCodeModel {
    /// 「参加する」の後の行き先
    enum Outcome: Hashable {
        /// S-06 参加確認を出す
        case confirm(JoinConfirmDestination)
        /// すでにメンバーなので、確認を出さずにルーム（S-07）を開く（値はルームの ID）
        case openRoom(roomID: String)
    }

    /// 入力欄の下に出すエラーの理由（F-04 の AC。入力を直せば変わりうるもの）。ほかの理由はトーストで出す
    static let inlineReasons: Set<AppError.Reason> = [.inviteCodeNotFound, .roomFull, .roomAlreadyDecided]

    /// 入力欄の文字列（表示の形。`ABC-123`）。入れるたびに正規化し、変わったらエラーを消す
    var codeText = "" {
        didSet {
            // ハイフンだけを消したときは、その前の 1 文字を消す（`InviteCode.inputText(_:previous:)`）
            let formatted = InviteCode.inputText(codeText, previous: oldValue)
            if formatted != codeText {
                codeText = formatted
            }
            if codeText != oldValue {
                errorMessage = nil
            }
        }
    }

    /// 確かめている途中か（二重に送らないため、ボタンと入力を止める）
    private(set) var isSubmitting = false
    /// 入力欄の下に出すエラーの文言（F-04 の AC）。無ければ nil
    private(set) var errorMessage: String?
    /// 「参加する」の後の行き先。画面がこれを見て進み、`clearOutcome()` で消す
    private(set) var outcome: Outcome?

    @ObservationIgnored private let functions: any FunctionsClient
    @ObservationIgnored private let toasts: DGToastCenter
    /// ボタンから始めた確認。画面が消えたら（`cancelSubmit`）止める
    @ObservationIgnored private var submitTask: Task<Void, Never>?
    /// 招待リンクで開いたときに、最初の 1 回だけ自動で確かめるか（`submitInitialCodeIfNeeded`）
    @ObservationIgnored private var needsInitialSubmit: Bool

    /// - Parameters:
    ///   - functions: `previewRoom` を呼ぶ窓口（Firebase か擬似のサーバー）
    ///   - toasts: 通信エラーを出すトーストの窓口
    ///   - initialCode: 招待リンクで開いたときの招待コード。入力欄に入れた状態で始め、画面が出たら自動で確かめる
    init(functions: any FunctionsClient, toasts: DGToastCenter, initialCode: InviteCode? = nil) {
        self.functions = functions
        self.toasts = toasts
        needsInitialSubmit = initialCode != nil
        if let initialCode {
            codeText = initialCode.displayText
        }
    }

    /// 入力した文字の数（ハイフンを除く）
    var enteredCount: Int {
        InviteCode.normalize(codeText).count
    }

    /// 入力が招待コードの形か（6 文字で、使える文字だけ）
    var code: InviteCode? {
        InviteCode(codeText)
    }

    /// 「参加する」を押せるか（6 文字を入れた・確かめている途中でない）。
    ///
    /// 使えない文字（`0 O 1 I` など）が入っていても 6 文字なら押せる。押すと「招待コードが見つかりません」を出す
    /// （サーバーも形の正しくないコードを存在しないコードと同じに扱う。押せない理由が分からないまま止まらないように）
    var canSubmit: Bool {
        enteredCount == InviteCode.length && !isSubmitting
    }

    /// 入力を変えられるか（確かめている途中は変えさせない）
    var isEditable: Bool {
        !isSubmitting
    }

    /// 「参加する」が押された・キーボードの「参加」が押された。確認を始める（確かめている途中なら何もしない）。
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

    /// 招待リンクで開いたとき、入れておいたコードで最初の 1 回だけ確認を始める（画面が出たときに呼ぶ）。
    ///
    /// 結果は「参加する」を押したときと同じ（S-06 を出す・メンバーならルームを開く・エラーは入力欄の下かトースト）。
    /// S-06 から戻って S-05 がもう一度出たときは確かめ直さない（戻ってコードを直せるように）
    func submitInitialCodeIfNeeded() {
        guard needsInitialSubmit else {
            return
        }
        needsInitialSubmit = false
        submitTapped()
    }

    /// 画面が消えたとき、確かめている途中の確認を止める（結果を待つ相手がいないため。cancel ではトーストを出さない）。
    ///
    /// Task は self を持つので、画面の `onDisappear` から必ず呼ぶ（Model の `deinit` では止められない）
    func cancelSubmit() {
        submitTask?.cancel()
        submitTask = nil
    }

    /// 行き先に進んだので、行き先を消す（S-06 から戻って、別のコードで確かめ直せるように）
    func clearOutcome() {
        outcome = nil
    }

    /// 参加するルームを確かめる。押せない状態なら何もしない。
    ///
    /// 成功したら `outcome` に行き先を入れる。F-04 の AC のエラーは `errorMessage`、ほかはトーストに出し、
    /// 入力をそのままにもう一度押せるようにする。cancel（画面を閉じた）のときは、結果によらず何もしない
    func submit() async {
        guard canSubmit else {
            return
        }
        guard let code else {
            // 6 文字だが使えない文字を含む。サーバーに送らずに、サーバーと同じ「招待コードが見つかりません」を出す
            errorMessage = AppError(.inviteCodeNotFound).message
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let preview = try await functions.previewRoom(PreviewRoomRequest(inviteCode: code.value))
            guard !Task.isCancelled else {
                return
            }
            outcome = preview.alreadyMember
                ? .openRoom(roomID: preview.roomId)
                : .confirm(JoinConfirmDestination(preview: preview, inviteCode: code))
        } catch {
            let appError = AppError.wrapping(error)
            guard !appError.isCancellation, !Task.isCancelled else {
                return
            }
            if Self.inlineReasons.contains(appError.reason) {
                errorMessage = appError.message
            } else {
                toasts.show(text: appError.message)
            }
        }
    }
}

/// S-06 参加確認の行き先（確かめたルームと、参加に送る招待コード）
nonisolated struct JoinConfirmDestination: Hashable, Sendable {
    /// `previewRoom` が返したルームの値
    let preview: RoomPreview
    /// 確かめた招待コード（「参加する」で `joinRoom` に送る）
    let inviteCode: InviteCode
}
