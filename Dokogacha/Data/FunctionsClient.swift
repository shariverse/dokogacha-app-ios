//
//  FunctionsClient.swift
//  Dokogacha
//

import Foundation

/// Callable Functions（05 の §5）を型付きで呼ぶ窓口。画面の Model はこの protocol だけを見る。
///
/// 失敗したときは `AppError` を投げる（`HttpsError` のコードと理由から、アプリの文言に対応付けたもの）。
/// Firebase の実装は `CallableFunctionsClient`、プレビュー・Unit テスト・`-uiTesting` では `InMemoryServer`。
protocol FunctionsClient {
    /// 表示名を登録・変更する（F-01。初回は `users/{uid}` を作る）
    func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse
    /// ルームを作る（F-02）
    func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse
    /// 招待コードでルームに参加する（F-04）
    func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse
    /// 招待コードで参加する前に、参加するルームを確かめる（S-06。何も書き換えない。断る理由は `joinRoom` と同じ）
    func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview
    /// ルームから退出する（F-05）
    func leaveRoom(_ request: RoomRequest) async throws
    /// 作成者がメンバーを削除する（F-05）
    func removeMember(_ request: RemoveMemberRequest) async throws
    /// 作成者がルームの設定を変える（F-03）
    func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws
    /// 候補を追加する（F-10・F-13。同じ場所があれば追加せずに既存の候補を返す）
    func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult
    /// 候補を削除する（F-11）
    func deleteCandidate(_ request: CandidateRequest) async throws
    /// 作成者が強制解禁する（F-32）
    func forceUnlock(_ request: RoomRequest) async throws
    /// ガチャを回す（F-40）
    func drawGacha(_ request: RoomRequest) async throws -> DrawGachaResponse
    /// 引き直しを提案する（F-43）
    func proposeReroll(_ request: RoomRequest) async throws
    /// 引き直しに投票する（F-43）
    func voteReroll(_ request: VoteRerollRequest) async throws
    /// 作成者がルームを終了する（F-44 の「この行き先で決定」・S-12 の「ルームを終了する」。意図は `CloseRoomRequest.Reason`）
    func closeRoom(_ request: CloseRoomRequest) async throws
    /// 前回のメンバーを招待する（F-04）
    func inviteLastMembers(_ request: RoomRequest) async throws -> InviteLastMembersResponse
    /// 候補を報告する（F-14）
    func reportCandidate(_ request: ReportCandidateRequest) async throws
    /// 広告非表示の購入をサーバーで確かめて記録する（F-51）
    func verifyPurchase(_ request: VerifyPurchaseRequest) async throws -> VerifyPurchaseResponse
    /// アカウントを削除する（F-06）
    func deleteAccount() async throws
}
