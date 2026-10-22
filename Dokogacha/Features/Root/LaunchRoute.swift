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
    /// オフラインで、サインインできない・プロフィールがキャッシュに無い（02 の §9）。繋がったら起動の流れが自動で続ける
    case offline
    /// S-01 オンボーディング（表示名をまだ登録していない）
    case onboarding
    /// S-02 ホーム（表示名を登録済み）
    case home(UserProfile)

    /// 画面の上端に「オフラインです」のバナーを出してよいか。
    ///
    /// `offline` の画面は、それ自体が「オフラインです」と案内するので、バナーを重ねると同じ文言が 2 回並ぶ（PR #113 の持ち越し）
    var showsOfflineBanner: Bool {
        self != .offline
    }

    /// 起動の流れの判定。
    ///
    /// 1. 接続できない → `serverUnavailable`。起動の処理の前 → `loading`
    /// 2. サインインしていない・途中 → `loading`（サーバー側でサインアウトされたときは、起動の流れが匿名でサインインし直す）
    /// 3. サインインに失敗した → `failed`（理由が分からないので「通信できませんでした」）
    /// 4. サインインした → そのユーザーのプロフィールで決める。読めていない・別のユーザーのもの → `loading`、
    ///    無い → `onboarding`、ある → `home`、読めなかった → `failed`
    /// 5. オフラインのとき、3 の失敗と 4 の読み込み中は `offline` にする。プロフィールの購読はキャッシュに無いと
    ///    サーバーの返事を待ち続ける（`FirebaseAuthService.profile`）ので、起動中のまま理由が分からなくなるため（PR #40 の持ち越し）。
    ///    読めた画面（S-01・ホーム）はオフラインでもそのまま出す（閲覧はキャッシュでできる）
    static func resolve(
        connection: ServerConnection,
        authState: ServerSession.AuthState,
        profile: ProfileLoadState,
        reachability: NetworkReachability = .unknown
    ) -> Self {
        let route = resolveIgnoringNetwork(connection: connection, authState: authState, profile: profile)
        guard reachability == .offline else {
            return route
        }
        switch (route, authState) {
        case (.failed, .failed), (.loading, .signedIn):
            return .offline
        default:
            return route
        }
    }

    /// 回線の状態を見ない判定（1〜4）
    private static func resolveIgnoringNetwork(
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
