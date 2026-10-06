import CoreGraphics
import Foundation
import Testing
@testable import HiveCore

/// Two-column grid: lu.01 lu.02 / or.01 or.02 / fj.01
private let grid: [String: CGRect] = [
    "lu.01": CGRect(x: 0, y: 0, width: 100, height: 80),
    "lu.02": CGRect(x: 120, y: 0, width: 100, height: 80),
    "or.01": CGRect(x: 0, y: 100, width: 100, height: 120),
    "or.02": CGRect(x: 120, y: 100, width: 100, height: 60),
    "fj.01": CGRect(x: 0, y: 260, width: 100, height: 80),
]
private let gridOrder = ["lu.01", "lu.02", "or.01", "or.02", "fj.01"]

private func go(_ sel: String?, _ d: SessionNav.Direction, _ frames: [String: CGRect] = grid,
                order: [String] = gridOrder) -> String? {
    SessionNav.target(from: sel, d, frames: frames, order: order)
}

@Test func downGoesToTheCardBelow() {
    #expect(go("lu.02", .down) == "or.02")
    #expect(go("or.01", .down) == "fj.01")
}

@Test func downFromTheRightColumnTakesTheClosestInTheShorterRow() {
    #expect(go("or.02", .down) == "fj.01")
}

@Test func upGoesToTheCardAbove() {
    #expect(go("or.02", .up) == "lu.02")
    #expect(go("fj.01", .up) == "or.01")
}

@Test func leftAndRightFollowTheReadingOrder() {
    #expect(go("lu.01", .right) == "lu.02")
    #expect(go("lu.02", .right) == "or.01")
    #expect(go("or.01", .left) == "lu.02")
}

@Test func atTheEdgeTheSelectionStays() {
    #expect(go("lu.01", .up) == "lu.01")
    #expect(go("lu.01", .left) == "lu.01")
    #expect(go("fj.01", .down) == "fj.01")
    #expect(go("fj.01", .right) == "fj.01")
}

@Test func withoutSelectionFirstOrLast() {
    #expect(go(nil, .down) == "lu.01")
    #expect(go(nil, .right) == "lu.01")
    #expect(go(nil, .up) == "fj.01")
    #expect(go("ki.01", .down) == "lu.01")  // selected, but not shown (e.g. offline collapsed)
}

@Test func undrawnSessionsAreReachedThroughTheOrder() {
    // lazy list: only the first two rows are drawn
    let list: [String: CGRect] = [
        "lu.01": CGRect(x: 0, y: 0, width: 300, height: 40),
        "lu.02": CGRect(x: 0, y: 40, width: 300, height: 40),
    ]
    let order = ["lu.01", "lu.02", "or.01"]
    #expect(go("lu.02", .down, list, order: order) == "or.01")
    #expect(go("lu.02", .right, list, order: order) == "or.01")
    #expect(go("lu.01", .up, list, order: order) == "lu.01")
}

@Test func nothingDrawnFallsBackToTheOrder() {
    #expect(go(nil, .down, [:], order: ["lu.01", "or.01"]) == "lu.01")
    #expect(go(nil, .down, [:], order: []) == nil)
}
