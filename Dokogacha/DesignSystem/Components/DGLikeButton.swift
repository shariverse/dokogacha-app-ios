//
//  DGLikeButton.swift
//  Dokogacha
//
//  候補カードのいいねボタン（`04_design_system.md` の §4 の CandidateCard の「いいねボタン」・02 の F-20）。
//

import SwiftUI

/// ハートと、その下の文言（「いいね」「いいね済」「自分」）を縦に並べたボタン。
///
/// 52×52・角丸 14・線なし。ハート 22 ＋下に 11 の文言。背景と色は `like.*`。
/// いいね済みはハートを塗りつぶす（`ui-heart` は線画のテンプレート画像で塗りを切り替えられないので、塗りつぶした版の `ui-heart-fill` に替える）。
/// 自分の投稿（F-20）と、いいねを受け付けないルーム（`drawn`・`closed`。02 の §2.1）では押せない。
/// 押した瞬間にハートを 1.0 → 1.25 → 1.0 に弾ませ（04 の §5 の「いいね」。`DGMotion.like`）、
/// 「視差効果を減らす」がオンのときは弾ませない。
struct DGLikeButton: View {
    /// いいねボタンの状態
    nonisolated enum Status: CaseIterable, Sendable {
        /// まだいいねしていない
        case notLiked
        /// いいね済み（もう一度押すと取り消す）
        case liked
        /// 自分の投稿（いいねできない）
        case mine
        /// いいねを受け付けないルーム（`drawn`・`closed`）で、いいねしていない
        case locked
        /// いいねを受け付けないルーム（`drawn`・`closed`）で、いいね済み（取り消せない）
        case lockedLiked

        /// ハートの下の文言（受け付けないときも、いいねしたかどうかは残して見せる）
        var title: LocalizedStringResource {
            switch self {
            case .notLiked, .locked: "いいね"
            case .liked, .lockedLiked: "いいね済"
            case .mine: "自分"
            }
        }

        /// VoiceOver で読むボタンの名前（押すと何が起きるか。押せないときは、なぜ押せないか）
        var accessibilityLabel: LocalizedStringResource {
            switch self {
            case .notLiked: "いいね"
            case .liked: "いいねを取り消す"
            case .mine: "自分の投稿にはいいねできません"
            case .locked: "いいねの受付は終わりました"
            case .lockedLiked: "いいね済み。いいねの受付は終わりました"
            }
        }

        /// いいね済みか（ハートを塗りつぶし、VoiceOver で選択中として読む）
        var isLiked: Bool {
            self == .liked || self == .lockedLiked
        }

        /// 背景色（いいね済みでも、押せないときは押せる「いいね済」と見分けられるよう未いいねの色にする）
        var background: Color {
            self == .liked ? .dgLikeBgActive : .dgLikeBg
        }

        /// ハートと文言の色（押せないものは「自分」と同じ薄い色）
        var foreground: Color {
            switch self {
            case .notLiked: .dgLikeIcon
            case .liked: .dgLikeIconActive
            case .mine, .locked, .lockedLiked: .dgLikeIconMine
            }
        }

        /// ハートのアセット名（いいね済みだけ塗りつぶした版）
        var heartIconName: String {
            isLiked ? "ui-heart-fill" : "ui-heart"
        }

        /// 押せるか（自分の投稿と、いいねを受け付けないルームでは押せない）
        var isEnabled: Bool {
            self == .notLiked || self == .liked
        }
    }

    /// ボタンの一辺（最小。文字が大きくなったら伸びる）
    private static let side: CGFloat = 52
    /// 角丸
    private static let cornerRadius: CGFloat = 14
    /// ハートの一辺
    private static let heartSize: CGFloat = 22
    /// 文言の大きさ
    private static let titleSize: CGFloat = 11

    /// いまの状態
    let state: Status
    /// 押したときの処理（いいね・取り消しの切り替え）
    let action: () -> Void

    /// ハートを弾ませるきっかけ。押すたびに増やす
    @State private var popCount = 0
    /// ハートを Dynamic Type に合わせて大きくする倍率
    @ScaledMetric(relativeTo: .caption) private var heartScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        Button {
            if !reduceMotion {
                popCount += 1
            }
            action()
        } label: {
            VStack(spacing: 0) {
                Image(state.heartIconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.heartSize * heartScale, height: Self.heartSize * heartScale)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: popCount) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(DGMotion.likeScale, duration: DGMotion.like.duration / 2)
                        SpringKeyframe(1, duration: DGMotion.like.duration / 2)
                    }
                Text(state.title)
                    .font(.dgBody(Self.titleSize, weight: .black, relativeTo: .caption))
                    .lineLimit(1)
            }
            .foregroundStyle(state.foreground)
            .padding(DGSpacing.s4)
            .frame(minWidth: Self.side, minHeight: Self.side)
            .background(state.background, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.dgBare)
        .disabled(!state.isEnabled)
        .fixedSize()
        .accessibilityLabel(Text(state.accessibilityLabel))
        .accessibilityAddTraits(state.isLiked ? .isSelected : [])
    }
}

#Preview("LikeButton 状態ごと") {
    HStack(spacing: DGSpacing.s16) {
        ForEach(DGLikeButton.Status.allCases, id: \.self) { state in
            DGLikeButton(state: state) {}
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("LikeButton 押して切り替え") {
    @Previewable @State var isLiked = false
    DGLikeButton(state: isLiked ? .liked : .notLiked) {
        isLiked.toggle()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
}

#Preview("LikeButton 文字を最大") {
    HStack(spacing: DGSpacing.s16) {
        ForEach(DGLikeButton.Status.allCases, id: \.self) { state in
            DGLikeButton(state: state) {}
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dgSurfaceCard)
    .dynamicTypeSize(.accessibility5)
}
