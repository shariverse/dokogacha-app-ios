//
//  RootModel.swift
//  Dokogacha
//

import Foundation
import Observation

/// 起動の流れ（サインイン → プロフィールの有無で S-01 かホーム）の状態と操作。
///
/// 画面（`RootView`）は `taskKey` が変わるたびに `follow()` を呼び直す（`.task(id:)`。前の呼び出しは cancel される）。
/// `follow()` はサインインの状態に合わせて、サインインするか、そのユーザーのプロフィールを購読する。
/// 表示名を登録すると購読しているプロフィールに届くので、S-01 からホームへは自動で進む。
///
/// - サーバー側でサインアウトされた（ユーザーが消えた・トークンを更新できなかった）ら、匿名でサインインし直す。
///   新しいユーザーにはプロフィールが無いので S-01 から始まる
/// - サインイン・プロフィールの読み込みに失敗したら、再試行のボタンと、アプリが前面に戻ったとき（`retryIfFailed`）にやり直す
@Observable
final class RootModel {
    /// 起動の流れを動かし直す鍵。サインインの状態か、プロフィールの読み直しの回数が変わったら変わる
    struct TaskKey: Equatable {
        /// サインインの状態
        let authState: ServerSession.AuthState
        /// プロフィールの読み直しの回数
        let profileAttempt: Int
    }

    /// サーバーへの接続とサインインの状態
    let session: ServerSession
    /// 自分のプロフィールの読み込みの状態
    private(set) var profile: ProfileLoadState = .idle
    /// プロフィールの読み直しの回数（再試行で増やすと `taskKey` が変わり、購読し直す）
    private(set) var profileAttempt = 0

    /// 再試行で始めたサインイン。Model が無くなったら止める（テストで終わりを待てるよう読み取りだけ公開する）
    @ObservationIgnored private(set) var retryTask: Task<Void, Never>?

    /// - Parameter session: サーバーへの接続とサインインの状態（`start` 済みのもの）
    init(session: ServerSession) {
        self.session = session
    }

    deinit {
        retryTask?.cancel()
    }

    /// 認証とプロフィールの窓口（S-01 の Model に渡す）
    var auth: any AuthService {
        session.services.auth
    }

    /// いま出す画面
    var route: LaunchRoute {
        LaunchRoute.resolve(connection: session.connection, authState: session.authState, profile: profile)
    }

    /// 起動の流れを動かし直す鍵
    var taskKey: TaskKey {
        TaskKey(authState: session.authState, profileAttempt: profileAttempt)
    }

    /// いまのサインインの状態に合わせて、サインインするか、プロフィールを購読する。
    ///
    /// プロフィールの購読は、呼んだ `Task` が cancel されるまで（サインインの状態が変わるか、再試行するまで）続く
    func follow() async {
        switch session.authState {
        case .signedOut:
            // 起動した直後と、サーバー側でサインアウトされたとき。接続できないときは何もしない
            profile = .idle
            await session.signInIfNeeded()
        case .signingIn, .failed:
            profile = .idle
        case let .signedIn(userID):
            await observeProfile(of: userID)
        }
    }

    /// 失敗の表示から、もう一度試す（ボタン）。サインインの失敗ならサインインし直し、プロフィールの失敗なら購読し直す
    func retry() {
        switch session.authState {
        case .failed:
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                await self?.session.signInIfNeeded()
            }
        case .signedIn:
            if case .failed = profile {
                profileAttempt += 1
            }
        case .signedOut, .signingIn:
            break
        }
    }

    /// アプリが前面に戻ったとき、失敗の表示のままなら、もう一度試す（オフラインで起動して、電波が戻った後など）
    func retryIfFailed() {
        if case .failed = route {
            retry()
        }
    }

    /// プロフィールを購読して状態に映す。購読が失敗で終わったら、再試行を待つ
    private func observeProfile(of userID: String) async {
        // 同じユーザーのプロフィールが読めているとき（読み直し）は、出している画面を「読み込み中」に戻さない
        if !hasLoadedProfile(of: userID) {
            profile = .loading(userID: userID)
        }
        for await update in auth.profile(userID: userID) {
            switch update {
            case let .value(value):
                profile = .loaded(userID: userID, profile: value)
            case let .failure(error):
                // cancel（画面が無くなった）は失敗の表示にしない
                if !error.isCancellation {
                    profile = .failed(userID: userID, error: error)
                }
            }
        }
    }

    /// `userID` のプロフィールが読めているか
    private func hasLoadedProfile(of userID: String) -> Bool {
        if case let .loaded(loadedUserID, _) = profile {
            return loadedUserID == userID
        }
        return false
    }
}
