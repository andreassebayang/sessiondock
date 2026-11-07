import Foundation
import Testing

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a == b, Comment(rawValue: message), sourceLocation: sourceLocation)
}
func XCTAssertFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
func XCTAssertTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, sourceLocation: sourceLocation) }
func XCTFail(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) { Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation) }
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try value() } catch { Issue.record(Comment(rawValue: "Unexpected error. " + message), sourceLocation: sourceLocation) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try value(); Issue.record(Comment(rawValue: "Expected rejection. " + message), sourceLocation: sourceLocation) } catch {}
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw TestFailure.missingValue }; return value
}
enum TestFailure: Error { case missingValue }
