//
//  GachaView.swift
//  Dokogacha
//

import SwiftUI

/// S-13 ガチャ（フルスクリーンカバー）。03 の S-13 の上から順に、ヘッダー（閉じる（戻る矢印）・ルーム名）、
/// 段階ごとのタイトルとサブ文言、GachaMachine（動きは `GachaMachineStage`）、「カプセル N個 · 共感ブースト」を並べる。
///
/// レバーを押す → 回転中（揺れ・レバーの回転・0.2 秒ごとの触覚）→ カプセルが落ちる → カプセルを押す → 開く → `onOpened`（S-14 はタスク 28）。
/// ほかの人が回したときは、購読で知って同じ演出を自動で再生する（`GachaModel`）。
/// 演出の段階が変わるたびに、タイトルとサブ文言を VoiceOver で読み上げる（開け終えたときは S-14 への切り替えで伝える）。
/// バナー広告は出さない（02 の F-50「表示しない画面：ガチャ」）。トーストはフルスクリーンカバーの中に重ねる。
struct GachaView: View {
    /// UI テストが探す ID
    enum Identifier {
        /// ガチャの画面
        static let screen = "gacha.screen"
        /// タイトル
        static let title = "gacha.title"
        /// サブ文言
        static let subtitle = "gacha.subtitle"
        /// 「カプセル N個 · 共感ブースト」
        static let capsuleCount = "gacha.capsuleCount"
    }

    /// サブ文言・カプセルの数の文字の大きさ（03 の S-13「13pt」）
    private static let captionSize: CGFloat = 13

    @State private var model: GachaModel
    /// トーストの窓口（フルスクリーンカバーの中に重ねる）
    private let toasts: DGToastCenter
    /// 常に「視差効果を減らす」で動かすか（UI テスト）
    private let forcesReducedMotion: Bool
    /// カプセルを開け終えたときの処理（抽選の ID を渡す。S-14 へ進む口）
    private let onOpened: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - model: 画面の状態（最初の 1 回だけ使う）
    ///   - toasts: トーストの窓口
    ///   - forcesReducedMotion: 常に「視差効果を減らす」で動かすか（UI テストで演出を待たないため）
    ///   - onOpened: カプセルを開け終えたときの処理
    init(model: GachaModel, toasts: DGToastCenter, forcesReducedMotion: Bool = false, onOpened: @escaping (String) -> Void) {
        _model = State(initialValue: model)
        self.toasts = toasts
        self.forcesReducedMotion = forcesReducedMotion
        self.onOpened = onOpened
    }

