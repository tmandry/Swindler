import XCTest
import AXSwift
@testable import Swindler

class TestUIElement: UIElementType, Equatable {
  var attrs: [Attribute: Any] = [:]
  init() { }
  func pid() throws -> pid_t { return 0 }
  func attribute<T>(attribute: Attribute) throws -> T? {
    if let value = attrs[attribute] {
      return (value as! T)
    }
    return nil
  }
  func getMultipleAttributes(attributes: [AXSwift.Attribute]) throws -> [Attribute: Any] {
    var result: [Attribute: Any] = [:]
    for attribute in attributes {
      result[attribute] = attrs[attribute]
    }
    return result
  }
  func setAttribute(attribute: Attribute, value: Any) throws {
    attrs[attribute] = value
  }
}
func ==(lhs: TestUIElement, rhs: TestUIElement) -> Bool {
  return lhs === rhs
}

class BaseTestApplication: TestUIElement {
  typealias UIElementType = TestUIElement
  var toElement: TestUIElement { return self }
}
final class TestApplication: BaseTestApplication, ApplicationType {
  static func all() -> [TestApplication] { return [TestApplication()] }
}

class TestObserver: ObserverType {
  typealias UIElementType = TestUIElement
  required init(processID: pid_t, callback: (observer: TestObserver, element: UIElementType, notification: AXSwift.Notification) -> Void) throws {}
  func addNotification(notification: AXSwift.Notification, forElement: UIElementType) throws {}
}

class SwindlerTests: XCTestCase {

  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }

  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }

  func testExample() {
    class MyTestObserver: TestObserver {
      static var lastPid: pid_t = -1
      static var numObservers: Int = 0
      required init(processID: pid_t, callback: (observer: TestObserver, element: UIElementType, notification: AXSwift.Notification) -> Void) throws {
        MyTestObserver.lastPid = processID
        MyTestObserver.numObservers++
        try super.init(processID: processID, callback: callback)
      }
    }
    let _ = OSXState<TestUIElement, TestApplication, MyTestObserver>()
    XCTAssert(MyTestObserver.numObservers == 1)
    XCTAssert(MyTestObserver.lastPid == 0)
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
  }

}
