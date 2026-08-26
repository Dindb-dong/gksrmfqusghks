import Foundation
import HanKeyCore
import XCTest

final class DubeolsikConverterTests: XCTestCase {
  func testProductExamplesInBothDirections() {
    XCTAssertEqual(DubeolsikConverter.compose("gksrmffh"), "한글로")
    XCTAssertEqual(DubeolsikConverter.decomposeToQWERTY("한글로"), "gksrmffh")
    XCTAssertEqual(DubeolsikConverter.compose("yonsei"), "ㅛㅐㅜㄴ댜")
    XCTAssertEqual(DubeolsikConverter.decomposeToQWERTY("ㅛㅐㅜㄴ댜"), "yonsei")
  }

  func testShiftedJamo() {
    XCTAssertEqual(DubeolsikConverter.compose("Qk"), "빠")
    XCTAssertEqual(DubeolsikConverter.compose("Rk"), "까")
    XCTAssertEqual(DubeolsikConverter.compose("Ek"), "따")
    XCTAssertEqual(DubeolsikConverter.compose("Wk"), "짜")
    XCTAssertEqual(DubeolsikConverter.compose("Tk"), "싸")
    XCTAssertEqual(DubeolsikConverter.compose("dO"), "얘")
    XCTAssertEqual(DubeolsikConverter.compose("dP"), "예")
  }

  func testCompoundMedials() {
    XCTAssertEqual(DubeolsikConverter.compose("dhk"), "와")
    XCTAssertEqual(DubeolsikConverter.compose("dho"), "왜")
    XCTAssertEqual(DubeolsikConverter.compose("dhl"), "외")
    XCTAssertEqual(DubeolsikConverter.compose("dnj"), "워")
    XCTAssertEqual(DubeolsikConverter.compose("dnp"), "웨")
    XCTAssertEqual(DubeolsikConverter.compose("dnl"), "위")
    XCTAssertEqual(DubeolsikConverter.compose("dml"), "의")
  }

  func testFinalMigrationAndCompoundFinalSplit() {
    XCTAssertEqual(DubeolsikConverter.compose("gksrmf"), "한글")
    XCTAssertEqual(DubeolsikConverter.compose("ekfr"), "닭")
    XCTAssertEqual(DubeolsikConverter.compose("ekfrl"), "달기")
    XCTAssertEqual(DubeolsikConverter.compose("ekfrdms"), "닭은")
  }

  func testStandaloneJamoAndUnsupportedCharactersArePreserved() {
    XCTAssertEqual(DubeolsikConverter.compose("y o n"), "ㅛ ㅐ ㅜ")
    XCTAssertEqual(DubeolsikConverter.decomposeToQWERTY("ㄳㅘㅢ"), "rthkml")
    XCTAssertEqual(DubeolsikConverter.compose("gksrmf 123"), "한글 123")
  }

  func testCanonicalDecomposedHangulMapsToTheSameKeys() {
    let decomposed = "한글".decomposedStringWithCanonicalMapping
    XCTAssertEqual(DubeolsikConverter.decomposeToQWERTY(decomposed), "gksrmf")
  }

  func testAllModernHangulSyllablesRoundTripThroughPhysicalKeys() throws {
    for scalarValue in UInt32(0xAC00)...UInt32(0xD7A3) {
      let scalar = try XCTUnwrap(Unicode.Scalar(scalarValue))
      let syllable = String(scalar)
      let keys = DubeolsikConverter.decomposeToQWERTY(syllable)
      XCTAssertEqual(
        DubeolsikConverter.compose(keys),
        syllable,
        "Round trip failed for U+\(String(scalarValue, radix: 16, uppercase: true)) via \(keys)"
      )
    }
  }
}
