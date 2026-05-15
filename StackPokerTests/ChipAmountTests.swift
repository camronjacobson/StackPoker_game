import XCTest
@testable import StackPoker

final class ChipAmountTests: XCTestCase {

    // ── Construction ─────────────────────────────────────────────────────────

    func test_initInt_storesValue() {
        XCTAssertEqual(ChipAmount(500).rawValue, 500)
    }

    func test_initInt_clampsNegativeToZero() {
        // Negative prices shouldn't reach this initializer in practice,
        // but the type is total — clamp rather than crash.
        XCTAssertEqual(ChipAmount(-100).rawValue, 0)
    }

    func test_initRawValue_clampsNegativeToZero() {
        XCTAssertEqual(ChipAmount(rawValue: -1).rawValue, 0)
    }

    func test_initServerString_parsesValid() {
        XCTAssertEqual(ChipAmount(serverString: "12345")?.rawValue, 12345)
    }

    func test_initServerString_returnsNilOnGarbage() {
        XCTAssertNil(ChipAmount(serverString: "1.5K"))
        XCTAssertNil(ChipAmount(serverString: "abc"))
        XCTAssertNil(ChipAmount(serverString: ""))
        XCTAssertNil(ChipAmount(serverString: " 100 "))
        XCTAssertNil(ChipAmount(serverString: "1,000"))
    }

    func test_initServerString_acceptsZero() {
        XCTAssertEqual(ChipAmount(serverString: "0"), .zero)
    }

    func test_initServerString_handlesLargeBigIntInRange() {
        // Int64.max as a string round-trips cleanly.
        XCTAssertEqual(ChipAmount(serverString: String(Int64.max))?.rawValue, Int64.max)
    }

    // ── Subtraction ──────────────────────────────────────────────────────────

    func test_subtracting_successWhenSufficient() {
        let balance = ChipAmount(1000)
        switch balance.subtracting(ChipAmount(300)) {
        case .success(let remaining):
            XCTAssertEqual(remaining, ChipAmount(700))
        case .failure:
            XCTFail("Expected success")
        }
    }

    func test_subtracting_succeedsExactly() {
        // Buying with exact balance leaves zero, not insufficient funds.
        let balance = ChipAmount(500)
        switch balance.subtracting(ChipAmount(500)) {
        case .success(let remaining):
            XCTAssertEqual(remaining, .zero)
        case .failure:
            XCTFail("Exact-balance purchase must succeed")
        }
    }

    func test_subtracting_failureWhenShort() {
        let balance = ChipAmount(100)
        switch balance.subtracting(ChipAmount(250)) {
        case .success:
            XCTFail("Expected insufficient funds")
        case .failure(let err):
            XCTAssertEqual(err, .insufficientFunds(shortBy: ChipAmount(150)))
        }
    }

    func test_subtracting_zeroIsNoOp() {
        let balance = ChipAmount(42)
        let result = try? balance.subtracting(.zero).get()
        XCTAssertEqual(result, balance)
    }

    // ── Addition ─────────────────────────────────────────────────────────────

    func test_adding_basic() {
        XCTAssertEqual(ChipAmount(100).adding(ChipAmount(50)),
                       ChipAmount(150))
    }

    func test_adding_zeroIsNoOp() {
        XCTAssertEqual(ChipAmount(42).adding(.zero), ChipAmount(42))
    }

    // ── canAfford ────────────────────────────────────────────────────────────

    func test_canAfford_trueWhenEqual() {
        XCTAssertTrue(ChipAmount(500).canAfford(ChipAmount(500)))
    }

    func test_canAfford_trueWhenAbove() {
        XCTAssertTrue(ChipAmount(501).canAfford(ChipAmount(500)))
    }

    func test_canAfford_falseWhenBelow() {
        XCTAssertFalse(ChipAmount(499).canAfford(ChipAmount(500)))
    }

    // ── Comparable / Equatable ───────────────────────────────────────────────

    func test_comparable() {
        XCTAssertLessThan(ChipAmount(100), ChipAmount(200))
        XCTAssertGreaterThan(ChipAmount(300), ChipAmount(100))
        XCTAssertEqual(ChipAmount(100), ChipAmount(100))
    }

    // ── Round-trip ───────────────────────────────────────────────────────────

    func test_serverString_roundTrips() {
        let original = ChipAmount(serverString: "987654321")!
        XCTAssertEqual(ChipAmount(serverString: original.serverString), original)
    }

    func test_zeroServerString() {
        XCTAssertEqual(ChipAmount.zero.serverString, "0")
    }

    // ── Formatting ───────────────────────────────────────────────────────────

    func test_shortFormatted_underThousand() {
        XCTAssertEqual(ChipAmount(999).shortFormatted, "999")
    }

    func test_shortFormatted_thousands() {
        XCTAssertEqual(ChipAmount(1_500).shortFormatted, "1.5K")
        XCTAssertEqual(ChipAmount(12_300).shortFormatted, "12.3K")
    }

    func test_shortFormatted_millions() {
        XCTAssertEqual(ChipAmount(2_500_000).shortFormatted, "2.5M")
    }

    func test_shortFormatted_zero() {
        XCTAssertEqual(ChipAmount.zero.shortFormatted, "0")
    }

    func test_longFormatted_includesThousandsSeparator() {
        // Locale-aware separator — assert structurally rather than
        // hard-coding "," so this still passes for testers in EU locales.
        let formatted = ChipAmount(1_234_567).longFormatted
        XCTAssertEqual(formatted.filter(\.isNumber), "1234567")
        XCTAssertTrue(formatted.count > 7, "Expected grouping separators, got \(formatted)")
    }

    func test_longFormatted_smallNumber() {
        XCTAssertEqual(ChipAmount(42).longFormatted.filter(\.isNumber), "42")
    }
}
