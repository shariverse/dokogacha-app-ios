//
//  DGStatusChipStatusTests.swift
//  DokogachaTests
//

@testable import Dokogacha
import Testing

/// ルームの状態（`RoomStatus`）から状態チップの状態への対応を確かめる。
struct DGStatusChipStatusTests {
    /// 4 つの状態が同じ名前の状態に 1 対 1 で対応する
    @Test
    func mapsRoomStatus() {
        #expect(DGStatusChip.Status(.open) == .open)
        #expect(DGStatusChip.Status(.unlocked) == .unlocked)
        #expect(DGStatusChip.Status(.drawn) == .drawn)
        #expect(DGStatusChip.Status(.closed) == .closed)
        #expect(Set(RoomStatus.allCases.map(DGStatusChip.Status.init)).count == DGStatusChip.Status.allCases.count)
    }
}
