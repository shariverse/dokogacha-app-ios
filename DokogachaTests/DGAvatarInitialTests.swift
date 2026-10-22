//
//  DGAvatarInitialTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// アバターに出す 1 文字（`DGAvatarInitial`）を確かめる。
struct DGAvatarInitialTests {
    /// 表示名と、アバターに出す 1 文字の組
    nonisolated static let cases: [(name: String, initial: String)] = [
        ("ゆい", "ゆ"),
        ("けんた", "け"),
        ("  みさき ", "み"),
        ("sora", "S"),
        ("ßen", "S"),
        ("がっちゃん", "が"),
        ("か\u{3099}ちゃ", "か\u{3099}"),
        ("👨‍👩‍👧家族", "👨‍👩‍👧"),
        ("", ""),
        ("   ", "")
    ]

    /// 前後の空白を除いた 1 文字目（書記素）を、英字は大文字にして返す
    @Test(arguments: Self.cases)
    func initialIsFirstCharacter(name: String, initial: String) {
        #expect(DGAvatarInitial.make(from: name) == initial)
    }
}
