import HanKeyCore
import XCTest

final class PhysicalKeyTokenTests: XCTestCase {
  func testNormalizesASCIIShiftState() throws {
    let lowercase = try XCTUnwrap(PhysicalKeyToken(ascii: "r"))
    XCTAssertEqual(lowercase.qwertyLetter, "r")
    XCTAssertFalse(lowercase.isShifted)
    XCTAssertEqual(lowercase.ascii, "r")

    let uppercase = try XCTUnwrap(PhysicalKeyToken(ascii: "R"))
    XCTAssertEqual(uppercase.qwertyLetter, "r")
    XCTAssertTrue(uppercase.isShifted)
    XCTAssertEqual(uppercase.ascii, "R")
  }

  func testRejectsNonLetterAndNonASCIIInput() {
    XCTAssertNil(PhysicalKeyToken(ascii: "1"))
    XCTAssertNil(PhysicalKeyToken(ascii: "한"))
    XCTAssertNil(PhysicalKeyToken(qwertyLetter: "R", isShifted: false))
  }
}
