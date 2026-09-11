import XCTest

extension XCTestCase {
    func assertAsyncThrows<T, E: Error>(
        expectedType: E.Type,
        _ expression: () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        errorHandler: ((E) -> Void)? = nil
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected \(expectedType) to be thrown but expression succeeded. \(message())", file: file, line: line)
        } catch let error as E {
            errorHandler?(error)
        } catch {
            XCTFail("Expected \(expectedType) but caught \(type(of: error)): \(error). \(message())", file: file, line: line)
        }
    }
}
