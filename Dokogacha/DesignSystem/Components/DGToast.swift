//
//  DGToast.swift
//  Dokogacha
//
//  トースト（`04_design_system.md` の §4 の Toast・§5 の `toast`、03 の §3）。
//  画面の Model は `DGToastCenter.show(_:)` で文言を渡し、画面の根元に `.dgToast(_:)` を付けて出す。
//

import SwiftUI

/// トーストの見た目（墨色の角丸の帯に白文字）。
///
/// 背景 `ink`・白・本文 Bold 14・左右 18・上下 12・角丸 14。文字が大きいときや長いときは折り返す。
struct DGToast: View {
    /// 画面の下端からトーストの下端までの距離（03 の §3「画面下から150pt」）
    static let bottomOffset: CGFloat = 150
    /// 角丸
    private static let cornerRadius: CGFloat = 14
    /// 左右の余白
    private static let horizontalPadding: CGFloat = 18

    /// 出す文言（翻訳済み）
    let text: String

    /// - Parameter message: 出す文言（03 の表記）
    init(_ message: LocalizedStringResource) {
        text = String(localized: message)
    }

    /// - Parameter text: 出す文言（翻訳済みの文字列。`DGToastCenter` から渡す）
    init(verbatim text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.dgBody(14, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(Color.dgTextOnAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, DGSpacing.s12)
            .background(Color.dgInk, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// トースト 1 件分（文言と、同じ文言を続けて出すときに区別するための ID）。
nonisolated struct DGToastMessage: Identifiable, Equatable, Sendable {
    /// 1 件ごとの ID
    let id: UUID
    /// 出す文言（翻訳済み）
    let text: String

    /// - Parameters:
    ///   - id: 1 件ごとの ID（テストでは固定の値を渡す）
    ///   - text: 出す文言（翻訳済み）
    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// トーストの表示の順番（いま出している 1 件と、待っているもの）。
///
/// トーストは 1 件ずつ出し、出している間に来たものは後ろに並べる（重ねて出すと読めないため）。
/// 同じ文言が出ている・最後に待っているときは足さない（いいねの失敗などで「通信できませんでした」が続けて並ばないように）。
nonisolated struct DGToastQueue: Equatable, Sendable {
    /// いま出しているトースト。無ければ `nil`
    private(set) var current: DGToastMessage?
    /// 出すのを待っているトースト（先頭から順に出す）
    private(set) var pending: [DGToastMessage] = []

    /// トーストを足す。
    /// - Parameter message: 足すトースト
    /// - Returns: 足したトーストをすぐに出す（いま出しているものが無かった）なら `true`
    @discardableResult
    mutating func enqueue(_ message: DGToastMessage) -> Bool {
        let last = pending.last ?? current
        guard last?.text != message.text else {
            return false
        }
        guard current == nil else {
            pending.append(message)
            return false
        }
        current = message
        return true
    }

    /// いま出しているトーストを消し、待っているものがあれば次を出す。
    /// - Returns: 次に出すトースト。待っているものが無ければ `nil`
    @discardableResult
    mutating func advance() -> DGToastMessage? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }
}

/// トーストを出す窓口。画面の Model や画面から `show(_:)` で文言を渡す。
///
/// 1 件を `DGMotion.toastVisibleFor`（2.2 秒）出したら次に進む。トーストをタップしても消せる。
/// 出すときに VoiceOver で文言を読み上げる。
@Observable
final class DGToastCenter {
    /// 表示の順番
    private(set) var queue = DGToastQueue()
    /// 1 件を出しておく時間
    @ObservationIgnored private let visibleFor: Duration
    /// いま出しているトーストを消すまでの待ち
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// いま出しているトースト
    var current: DGToastMessage? {
        queue.current
    }

    /// - Parameter visibleFor: 1 件を出しておく時間（既定はトークンの 2.2 秒）
    init(visibleFor: Duration = .seconds(DGMotion.toastVisibleFor)) {
        self.visibleFor = visibleFor
    }

    /// トーストを出す（出しているものがあれば、その後に出す）。
    /// - Parameter message: 出す文言（03 の表記）
    func show(_ message: LocalizedStringResource) {
        show(text: String(localized: message))
    }

    /// 翻訳済みの文字列でトーストを出す。
    /// - Parameter text: 出す文言
    func show(text: String) {
        if queue.enqueue(DGToastMessage(text: text)) {
            present()
        }
    }

    /// いま出しているトーストを消し、待っているものがあれば次を出す
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if queue.advance() != nil {
            present()
        }
    }

    /// いま出しているトーストを読み上げ、出しておく時間が過ぎたら消す
    private func present() {
        guard let current else {
            return
        }
        AccessibilityNotification.Announcement(current.text).post()
        dismissTask?.cancel()
        let visibleFor = visibleFor
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: visibleFor)
            guard !Task.isCancelled else {
                return
            }
            self?.dismiss()
        }
    }
}

/// `DGToastCenter` のトーストを画面の下から 150 の位置に重ねる。
///
/// 下から 12 上がりながらフェードインする（0.25 秒）。「視差効果を減らす」がオンのときはフェード 0.2 秒だけにする。
private struct DGToastPresenter: ViewModifier {
    /// トーストが下から上がる距離（04 の §5 の `toast`）
    private static let riseDistance: CGFloat = 12

    let center: DGToastCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if let message = center.current {
                    DGToast(verbatim: message.text)
                        .id(message.id)
                        .transition(transition)
                        .onTapGesture { center.dismiss() }
                }
            }
            .padding(.horizontal, DGSpacing.screenX)
            .padding(.bottom, DGToast.bottomOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(reduceMotion ? DGMotion.reducedFade : DGMotion.toast.animation, value: center.current)
        }
    }

    /// 出入りの動き
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Self.riseDistance))
    }
}

extension View {
    /// `DGToastCenter` のトーストをこのビューに重ねて出す。画面の根元（画面いっぱいのビュー）に付ける。
    /// - Parameter center: トーストを出す窓口
    func dgToast(_ center: DGToastCenter) -> some View {
        modifier(DGToastPresenter(center: center))
    }
}

#Preview("Toast 見た目") {
    VStack(spacing: DGSpacing.s16) {
        DGToast("候補に追加しました")
        DGToast("通信できませんでした")
        DGToast("過去のアイデアを持ち込みました")
            .dynamicTypeSize(.accessibility5)
    }
    .padding(DGSpacing.screenX)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
}

#Preview("Toast 出し入れ") {
    @Previewable @State var center = DGToastCenter()
    VStack(spacing: DGSpacing.s16) {
        DGButton("候補に追加しました", kind: .secondary) { center.show("候補に追加しました") }
        DGButton("通信できませんでした", kind: .secondary) { center.show("通信できませんでした") }
    }
    .padding(DGSpacing.screenX)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgBgBase)
    .dgToast(center)
}
