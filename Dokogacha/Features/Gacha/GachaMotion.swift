//
//  GachaMotion.swift
//  Dokogacha
//
//  S-13 の筐体の動き（04 の §5 の `shake`・`turn`・`tumble`・`exit`・`drop`・`open`。Issue #178）。
//  どれも段階に入ってからの秒から形を求める `nonisolated` の関数にし、画面（`GachaMachineStage`）は時刻から読んで描くだけにする。
//

import CoreGraphics
import Foundation

/// S-13 の筐体の動き。時刻（段階に入ってからの秒）から、ドーム・レバー・ドームのカプセル・取り出し口のカプセルの形を求める
nonisolated enum GachaMotion {
    // MARK: レバー（`turn`）

    /// レバーのバーを 1 刻みで回す角度（720° を 8 刻み。0.2 秒ごとの刻みの触覚と同じ数）
    static var leverStepDegrees: Double {
        GachaTimeline.turnDegrees / Double(leverStepCount)
    }

    /// レバーを回す刻みの数（回転中の 1.6 秒を 0.2 秒ずつ）
    static var leverStepCount: Int {
        Int((GachaTimeline.spinDuration / GachaTimeline.tickInterval).rounded())
    }

    /// 刻みで止まった後の行き過ぎの振れ幅（カチッと止まる手応え。減衰をかけるので、実際の行き過ぎは最大で約 4.3°）
    static let leverOvershootAmplitude: Double = 7
    /// 刻みの中で、行き過ぎから戻るまでの割合
    static let leverSettleFraction = 0.35

    /// 回し始めてから `time` 秒のレバーのバーの角度。
    ///
    /// 刻みごとに、力を入れて押し込むように加速して 90° 回り（`easeIn`）、刻みの終わり（触覚の刻みと同じ時刻）でカチッと止まり、
    /// 次の刻みの初めに少し行き過ぎてから戻る。回し終えたら 720°（見た目は 0° と同じ）
    static func leverAngle(at time: Double) -> Double {
        guard time > 0 else {
            return 0
        }
        let step = GachaTimeline.tickInterval
        let count = Double(leverStepCount)
        guard time < step * count else {
            return GachaTimeline.turnDegrees
        }
        let index = (time / step).rounded(.down)
        let within = (time - index * step) / step
        var angle = (index + RevealCurve.easeIn(within)) * leverStepDegrees
        if index > 0, within < leverSettleFraction {
            // 前の刻みでカチッと止まった後の行き過ぎ（すぐに戻る）
            let settle: Double = within / leverSettleFraction
            let wave: Double = sin(Double.pi * settle)
            angle += leverOvershootAmplitude * wave * (1 - settle)
        }
        return angle
    }

    // MARK: ドーム（`shake`）

    /// ドームの傾き（0 → −4° → 4° → −3° → 3° → 0 を 0.4 秒で繰り返す）。
    ///
    /// 回転中は、抽選の結果が 1.6 秒より遅く返っても揺れ続け、落ち始めたら `settleDuration` で 0 に収める
    /// - Parameters:
    ///   - spinTime: 回し始めてからの秒
    ///   - dropTime: 落ち始めてからの秒（まだ落ちていなければ nil）
    static func domeAngle(spinTime: Double, dropTime: Double?) -> Double {
        guard spinTime > 0 else {
            return 0
        }
        let cycle = DGMotion.shake.duration
        let within = spinTime.truncatingRemainder(dividingBy: cycle) / cycle
        let angles = [0] + GachaTimeline.shakeAngles
        let position = within * Double(GachaTimeline.shakeAngles.count)
        let index = min(Int(position), GachaTimeline.shakeAngles.count - 1)
        let angle = RevealCurve.mix(angles[index], angles[index + 1], RevealCurve.easeInOut(position - Double(index)))
        return angle * settleFactor(dropTime: dropTime)
    }

    /// 落ち始めてから、ドームの揺れ・カプセルのかき混ぜを収めるまでの時間
    static let settleDuration = 0.35

    /// 落ち始めてからの、揺れ・かき混ぜの残り（1 → 0。`(1 − 進み)²` で、はじめに大きく減らす。まだ落ちていなければ 1）
    static func settleFactor(dropTime: Double?) -> Double {
        guard let dropTime else {
            return 1
        }
        let rest = 1 - RevealCurve.progress(dropTime, from: 0, duration: settleDuration)
        return rest * rest
    }

    // MARK: ドームのカプセル（`tumble`）

    /// かき混ぜの強さが最大になるまでの時間
    static let tumbleRiseDuration = 0.25
    /// 横に揺れる幅（最小・幅）
    static let tumbleSway = (base: 6.0, spread: 10.0)
    /// 跳ねる高さ（最小・幅）
    static let tumbleHop = (base: 12.0, spread: 18.0)
    /// 回る速さ（ラジアン / 秒。最小・幅）
    static let tumbleSpeed = (base: 9.0, spread: 6.0)
    /// 転がる角度の速さ（度 / 秒。最小・幅）
    static let tumbleSpin = (base: 160.0, spread: 200.0)

    /// ドームのカプセル 1 個の、置き場所からのずれ
    typealias CapsuleTransform = DGGachaMachine.CapsuleTransform

    /// かき混ぜの強さ（0〜1。回し始めの 0.25 秒で強め、回転中は通信が遅くても続け、落ち始めたら `settleDuration` で収める）
    static func tumbleAmount(spinTime: Double, dropTime: Double?) -> Double {
        guard spinTime > 0 else {
            return 0
        }
        return RevealCurve.easeOut(spinTime / tumbleRiseDuration) * settleFactor(dropTime: dropTime)
    }

    /// かき混ぜの強さを時間で積んだもの（秒）。転がる角度はこれに比例させ、強さが下がっても巻き戻さずに減速して止める
    static func tumbleTravel(spinTime: Double, dropTime: Double?) -> Double {
        guard spinTime > 0 else {
            return 0
        }
        // 落ち始めた時点の、回し始めてからの秒
        let spinAtDrop = dropTime.map { max(spinTime - $0, 0) } ?? spinTime
        let beforeDrop = riseIntegral(min(spinTime, spinAtDrop))
        guard let dropTime, dropTime > 0 else {
            return beforeDrop
        }
        // 落ち始めた後は、強さ × (1 − 進み)² を積む（∫(1 − x)² dx = (1 − (1 − x)³) / 3）
        let settled = 1 - RevealCurve.progress(dropTime, from: 0, duration: settleDuration)
        let afterDrop = settleDuration * (1 - settled * settled * settled) / 3
        return beforeDrop + RevealCurve.easeOut(spinAtDrop / tumbleRiseDuration) * afterDrop
    }

    /// 強めていく間の強さ（`easeOut`）を 0 から `time` 秒まで積んだもの
    private static func riseIntegral(_ time: Double) -> Double {
        let rise = tumbleRiseDuration
        guard time > 0 else {
            return 0
        }
        guard time < rise else {
            return time - rise / 4
        }
        let rest = 1 - time / rise
        return time + rise / 4 * (rest * rest * rest * rest - 1)
    }

    /// `index` 番目のドームのカプセルのずれ（底で弾むように、上にだけ跳ねる。番号ごとに速さと向きをずらす）。
    ///
    /// 転がる角度は強さに比例した速さで積むので、収めるときも巻き戻らずに減速して止まり、止まった角度のまま残る
    /// - Parameters:
    ///   - index: カプセルの番号
    ///   - spinTime: 回し始めてからの秒
    ///   - dropTime: 落ち始めてからの秒（まだ落ちていなければ nil）
    static func tumble(index: Int, spinTime: Double, dropTime: Double?) -> CapsuleTransform {
        let travel = tumbleTravel(spinTime: spinTime, dropTime: dropTime)
        guard travel > 0 else {
            return .rest
        }
        let amount = tumbleAmount(spinTime: spinTime, dropTime: dropTime)
        let direction: Double = index.isMultiple(of: 2) ? 1 : -1
        let theta = 2 * Double.pi * unit(index, salt: 1)
            + direction * (tumbleSpeed.base + tumbleSpeed.spread * unit(index, salt: 2)) * spinTime
        let sway = tumbleSway.base + tumbleSway.spread * unit(index, salt: 3)
        let hop = tumbleHop.base + tumbleHop.spread * unit(index, salt: 4)
        let spin = tumbleSpin.base + tumbleSpin.spread * unit(index, salt: 5)
        let swayOffset: Double = amount * sway * cos(theta)
        let hopOffset: Double = -amount * hop * abs(sin(theta))
        return CapsuleTransform(
            offset: CGSize(width: swayOffset, height: hopOffset),
            turnDegrees: direction * spin * travel
        )
    }

    // MARK: 当選のカプセルが抜ける（`exit`）

    /// 当選のカプセルがドームの底から抜けるまでの時間（落ち始めてから）
    static var exitDuration: Double {
        GachaTimeline.exitDuration
    }

    /// ドームの底の抜け口（ドームの外形の左上からの位置。真ん中の下の、線の内側）
    static let exitPoint = CGPoint(
        x: DGGachaCapsuleLayout.domeDiameter / 2,
        y: DGGachaCapsuleLayout.domeDiameter - DGBorder.machine
    )
    /// 抜けきったときの大きさ
    static let exitScale = 0.7
    /// 抜ける途中で消え始める位置（抜ける時間に対する割合）
    static let exitFadeStart = 0.6

    /// 落ち始めてから `time` 秒の、当選のカプセルのずれ（置き場所 `center` から底の抜け口へ吸い込まれ、小さくなって消える）。
    /// かき混ぜていたときは、そのずれと角度を `machinePose` が重ねる
    static func exit(from center: CGPoint, at time: Double) -> CapsuleTransform {
        let progress = RevealCurve.progress(time, from: 0, duration: exitDuration)
        let pull = RevealCurve.easeIn(progress)
        return CapsuleTransform(
            offset: CGSize(width: (exitPoint.x - center.x) * pull, height: (exitPoint.y - center.y) * pull),
            turnDegrees: 0,
            scale: RevealCurve.mix(1, exitScale, pull),
            opacity: 1 - RevealCurve.progress(progress, from: exitFadeStart, duration: 1 - exitFadeStart)
        )
    }

    // MARK: 取り出し口のカプセル（`drop`）

    /// 取り出し口のカプセルの形
    struct DispensedPose: Equatable, Sendable {
        /// 縦のずれ（pt。上が負）
        var offsetY: Double = 0
        /// 不透明度
        var opacity: Double = 1
        /// 横・縦の大きさ（底に当たったときにつぶれる）
        var squash = CGSize(width: 1, height: 1)
        /// 転がる角度
        var rotationDegrees: Double = 0
    }

    /// 底に当たってつぶれたときの横・縦の大きさ
    static let landingSquash = CGSize(width: 1.12, height: 0.86)
    /// つぶれてから戻るまでの時間
    static let squashDuration = 0.12
    /// 跳ね返りで転がる角度
    static let rollDegrees: Double = -22

    /// 落ち始めてから `time` 秒の取り出し口のカプセル（ドームから抜けた後に、上 −90 から落ちて +6 → −8 → 0 と跳ね、
    /// 底に当たった瞬間につぶれ、跳ね返りで少し転がって戻る。プロトタイプの `dgDrop` に、つぶれと転がりを足したもの）
    static func dispensed(at time: Double) -> DispensedPose {
        let keys = GachaTimeline.DropKeyframes.self
        let drop = DGMotion.drop.duration
        let since = time - exitDuration
        guard since > 0 else {
            return DispensedPose(offsetY: keys.startOffset, opacity: 0)
        }
        guard since < drop else {
            return DispensedPose()
        }
        let landing = drop * keys.landingFraction
        let bounceTop = drop * keys.bounceFraction
        var pose = DispensedPose()
        if since < landing {
            let fall = RevealCurve.easeIn(since / landing)
            pose.offsetY = RevealCurve.mix(keys.startOffset, keys.landingOffset, fall)
            pose.opacity = RevealCurve.easeOut(since / landing)
            return pose
        }
        if since < bounceTop {
            let rise = RevealCurve.easeOut((since - landing) / (bounceTop - landing))
            pose.offsetY = RevealCurve.mix(keys.landingOffset, keys.bounceOffset, rise)
        } else {
            let settle = RevealCurve.easeIn(RevealCurve.progress(since, from: bounceTop, duration: drop - bounceTop))
            pose.offsetY = RevealCurve.mix(keys.bounceOffset, 0, settle)
        }
        let squash = 1 - RevealCurve.easeOut(RevealCurve.progress(since, from: landing, duration: squashDuration))
        pose.squash = CGSize(
            width: RevealCurve.mix(1, landingSquash.width, squash),
            height: RevealCurve.mix(1, landingSquash.height, squash)
        )
        let roll = RevealCurve.progress(since, from: landing, duration: drop - landing)
        pose.rotationDegrees = rollDegrees * sin(Double.pi * roll)
        return pose
    }

    // MARK: 筐体の形

    /// 段階に入ってからの秒（まだその段階に入っていなければ nil）
    struct StageTimes: Equatable, Sendable {
        /// 回し始めてからの秒
        var spin: Double?
        /// 落ち始めてからの秒
        var drop: Double?
        /// 開け始めてからの秒
        var open: Double?
    }

    /// 時刻から筐体の動かす値を組み立てる（`GachaMachineStage` が毎フレーム呼ぶ）。
    ///
    /// 「視差効果を減らす」では動かさない（静止状態）。そのときは画面が取り出し口にカプセルを出さず、S-14 へのフェードだけで替える
    /// - Parameters:
    ///   - times: 段階に入ってからの秒
    ///   - capsuleCount: ドームのカプセルの数
    ///   - winnerIndex: 当選のカプセルのドームの中の番号（分からなければ nil）
    ///   - reduceMotion: 「視差効果を減らす」か
    static func machinePose(times: StageTimes, capsuleCount: Int, winnerIndex: Int?, reduceMotion: Bool) -> DGGachaMachine.Pose {
        var pose = DGGachaMachine.Pose()
        guard !reduceMotion else {
            return pose
        }
        let spinTime = times.spin
        let dropTime = times.drop
        let openTime = times.open
        if let spinTime {
            pose.domeRotationDegrees = domeAngle(spinTime: spinTime, dropTime: dropTime)
            pose.leverRotationDegrees = leverAngle(at: spinTime)
            for index in 0..<min(capsuleCount, DGGachaCapsuleLayout.maxVisibleCount) {
                pose.capsuleTransforms[index] = tumble(index: index, spinTime: spinTime, dropTime: dropTime)
            }
        }
        if let dropTime {
            if let winnerIndex, let center = DGGachaCapsuleLayout.center(at: winnerIndex) {
                var transform = exit(from: center, at: dropTime)
                if let spinTime {
                    // 落ち始めた瞬間のかき混ぜの形から続けて抜く（かき混ぜのずれは抜ける時間と同じ 0.35 秒で 0 に収まる。
                    // 置き場所から抜き始めると、落ち始めの 1 フレームで位置と角度が跳ぶ）
                    let tumbling = tumble(index: winnerIndex, spinTime: spinTime, dropTime: dropTime)
                    transform.offset.width += tumbling.offset.width
                    transform.offset.height += tumbling.offset.height
                    transform.turnDegrees = tumbling.turnDegrees
                }
                pose.capsuleTransforms[winnerIndex] = transform
                // 抜けるときに、ほかのカプセルの後ろに隠れないよう手前に描く
                pose.frontCapsuleIndex = winnerIndex
            }
            let dispensed = dispensed(at: dropTime)
            pose.dispensedOffsetY = dispensed.offsetY
            pose.dispensedOpacity = dispensed.opacity
            pose.dispensedSquash = dispensed.squash
            pose.dispensedRotationDegrees = dispensed.rotationDegrees
        }
        if let openTime {
            let open = RevealCurve.easeIn(RevealCurve.progress(openTime, from: 0, duration: DGMotion.open.duration))
            pose.dispensedScale = RevealCurve.mix(1, GachaTimeline.openScale, open)
            pose.dispensedOpacity = 1 - open
        }
        return pose
    }

    /// 番号と種から作る 0〜1 の値（同じ番号なら毎回同じ）
    private static func unit(_ index: Int, salt: Int) -> Double {
        let value = sin(Double(index * 193 + salt * 457) * 12.9898) * 43_758.5453
        return value - value.rounded(.down)
    }
}
