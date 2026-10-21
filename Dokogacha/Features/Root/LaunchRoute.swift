//
//  LaunchRoute.swift
//  Dokogacha
//

import Foundation

/// 自分のプロフィール（`users/{uid}`）の読み込みの状態。どのユーザーのものかを一緒に持つ
/// （ユーザーが変わった直後に、前のユーザーのプロフィールで画面を決めないため）。
nonisolated enum ProfileLoadState: Equatable, Sendable {
    /// まだ読んでいない（サインインの前）
    case idle
    /// 読み込み中
    case loading(userID: String)
    /// 読めた（nil なら表示名をまだ登録していない）
    case loaded(userID: String, profile: UserProfile?)
    /// 読めなかった（通信エラー・ルールで拒まれた）
    case failed(userID: String, error: AppError)
}

/// 起動したときに出す画面（起動の流れの判定）。
///
/// 接続の状態・サインインの状態・プロフィールの読み込みの状態だけから決める純粋な判定にして、
/// F-01 の AC（初回だけ S-01、以降は入力なしでホーム）を Unit テストで確かめられるようにする。
/// `ServerSession.AuthState` が MainActor の型なので、この判定も MainActor に置く。
enum LaunchRoute: Equatable {
    /// サインイン中・プロフィールの読み込み中
    case loading
    /// サーバーに接続できない（Firebase の設定が無い・読めない）。再試行しても変わらないので、ボタンを出さない
    case serverUnavailable
    /// サインイン・プロフィールの読み込みに失敗した（再試行できる）
    case failed(AppError)
    /// S-01 オンボーディング（表示名をまだ登録していない）
    case onboarding
    /// S-02 ホーム（表示名を登録済み）
    case home(UserProfile)

    /// 起動の流れの判定。
    ///
    /// 1. 接続できない → `serverUnavailable`。起動の処理の前 → `loading`
    /// 2. サインインしていない・途中 → `loading`（サーバー側でサインアウトされたときは、起動の流れが匿名でサインインし直す）
    /// 3. サインインに失敗した → `failed`（理由が分からないので「通信できませんでした」）
    /// 4. サインインした → そのユーザーのプロフィールで決める。読めていない・別のユーザーのもの → `loading`、
    ///    無い → `onboarding`、ある → `home`、読めなかった → `failed`
    static func resolve(
        connection: ServerConnection,
        authState: ServerSession.AuthState,
        profile: ProfileLoadState
    ) -> Self {
        switch connection {
        case .unavailable:
            return .serverUnavailable
        case .notStarted:
            return .loading
        case .firebase, .disabled:
            break
        }
        switch authState {
        case .signedOut, .signingIn:
            return .loading
        case .failed:
            return .failed(AppError(.network))
        case let .signedIn(userID):
            return route(for: profile, of: userID)
        }
    }

    /// サインインしたユーザーのプロフィールの状態から決める
    private static func route(for profile: ProfileLoadState, of userID: String) -> Self {
        switch profile {
        case let .loaded(loadedUserID, profile) where loadedUserID == userID:
            if let profile {
                return .home(profile)
            }
            return .onboarding
        case let .failed(failedUserID, error) where failedUserID == userID:
            return .failed(error)
        case .idle, .loading, .loaded, .failed:
            return .loading
        }
    }
}
