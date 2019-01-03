import Quick
import Nimble
import PromiseKit

func waitUntil(_ expression: @autoclosure @escaping () throws -> Bool,
               file: String = #file,
               line: UInt = #line) {
    expect(try expression(), file: file, line: line).toEventually(beTrue())
}

func waitFor<T>(_ expression: @autoclosure @escaping () throws -> T?,
                file: String = #file,
                line: UInt = #line) -> T? {
    expect(try expression(), file: file, line: line).toEventuallyNot(beNil())
    do {
        let result = try expression()
        return result!
    } catch {
        fail("Error thrown while retrieving value: \(error)")
        return nil
    }
}

func it<T>(_ desc: String,
           timeout: TimeInterval = 1.0,
           failOnError: Bool = true,
           file: String = #file,
           line: UInt = #line,
           closure: @escaping () -> Promise<T>) {
    it(desc, file: file, line: line, closure: {
        let promise = closure()
        waitUntil(timeout: timeout, file: file, line: line) { done in
            promise.done { _ in
                done()
            }.catch { error in
                if failOnError {
                    fail("Promise failed with error \(error)", file: file, line: line)
                }
                done()
            }
        }
    } as () -> Void)
}

func expectToSucceed<T>(_ promise: Promise<T>, file: String = #file, line: UInt = #line)
-> Promise<Void> {
    return promise.asVoid().recover { (error: Error) -> Void in
        fail("Expected promise to succeed, but failed with \(error)", file: file, line: line)
    }
}

func expectToFail<T>(_ promise: Promise<T>, file: String = #file, line: UInt = #line)
-> Promise<Void> {
    return promise.asVoid().done {
        fail("Expected promise to fail, but succeeded", file: file, line: line)
    }.recover { (error: Error) -> Promise<Void> in
        expect(file, line: line, expression: { throw error }).to(throwError())
        return Promise.value(())
    }
}

func expectToFail<T, E: Error>(_ promise: Promise<T>,
                               with expectedError: E,
                               file: String = #file,
                               line: UInt = #line) -> Promise<Void> {
    return promise.asVoid().done {
        fail("Expected promise to fail with error \(expectedError), but succeeded",
             file: file, line: line)
    }.recover { (error: Error) -> Void in
        expect(file, line: line, expression: { throw error }).to(throwError(expectedError))
    }
}

/// Convenience struct for when errors need to be thrown from tests to abort execution (e.g. during
/// a promise chain).
struct TestError: Error {
    let description: String
    init(_ description: String) { self.description = description }
}
