//
//  InMemoryServer+Device.swift
//  Dokogacha
//
//  擬似のサーバーに、ほかのメンバーの端末から操作する入口。テストとデモのデータで、ほかの人の参加・準備OK・いいねを再現する。
//

import Foundation

extension InMemoryServer {
    /// ほかのメンバー（`userID` でサインインしている別の端末）。
    ///
    /// この端末の操作（protocol の Callable・直接の書き込み）と同じ検証・状態遷移・数え直しを、`userID` が行ったものとして通す。
    /// uid は呼び出しごとに引数で渡すので、`await` で中断している間に、この端末の呼び出しへ別の人の uid が漏れない。
    /// 直接の書き込みは、この端末と同じく拒まれても投げずに `rejectedWrites` に残す
    struct Device {
        /// 操作する擬似のサーバー
        let server: InMemoryServer
        /// この端末でサインインしている人の uid
        let userID: String

        /// 表示名を登録・変更する（`saveProfile`）
        func saveProfile(_ request: SaveProfileRequest) async throws -> SaveProfileResponse {
            try server.saveProfile(request, by: userID)
        }

        /// ルームを作る（`createRoom`）
        func createRoom(_ request: CreateRoomRequest) async throws -> CreateRoomResponse {
            try server.createRoom(request, by: userID)
        }

        /// 招待コードで参加する（`joinRoom`）
        func joinRoom(_ request: JoinRoomRequest) async throws -> JoinRoomResponse {
            try server.joinRoom(request, by: userID)
        }

        /// 参加する前にルームを確かめる（`previewRoom`）
        func previewRoom(_ request: PreviewRoomRequest) async throws -> RoomPreview {
            try server.previewRoom(request, by: userID)
        }

        /// ルームから退出する（`leaveRoom`）
        func leaveRoom(_ request: RoomRequest) async throws {
            try server.leaveRoom(request, by: userID)
        }

        /// メンバーを削除する（`removeMember`）
        func removeMember(_ request: RemoveMemberRequest) async throws {
            try server.removeMember(request, by: userID)
        }

        /// 候補を追加する（`addCandidate`）
        func addCandidate(_ request: AddCandidateRequest) async throws -> AddCandidateResult {
            try server.addCandidate(request, by: userID)
        }

        /// 候補を削除する（`deleteCandidate`）
        func deleteCandidate(_ request: CandidateRequest) async throws {
            try server.deleteCandidate(request, by: userID)
        }

        /// ルームの設定を変える（`updateRoomSettings`）
        func updateRoomSettings(_ request: UpdateRoomSettingsRequest) async throws {
            try server.updateRoomSettings(request, by: userID)
        }

        /// 強制解禁する（`forceUnlock`）
        func forceUnlock(_ request: RoomRequest) async throws {
            try server.forceUnlock(request, by: userID)
        }

        /// 自分の準備OKを変える（直接の書き込み）
        func setReady(_ ready: Bool, roomID: String) async {
            server.applyDirectWrite { try server.writeReady(ready, roomID: roomID, userID: userID, by: userID) }
        }

        /// 他人の候補へのいいねを付ける・外す（直接の書き込み）
        func setLike(_ liked: Bool, candidateID: String, roomID: String) async {
            server.applyDirectWrite {
                try server.writeLike(liked, candidateID: candidateID, roomID: roomID, userID: userID, by: userID)
            }
        }

        /// 自分が最後に見た日時を今にする（直接の書き込み）
        func markSeen(roomID: String) async {
            server.applyDirectWrite { try server.writeSeen(roomID: roomID, userID: userID, by: userID) }
        }
    }

    /// ほかのメンバー（`userID`）の端末を返す（テスト・デモのデータを作るとき）
    func device(of userID: String) -> Device {
        Device(server: self, userID: userID)
    }
}
