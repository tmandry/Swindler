import Quick
import Nimble
import PromiseKit

func waitUntil(@autoclosure(escaping) expression: () throws -> Bool, file: String = __FILE__, line: UInt = __LINE__) {
  expect(try expression(), file: file, line: line).toEventually(beTrue())
}

func waitFor<T>(@autoclosure(escaping) expression: () throws -> T?, file: String = __FILE__, line: UInt = __LINE__) -> T? {
  expect(try expression(), file: file, line: line).toEventuallyNot(beNil())
  do {
    let result = try expression()
    return result!
  } catch {
    fail("Error thrown while retrieving value: \(error)")
    return nil
  }
}

func it<T>(desc: String, timeout: NSTimeInterval = 1.0, failOnError: Bool = true, file: String = __FILE__, line: UInt = __LINE__, closure: () -> Promise<T>) {
  setUpPromiseErrorHandler(file: file, line: line)
  it(desc, file: file, line: line, closure: {
    let promise = closure()
    waitUntil(timeout: timeout, file: file, line: line) { done in
      promise.then { _ in
        done()
      }.error { error in
        if failOnError {
          fail("Promise failed with error \(error)", file: file, line: line)
        }
        done()
      }
    }
  } as () -> ())
}

func setUpPromiseErrorHandler(file file: String, line: UInt) {
  PMKUnhandledErrorHandler = { error in
    fail("Unhandled error returned from promise: \(error)", file: file, line: line)
  }
}

func expectToFail<T, E: ErrorType>(promise: Promise<T>, with expectedError: E, file: String = __FILE__, line: UInt = __LINE__) -> Promise<Void> {
  return promise.asVoid().then({
    fail("Expected to fail with error \(expectedError), but succeeded", file: file, line: line)
  }).recover { (error: ErrorType) -> () in
    expect(file, line: line, expression: { throw error }).to(throwError(expectedError))
  }
}
