//
//  FirebaseEmulator.swift
//  Dokogacha
//

import Foundation

/// Debug で接続する Firebase の Emulator の接続先。値はここ 1 か所にまとめる。
///
/// ポートは `backend/firebase.json` の `emulators`（ずらし 0）と同じ値にする。
/// Simulator は Mac のネットワークをそのまま使うので `localhost` で Mac の Emulator に届く。
nonisolated enum FirebaseEmulator {
    /// Emulator が動いているホスト
    static let host = "localhost"
    /// Authentication の Emulator のポート
    static let authPort = 9099
    /// Cloud Firestore の Emulator のポート
    static let firestorePort = 8080
    /// Cloud Functions の Emulator のポート
    static let functionsPort = 5001

    /// Emulator 専用の demo プロジェクト（`backend/.firebaserc`）。`demo-` で始まる ID は実プロジェクトに接続しない
    static let projectID = "demo-dokogacha"
    /// demo プロジェクトで使う Google App ID。Emulator は値を確かめないが、SDK が形式を確かめるので形だけそろえる
    static let googleAppID = "1:123456789012:ios:0000000000000000"
    /// demo プロジェクトで使う送信者 ID（`googleAppID` の 2 つ目の値と同じ）
    static let gcmSenderID = "123456789012"
    /// demo プロジェクトで使う API キー（実際の鍵ではない）。Emulator は値を確かめないが、
    /// Firebase Installations が形式（`A` で始まる 39 文字）を確かめて例外で落とすので形だけそろえる。
    /// 本物の鍵の形（`AIza…`）にすると秘密情報の検出に掛かるので避ける
    static let apiKey = "Ademo-dokogacha-emulator-only-not-a-key"
}

/// Firebase の共通の設定
nonisolated enum FirebaseConstants {
    /// Cloud Functions のリージョン（Discussion #5 の Q3。`backend/functions` の `setGlobalOptions` と同じ）
    static let functionsRegion = "asia-northeast1"
}