    var body: some View {
        VStack(spacing: 0) {
            DGHeader(Text(verbatim: model.room?.name ?? ""), onBack: { dismiss() })
                .padding(.leading, DGSpacing.s4)
                .dgContentColumn()
                // 演出の途中は閉じない（結果を見ないまま戻らないように）
                .disabled(!model.canClose)
            ScrollView {
                content
                    .padding(.horizontal, DGSpacing.screenX)
                    .dgContentColumn()
                    .padding(.top, DGSpacing.s8)
                    .padding(.bottom, DGSpacing.s24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .dgCentersContentOnTallScreen()
        }
        .background(Color.dgBgBase.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Identifier.screen)
        .dgToast(toasts)
        .sensoryFeedback(trigger: model.cue) { _, event in
            event?.cue.feedback
        }
        .task {
            model.reducesMotion = reduceMotion || forcesReducedMotion
            await model.observe()
        }
        .onChange(of: reduceMotion) { _, value in
            model.reducesMotion = value || forcesReducedMotion
        }
        .onChange(of: model.phase) { _, phase in
            announce(phase)
            if phase == .opened, let drawID = model.drawID {
                onOpened(drawID)
            }
        }
        .onDisappear {
            model.stop()
        }
    }

    /// タイトル・サブ文言・筐体・カプセルの数
    private var content: some View {
        VStack(spacing: DGSpacing.s16) {
            captionView
            GachaMachineStage(model: model, reduceMotion: model.reducesMotion)
            capsuleCountText
        }
        .frame(maxWidth: .infinity)
    }

    /// 段階ごとのタイトルとサブ文言（03 の S-13 の表）
    private var captionView: some View {
        let caption = model.caption
        return VStack(spacing: DGSpacing.s4) {
            Text(caption.title)
                .font(.dg(.displayL))
                .foregroundStyle(Color.dgInk)
                .accessibilityIdentifier(Identifier.title)
                .accessibilityAddTraits(.isHeader)
            Text(caption.subtitle)
                .font(.dgBody(Self.captionSize, relativeTo: .footnote))
                .foregroundStyle(Color.dgTextSecondary)
                .accessibilityIdentifier(Identifier.subtitle)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .animation(DGMotion.reducedFade, value: caption)
    }

    /// 「カプセル N個 · 共感ブースト」。
    ///
    /// 数はドームの VoiceOver のラベル（「ガチャ。カプセル N個」）でも読むので、ここではいいねの効き方だけを読む（同じ数を 2 回読まない）
    private var capsuleCountText: some View {
        let mode: Text = model.room?.settings.likeMode == .equal ? Text("みんな平等") : Text("共感ブースト")
        return Text("カプセル \(model.capsuleCount)個 · \(mode)")
            .font(.dgBody(Self.captionSize, relativeTo: .footnote))
            .foregroundStyle(Color.dgTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(mode)
            .accessibilityIdentifier(Identifier.capsuleCount)
    }

    /// 段階が変わったことを VoiceOver で読み上げる（待機は読まない）。
    ///
    /// 開け終えたときは読まない。S-14 に替わり、画面の切り替えの通知と S-14 の見出し「行き先が決まりました」で伝えるため
    /// （読み上げと画面の切り替えが重なると、どちらかが途中で切れる。`GachaFlowView`）
    private func announce(_ phase: GachaPhase) {
        switch phase {
        case .idle, .dropping, .opening, .opened:
            return
        case .spinning, .dispensed:
            let caption = model.caption
            let text = "\(String(localized: caption.title)) \(String(localized: caption.subtitle))"
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

extension GachaCaption {
    /// タイトル（見出し 24pt）
    var title: LocalizedStringResource {
        switch self {
        case .ready, .noCandidates, .locked: "レバーを回してね"
        case .spinning: "ガラガラ…"
        case let .drawnByOther(name): "\(name)さんが回しました！"
        case .dispensed: "カプセルをタップ！"
        }
    }

    /// サブ文言（13pt）
    var subtitle: LocalizedStringResource {
        switch self {
        case let .ready(isReroll): isReroll ? "引き直し（前回の当選は除外）" : "結果はメンバー全員の画面に同時に出ます"
        case .noCandidates: "候補がありません"
        case .locked: "まだガチャは解禁されていません"
        case .spinning, .drawnByOther: "どこに決まるかな"
        case .dispensed: "開けると行き先が決まります"
        }
    }
}

extension GachaCue {
    /// 合図の触覚（03 の S-13「レバーを押した瞬間 .impact(.heavy)、回転中は0.2秒ごとに .impact(.light)、
    /// カプセルが落ちた瞬間 .impact(.medium)、開いた瞬間 .success」）
    var feedback: SensoryFeedback {
        switch self {
        case .leverPulled: .impact(weight: .heavy)
        case .spinTick: .impact(weight: .light)
        case .capsuleLanded: .impact(weight: .medium)
        case .capsuleOpened: .success
        }
    }
}

#Preview("S-13 解禁済み") {
    let server = InMemoryServer.demo(.severalRooms)
    let toasts = DGToastCenter()
    GachaView(
        model: GachaModel(
            roomID: DemoScenario.unlockedRoomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: toasts,
            seenDraws: InMemorySeenDrawStore()
        ),
        toasts: toasts
    ) { _ in }
}

#Preview("S-13 文字を最大") {
    let server = InMemoryServer.demo(.severalRooms)
    let toasts = DGToastCenter()
    GachaView(
        model: GachaModel(
            roomID: DemoScenario.unlockedRoomID,
            userID: DemoScenario.myUserID,
            repository: server,
            functions: server,
            toasts: toasts,
            seenDraws: InMemorySeenDrawStore()
        ),
        toasts: toasts
    ) { _ in }
    .dynamicTypeSize(.accessibility5)
}
