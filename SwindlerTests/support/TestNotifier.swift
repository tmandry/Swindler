import Nimble

@testable import Swindler

class TestNotifier: EventNotifier {
  var events: [EventType] = []
  func notify<Event: EventType>(event: Event) {
    events.append(event)
  }

  func getEventsOfType<T: EventType>(type: T.Type) -> [T] {
    return events.flatMap({ $0 as? T })
  }
  func getEventOfType<T: EventType>(type: T.Type) -> T? {
    return getEventsOfType(type).first
  }

  func expectEvent<T: EventType>(type: T.Type, file: String = __FILE__, line: UInt = __LINE__) -> T? {
    expect(self.getEventOfType(type), file: file, line: line).toEventuallyNot(beNil(), description: "expected event of type \(type)")
    return self.getEventOfType(type)
  }

  func waitUntilEvent<T: EventType>(type: T.Type, file: String = __FILE__, line: UInt = __LINE__) -> T? {
    var event: T?
    func getEvent() -> Bool {
      event = getEventOfType(type)
      return (event != nil)
    }
    waitUntil(getEvent(), file: file, line: line)
    return event
  }
}
