import Foundation
import XCTest
import OortCore

final class LineBufferTests: XCTestCase {
    func testLineBufferSplitsOnReturnAndNewline() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("Receiving objects:  1%\rReceiving obj".utf8)), ["Receiving objects:  1%"])
        XCTAssertEqual(buffer.append(Data("ects:  2%\r\ndone\n\n".utf8)), ["Receiving objects:  2%", "done"])
        XCTAssertEqual(buffer.append(Data("tail".utf8)), [])
        XCTAssertEqual(buffer.finish(), ["tail"])
        XCTAssertEqual(buffer.finish(), [])
    }
}
