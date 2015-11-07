import Quick
import Nimble

@testable import Swindler
import AXSwift

class TestUIElement: UIElementType, Equatable {
  var processID: pid_t = 0
  var attrs: [Attribute: Any] = [:]
  init() { }
  func pid() throws -> pid_t { return processID }
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

  static var processCount: pid_t = 0
  override init() {
    super.init()
    BaseTestApplication.processCount++
    self.processID = BaseTestApplication.processCount
  }
}

class TestObserver: ObserverType {
  typealias UIElementType = TestUIElement
  typealias Callback = (observer: TestObserver, element: UIElementType, notification: AXSwift.Notification) -> ()

  var callback: Callback!

  required init(processID: pid_t, callback: Callback) throws {
    self.callback = callback
  }
  func addNotification(notification: AXSwift.Notification, forElement: UIElementType) throws {}
}


// Can't define this inside the spec, due to a Swift bug.
final class TestApplication: BaseTestApplication, ApplicationType {
  static var allApps: [TestApplication] = []
  static func all() -> [TestApplication] { return TestApplication.allApps }
}

class OSXStateSpec: QuickSpec {
  override func spec() {
    beforeEach { TestApplication.allApps = [] }

    describe("initialization") {

      it("observes all applications") {
        class MyTestObserver: TestObserver {
          static var numObservers: Int = 0
          required init(processID: pid_t, callback: Callback) throws {
            MyTestObserver.numObservers++
            try super.init(processID: processID, callback: callback)
          }
        }

        TestApplication.allApps = [TestApplication(), TestApplication()]
        let _ = OSXState<TestUIElement, TestApplication, MyTestObserver>()

        expect(MyTestObserver.numObservers).to(equal(2), description: "observer count")
      }

    }

  }
}
