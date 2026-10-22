//
//  UITestIdentifiers.swift
//  DokogachaUITests
//

import Foundation

/// UI テストの各クラスで共通に使う、画面の `accessibilityIdentifier`・デモのデータの ID・待つ時間
enum UITestID {
    /// S-01 の表示名の入力欄（`OnboardingView.Identifier.displayName`）
    static let displayNameField = "onboarding.displayName"
    /// S-01 の「はじめる」（`OnboardingView.Identifier.start`）
    static let startButton = "onboarding.start"
    /// ホーム（`HomeView.Identifier.screen`）
    static let home = "home.screen"
    /// ホームのデモのルームのカード（`HomeView.Identifier.room(DemoScenario.roomID)`）
    static let demoRoomCard = "home.room.demo-room"
    /// 進行中のルームの空の表示（`HomeView.Identifier.roomsEmpty`）
    static let roomsEmpty = "home.rooms.empty"
    /// S-07 ルーム（`RoomView.Identifier.screen`）
    static let roomScreen = "room.screen"
    /// ホームの「＋ ルームを作る」（`HomeView.Identifier.createRoom`）
    static let createRoomButton = "home.createRoom"
    /// S-03（`CreateRoomView.Identifier.screen`）
    static let createRoomScreen = "createRoom.screen"
    /// S-03 のルーム名の入力欄（`CreateRoomView.Identifier.name`）
    static let roomNameField = "createRoom.name"
    /// S-03 の「ルームを作成」（`CreateRoomView.Identifier.submit`）
    static let createRoomSubmit = "createRoom.submit"
    /// S-04（`InviteView.Identifier.screen`）
    static let inviteScreen = "invite.screen"
    /// S-04 の招待コード（`InviteView.Identifier.code`）
    static let inviteCode = "invite.code"
    /// S-04 の「ルームへ進む」（`InviteView.Identifier.openRoom`）
    static let openRoomButton = "invite.openRoom"
    /// S-04 の「前回のメンバー（{前回ルーム名}・N人）を招待」（`InviteView.Identifier.lastMembers`）
    static let inviteLastMembersButton = "invite.lastMembers"
    /// ホームの設定の歯車（`HomeView.Identifier.settings`）
    static let settingsButton = "home.settings"
    /// S-15 設定（`SettingsView.Identifier.screen`）
    static let settingsScreen = "settings.screen"
    /// S-15 の表示名の行（`SettingsView.Identifier.displayName`）
    static let displayNameRow = "settings.displayName"
    /// 表示名の変更のシートの入力欄（`DisplayNameEditor.Identifier.field`）
    static let nameEditorField = "settings.nameEditor.field"
    /// 表示名の変更のシートの「保存」（`DisplayNameEditor.Identifier.save`）
    static let nameEditorSave = "settings.nameEditor.save"
    /// ホームの「招待コードで参加」（`HomeView.Identifier.joinByCode`）
    static let joinByCodeButton = "home.joinByCode"
    /// S-05 の招待コードの入力欄（`JoinByCodeView.Identifier.code`）
    static let joinCodeField = "joinByCode.code"
    /// S-05 の入力欄の下のエラー（`JoinByCodeView.Identifier.error`）
    static let joinCodeError = "joinByCode.error"
    /// S-05 の「参加する」（`JoinByCodeView.Identifier.submit`）
    static let joinCodeSubmit = "joinByCode.submit"
    /// S-06（`JoinConfirmView.Identifier.screen`）
    static let joinConfirmScreen = "joinConfirm.screen"
    /// S-06 のルームのカード（`JoinConfirmView.Identifier.card`）
    static let joinConfirmCard = "joinConfirm.card"
    /// S-06 の「参加する」（`JoinConfirmView.Identifier.join`）
    static let joinConfirmJoin = "joinConfirm.join"
    /// 招待リンクで開かれたことにする起動引数（`LaunchContext.openURLArgument`）
    static let openURLArgument = "-open-url"
    /// デモの参加できるルームの招待リンク（`DemoScenario.joinableInviteCode` を小文字・ハイフン付きで）
    static let joinableInviteLink = "https://dokogacha.app/r/qw5-8rt"
    /// デモの参加できるルームの ID（`DemoScenario.joinableRoomID`）
    static let joinableRoomID = "demo-room-joinable"
    /// デモの自分の候補（`room-with-candidates` の江の島）
    static let myCandidateID = "demo-candidate-3"
    /// デモのそうたの候補（`room-with-candidates` の明治神宮。いいね 0）
    static let shrineCandidateID = "demo-candidate-2"
    /// S-10 候補の詳細（`CandidateDetailView.Identifier.screen`）
    static let candidateDetailScreen = "candidateDetail.screen"
    /// S-10 の「この候補を削除」（`CandidateDetailView.Identifier.delete`）
    static let candidateDetailDelete = "candidateDetail.delete"
    /// S-10 の右上の「…」のメニュー（`CandidateDetailView.Identifier.more`）
    static let candidateDetailMore = "candidateDetail.more"
    /// S-10 の「…」の「この投稿を報告」（`CandidateDetailView.Identifier.report`）
    static let candidateDetailReport = "candidateDetail.report"
    /// S-10 の閉じるボタン（`CandidateDetailView.Identifier.close`）
    static let candidateDetailClose = "candidateDetail.close"
    /// S-10 の参考 URL（`CandidateDetailView.Identifier.url`）
    static let candidateDetailURL = "candidateDetail.url"
    /// デモのルームの、はるかが投稿したサンシャイン水族館（ひとこと・参考 URL あり。`DemoScenario` の `demo-candidate-1`）
    static let othersCandidateID = "demo-candidate-1"
    /// S-07 の見出し行の「候補を追加」（`RoomView.Identifier.addCandidate`）
    static let roomAddCandidate = "room.addCandidate"
    /// S-08（`AddCandidateView.Identifier.screen`）
    static let addCandidateScreen = "addCandidate.screen"
    /// S-08 のヘッダーの「n/上限」（`AddCandidateView.Identifier.postCount`）
    static let addCandidatePostCount = "addCandidate.postCount"
    /// S-08 の検索欄（`AddCandidateView.Identifier.searchField`）
    static let addCandidateSearch = "addCandidate.search"
    /// S-08 のすみだ水族館の「追加」（`AddCandidateView.Identifier.add(DemoPlaceSearchService.sumidaAquariumID)`）
    static let sumidaAquariumAdd = "addCandidate.place.demo-place-sumida-aquarium.add"
    /// S-09（`PostCandidateView.Identifier.screen`）
    static let postCandidateScreen = "postCandidate.screen"
    /// S-09 の場所名（`PostCandidateView.Identifier.placeName`）
    static let postCandidatePlaceName = "postCandidate.placeName"
    /// S-09 のカテゴリ（`PostCandidateView.Identifier.category`）
    static let postCandidateCategory = "postCandidate.category"
    /// S-09 のひとこと（`PostCandidateView.Identifier.note`）
    static let postCandidateNote = "postCandidate.note"
    /// S-09 の「候補に追加」（`PostCandidateView.Identifier.submit`）
    static let postCandidateSubmit = "postCandidate.submit"
    /// S-07 の「準備OK n/m」（`RoomView.Identifier.readyCount`）
    static let roomReadyCount = "room.readyCount"
    /// S-07 のヒント文言（`RoomView.Identifier.readyHint`）
    static let roomReadyHint = "room.readyHint"
    /// S-07 の「準備OK」「準備OKを取り消す」（`RoomView.Identifier.ready`）
    static let roomReady = "room.ready"
    /// S-07 の「強制解禁（作成者）」（`RoomView.Identifier.forceUnlock`）
    static let roomForceUnlock = "room.forceUnlock"
    /// S-07 の下部の「ガチャを回す」（`RoomView.Identifier.gacha`）
    static let roomGacha = "room.gacha"
    /// ホームの `several-rooms` のほかの人が作ったルーム（春のお花見）のカード（`HomeView.Identifier.room(DemoScenario.othersRoomID)`）
    static let othersRoomCard = "home.room.demo-room-others"
    /// S-07 のルームパネルのメンバー（`RoomView.Identifier.members`）
    static let roomMembers = "room.members"
    /// S-07 のヘッダーの設定（`RoomView.Identifier.settings`）
    static let roomSettings = "room.settings"
    /// S-11 メンバー一覧（`MembersView.Identifier.screen`）
    static let membersScreen = "members.screen"
    /// S-11 の「ルームから退出」（`MembersView.Identifier.leave`）
    static let membersLeave = "members.leave"
    /// S-12 ルーム設定（`RoomSettingsView.Identifier.screen`）
    static let roomSettingsScreen = "roomSettings.screen"
    /// S-12 の「保存」（`RoomSettingsView.Identifier.save`）
    static let roomSettingsSave = "roomSettings.save"
    /// S-07 の下部の「行き先きっぷを見る」（`RoomGachaBar.Identifier.result`）
    static let roomResult = "room.result"
    /// S-14 結果（`ResultView.Identifier.screen`）
    static let resultScreen = "result.screen"
    /// S-14 の「行き先が決まりました」（`ResultView.Identifier.title`）
    static let resultTitle = "result.title"
    /// S-14 の行き先きっぷ（`ResultView.Identifier.ticket`）
    static let resultTicket = "result.ticket"
    /// S-14 の「マップで開く」（`ResultView.Identifier.openInMaps`）
    static let resultOpenInMaps = "result.openInMaps"
    /// S-14 の「きっぷを共有」（`ResultView.Identifier.share`）
    static let resultShare = "result.share"
    /// S-14 の「引き直しを提案（過半数の賛成で1回まで）」（`ResultRerollSection.Identifier.propose`）
    static let resultRerollPropose = "result.reroll.propose"
    /// S-14 の「賛成を集めています…（N/M人）」・「引き直しは使用済みです」（`ResultRerollSection.Identifier.status`）
    static let resultRerollStatus = "result.reroll.status"
    /// S-14 の引き直しの「賛成」（`ResultRerollSection.Identifier.approve`）
    static let resultRerollApprove = "result.reroll.approve"
    /// S-14 の引き直しの「反対」（`ResultRerollSection.Identifier.reject`）
    static let resultRerollReject = "result.reroll.reject"
    /// 画面が出るのを待つ時間。
    ///
    /// Mac が混んでいる（load average が 100 を超える）と、画面の切り替えに 10 秒を超えることがある。
    /// `waitForExistence` は出た時点で返るので、長くしても通るときの時間は変わらない
    static let timeout: TimeInterval = 30
    /// 1 回のキー入力で入力欄の値が変わるのを待つ時間（変わらなければ打ち直す。`clearText`・`typeTextByCharacter`）
    static let keystrokeTimeout: TimeInterval = 5

    /// S-11 のメンバーの行（`MembersView.Identifier.row(_:)`）
    static func membersRow(_ memberID: String) -> String {
        "members.row.\(memberID)"
    }

    /// S-07 の候補のカード（`RoomView.Identifier.candidate(_:)`）
    static func candidateCard(_ candidateID: String) -> String {
        "room.candidate.\(candidateID)"
    }
}
