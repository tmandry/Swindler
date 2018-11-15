import Nimble

@testable import Swindler

class TestNotifier: EventNotifier {
    var events: [EventType] = []

    override func notify<Event: EventType>(_ event: Event) {
        events.append(event)
        super.notify(event)
    }

    func getEventsOfType<T: EventType>(_ type: T.Type) -> [T] {
        return events.compactMap({ $0 as? T })
    }
    func getEventOfType<T: EventType>(_ type: T.Type) -> T? {
        return getEventsOfType(type).first
    }

    @discardableResult
    func expectEvent<T: EventType>(_ type: T.Type, file: String = #file, line: UInt = #line) -> T? {
        expect(self.getEventOfType(type), file: file, line: line)
            .toEventuallyNot(beNil(), description: "expected event of type \(type)")
        return getEventOfType(type)
    }

    @discardableResult
    func waitUntilEvent<T: EventType>(_ type: T.Type, file: String = #file, line: UInt = #line)
    -> T? {
        var event: T?
        func getEvent() -> Bool {
            event = getEventOfType(type)
            return (event != nil)
        }
        waitUntil(getEvent(), file: file, line: line)
        return event
    }
}
