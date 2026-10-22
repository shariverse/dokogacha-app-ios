//
//  UITestHelpers.swift
//  DokogachaUITests
//

import XCTest

/// UI テストの各クラスで共通に使う、待ち方と入力のしかた。
///
/// Mac が混んでいる（load average が 100 を超える）と、アプリの描き直しが遅れ、まとめて打ったキーが抜けたり、
/// スクロールが止まる前に押してしまったりする。ここでは「状態が変わったのを確かめてから次へ進む」形にそろえる
@MainActor
extension XCUIElement {
    /// 文言（`label`）が `label` になるまで待つ。なれば true
    func waitForLabel(_ label: String, timeout: TimeInterval = UITestID.timeout) -> Bool {
        wait(for: NSPredicate(format: "label == %@", label), timeout: timeout)
    }

    /// 値（入力欄の文字など）が `value` になるまで待つ。なれば true
    func waitForValue(_ value: String, timeout: TimeInterval = UITestID.timeout) -> Bool {
        wait(for: NSPredicate(format: "value == %@", value), timeout: timeout)
    }

    /// 押せる状態（`isEnabled`）になるまで待つ。なれば true
    func waitForEnabled(timeout: TimeInterval = UITestID.timeout) -> Bool {
        wait(for: NSPredicate(format: "enabled == true"), timeout: timeout)
    }

    /// 入力欄の文字を 1 文字ずつ消し、空（プレースホルダーの表示）になるまで続ける。
    ///
    /// 削除キーをまとめて打つと、負荷が高いときに抜けて文字が残る（招待コードは入力のたびに画面が値を直すので特に抜けやすい）。
    /// 1 回打つたびに値が変わるのを待ち、変わらなければ打ち直す。上限まで打っても空にならなければ失敗にする
    func clearText(file: StaticString = #filePath, line: UInt = #line) {
        let maxPresses = 30
        for _ in 0..<maxPresses {
            guard let current = value as? String, !current.isEmpty, current != placeholderValue else {
                return
            }
            typeText(XCUIKeyboardKey.delete.rawValue)
            _ = wait(for: NSPredicate(format: "value != %@", current), timeout: UITestID.keystrokeTimeout)
        }
        let rest = value as? String ?? ""
        XCTAssertTrue(rest.isEmpty || rest == placeholderValue, "入力欄を空にできませんでした: \(rest)", file: file, line: line)
    }

    /// 1 文字ずつ打ち、値が変わるのを待ってから次の文字を打つ（まとめて打つと、負荷が高いときに抜ける）
    func typeTextByCharacter(_ text: String) {
        for character in text {
            let before = value as? String ?? ""
            typeText(String(character))
            _ = wait(for: NSPredicate(format: "value != %@", before), timeout: UITestID.keystrokeTimeout)
        }
    }

    /// 画面をゆっくり上へ送り、この要素が押せる位置（`bottomLimit` より上）に来たら止める。来れば true。
    ///
    /// 遅延して並べる一覧では、画面の外の要素はまだ無い（`waitForExistence` で待っても出ない）ので、在るかどうかも送りながら確かめる。
    /// 呼ぶ前に、その画面が出たことを確かめておく。速く送ると、慣性で動いている間に押した操作がスクロールを止めるだけになり、ボタンが押されない
    /// 画面の上の方へ戻すときは `towardTop` を true にする（下へ送る）
    func scrollIntoView(
        in app: XCUIApplication,
        above bottomLimit: XCUIElement? = nil,
        towardTop: Bool = false,
        maxSwipes: Int = 6
    ) -> Bool {
        for _ in 0..<maxSwipes {
            if exists, isHittable, bottomLimit.map({ !$0.exists || frame.maxY <= $0.frame.minY }) ?? true {
                return true
            }
            if towardTop {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        return exists && isHittable
    }

    /// 述語が満たされるまで待つ
    private func wait(for predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

@MainActor
extension XCUIElementQuery {
    /// 識別子が `prefix` で始まり、文言に `text` を含む最初の要素（ID に作った時点の乱数が入る要素を探す）
    func first(identifierPrefix prefix: String, labelContaining text: String) -> XCUIElement {
        matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, text)).firstMatch
    }
}
