import Quick
import Nimble

@testable import Swindler
import AXSwift
import PromiseKit

private class TestPropertyDelegate<T: Equatable>: PropertyDelegate {
    var systemValue: T?

    init(value: T?) {
        systemValue = value
    }
    func initialize() -> Promise<T?> {
        return Promise(value: systemValue)
    }
    func readValue() throws -> T? {
        return systemValue
    }
    func writeValue(_ newValue: T) throws {
        systemValue = newValue
    }
}

class TestPropertyNotifier: PropertyNotifier {
    typealias Object = Window

    // We must make our own struct because we don't have a window.
    struct Event {
        var type: Any.Type
        var external: Bool
        var oldValue: Any
        var newValue: Any
    }
    var events: [Event] = []
    var stillValid = true

    func notify<EventT: PropertyEventType>(
        _ event: EventT.Type,
        external: Bool,
        oldValue: EventT.PropertyType,
        newValue: EventT.PropertyType
    ) where EventT.Object == Window {
        events.append(
            Event(type: event, external: external, oldValue: oldValue, newValue: newValue)
        )
    }
    func notifyInvalid() {
        stillValid = false
    }
}

class PropertySpec: QuickSpec {
    override func spec() {

        // Set up a position property on a test AX window.
        var windowElement: TestWindowElement!
        var notifier: TestPropertyNotifier!

        func setUpWithAttributes(_ attrs: [AXSwift.Attribute: Any])
        -> WriteableProperty<OfType<CGPoint>> {
            windowElement = TestWindowElement(forApp: TestApplicationElement())
            windowElement.attrs = attrs
            let initPromise = Promise<[AXSwift.Attribute: Any]>(value: attrs)
            notifier = TestPropertyNotifier()
            let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(
                windowElement, .position, initPromise
            )
            return WriteableProperty(
                delegate,
                withEvent: WindowPosChangedEvent.self,
                receivingObject: Window.self,
                notifier: notifier)
        }

        let firstPoint = CGPoint(x: 5, y: 5)
        let secondPoint = CGPoint(x: 100, y: 100)

        var property: WriteableProperty<OfType<CGPoint>>!
        func finishPropertyInit() {
            waitUntil { done in
                property.initialized.then {
                    done()
                }.always {}
            }
        }

        beforeEach {
            property = setUpWithAttributes([.position: firstPoint])
            finishPropertyInit()
        }

        describe("initialization") {

            it("doesn't leak") {
                weak var property = setUpWithAttributes([.position: firstPoint])
                waitUntil { done in
                    if let prop = property {
                        prop.initialized.then { done() }.always {}
                    } else {
                        done()
                    }
                }
                expect(property).to(beNil())
            }

            context("when a non-optional attribute is missing") {

                it("reports an error") { () -> Promise<Void> in
                    property = setUpWithAttributes([:])
                    let expectedError = PropertyError.invalidObject(
                        cause: PropertyError.missingValue
                    )
                    return expectToFail(property.initialized, with: expectedError)
                }

                it("marks the object as invalid", failOnError: false) { () -> Promise<Void> in
                    property = setUpWithAttributes([:])
                    return property.initialized.always {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

            }

            context("when an optional attribute is missing") {

                var optProperty: WriteableProperty<OfOptionalType<CGPoint>>!
                beforeEach {
                    let initPromise = Promise<[AXSwift.Attribute: Any]>(value: [:])
                    let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(
                        windowElement, .position, initPromise
                    )
                    optProperty = WriteableProperty(delegate, notifier: notifier)
                }

                it("reports no error") { () -> Promise<Void> in
                    return optProperty.initialized
                }

                it("does not mark the object as invalid") { () -> Promise<Void> in
                    return optProperty.initialized.then {
                        expect(notifier.stillValid).to(beTrue())
                    }
                }

            }
        }

        describe("refresh") {
            context("when the attribute has changed") {
                beforeEach {
                    windowElement.attrs[.position] = secondPoint
                }

                it("resolves to the new value") {
                    property.refresh().then { newValue in
                        expect(newValue).to(equal(secondPoint))
                    }
                }

                it("emits a ChangedEvent of the correct type") {
                    property.refresh().then { _ -> Void in
                        expect(notifier.events.count).to(equal(1))
                        if let event = notifier.events.first {
                            expect(event.type == WindowPosChangedEvent.self).to(beTrue())
                        }
                    }
                }

                it("includes the correct oldValue and newValue in the event") {
                    property.refresh().then { _ -> Void in
                        if let event = notifier.events.first {
                            expect(event.oldValue as? CGPoint).to(equal(firstPoint))
                            expect(event.newValue as? CGPoint).to(equal(secondPoint))
                        }
                    }
                }

                it("marks the event as external") {
                    property.refresh().then { _ -> Void in
                        if let event = notifier.events.first {
                            expect(event.external).to(beTrue())
                        }
                    }
                }

            }

            context("when the attribute has not changed") {

                it("resolves to the correct value") {
                    property.refresh().then { newValue in
                        expect(newValue).to(equal(firstPoint))
                    }
                }

                it("does not emit a ChangedEvent") {
                    property.refresh().then { _ -> Void in
                        expect(notifier.events.count).to(equal(0))
                    }
                }

            }

            context("when a non-optional attribute is missing") {

                it("reports an error") { () -> Promise<Void> in
                    windowElement.attrs[.position] = nil
                    let expectedError = PropertyError.invalidObject(
                        cause: PropertyError.missingValue
                    )
                    return expectToFail(property.refresh(), with: expectedError)
                }

                it("marks the object as invalid", failOnError: false) { () -> Promise<Void> in
                    windowElement.attrs[.position] = nil
                    return property.refresh().asVoid().always {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

            }

            context("when an optional attribute is missing") {
                var optProperty: WriteableProperty<OfOptionalType<CGPoint>>!
                beforeEach {
                    let initPromise = Promise<[AXSwift.Attribute: Any]>(
                        value: [.position: firstPoint]
                    )
                    let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(
                        windowElement, .position, initPromise
                    )
                    optProperty = WriteableProperty(delegate, notifier: notifier)
                    waitUntil { done in
                        optProperty.initialized.then { done() }.always {}
                    }
                }

                it("reports no error") { () -> Promise<Void> in
                    windowElement.attrs[.position] = nil
                    return optProperty.refresh().asVoid()
                }

                it("does not mark the object as invalid") { () -> Promise<Void> in
                    return optProperty.initialized.then {
                        expect(notifier.stillValid).to(beTrue())
                    }
                }

            }

            context("when the window element becomes invalid") {
                beforeEach {
                    windowElement.throwInvalid = true
                }

                it("returns an error") {
                    expectToFail(property.refresh(), with: PropertyError.invalidObject(
                        cause: AXError.invalidUIElement)
                    )
                }

                it("calls notifier.notifyInvalid()", failOnError: false) {
                    property.refresh().always {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

                it("still allows reading", failOnError: false) {
                    property.refresh().always {
                        expect(property.value).to(equal(firstPoint))
                    }
                }

                it("does not emit a ChangedEvent", failOnError: false) {
                    property.refresh().always {
                        expect(notifier.events.count).to(equal(0))
                    }
                }

            }

            context("when called before the property is initialized") {

                var fulfillInitPromise: (([AXSwift.Attribute: Any]) -> Void)!
                beforeEach {
                    let (initPromise, fulfill, _) = Promise<[AXSwift.Attribute: Any]>.pending()
                    fulfillInitPromise = fulfill
                    let delegate = AXPropertyDelegate<CGPoint, TestWindowElement>(
                        windowElement, .position, initPromise
                    )
                    property = WriteableProperty(
                        delegate,
                        withEvent: WindowPosChangedEvent.self,
                        receivingObject: Window.self,
                        notifier: notifier)
                }

                it("doesn't crash") { () -> Void in
                    property.refresh()
                }

                it("refreshes the property value after initialization is complete") {
                    () -> Promise<Void> in

                    let promise = property.refresh().then { newValue -> Void in
                        expect(newValue).to(equal(secondPoint))
                    }
                    windowElement.attrs[.position] = secondPoint
                    fulfillInitPromise([.position: firstPoint])
                    return promise
                }

            }
        }

        describe("set") {

            it("eventually updates the property value") {
                property.set(secondPoint).always {}
                expect(property.value).toEventually(equal(secondPoint))
            }

            it("resolves to the new value") {
                property.set(secondPoint).then { newValue in
                    expect(newValue).to(equal(secondPoint))
                }
            }

            it("sets the attribute on the UIElement") {
                property.set(secondPoint).then { _ -> Void in
                    expect(windowElement.attrs[.position]! is CGPoint).to(beTrue())
                    expect(windowElement.attrs[.position]! as? CGPoint).to(equal(secondPoint))
                }
            }

            it("emits a ChangedEvent of the correct type") {
                property.set(secondPoint).then { _ -> Void in
                    expect(notifier.events.count).to(equal(1))
                    if let event = notifier.events.first {
                        expect(event.type == WindowPosChangedEvent.self).to(beTrue())
                    }
                }
            }

            it("includes the correct oldValue and newValue in the event") {
                property.set(secondPoint).then { _ -> Void in
                    if let event = notifier.events.first {
                        expect(event.oldValue as? CGPoint).to(equal(firstPoint))
                        expect(event.newValue as? CGPoint).to(equal(secondPoint))
                    }
                }
            }

            it("marks the event as internal") {
                property.set(secondPoint).then { _ -> Void in
                    if let event = notifier.events.first {
                        expect(event.external).to(beFalse())
                    }
                }
            }

            it("updates the property value before emitting the event") {
                property.set(secondPoint).then { _ -> Void in
                    expect(property.value).to(equal(secondPoint))
                }
            }

            context("when the new value is the same as the old value") {
                it("does not emit a ChangedEvent") {
                    property.set(firstPoint).then { _ in
                        expect(notifier.events.count).to(equal(0))
                    }
                }
            }

            context("when the UIElement") {
                class MyPropertyDelegate: TestPropertyDelegate<CGPoint> {
                    let setTo: CGPoint?
                    init(value: CGPoint, setTo: CGPoint) {
                        self.setTo = setTo
                        super.init(value: value)
                    }
                    override func writeValue(_ newValue: CGPoint?) throws {
                        systemValue = setTo
                    }
                }

                var delegate: MyPropertyDelegate!
                func initPropertyWithDelegate(_ delegate_: MyPropertyDelegate) {
                    delegate = delegate_
                    property = WriteableProperty(
                            delegate,
                            withEvent: WindowPosChangedEvent.self,
                            receivingObject: Window.self,
                            notifier: notifier)
                    finishPropertyInit()
                }

                context("does not change its value") {
                    beforeEach {
                        initPropertyWithDelegate(
                            MyPropertyDelegate(value: firstPoint, setTo: firstPoint)
                        )
                    }

                    it("reports the actual value") {
                        property.set(secondPoint).then { newValue -> Void in
                            expect(newValue).to(equal(firstPoint))
                            expect(property.value).to(equal(firstPoint))
                        }
                    }

                    it("does not emit a ChangedEvent") {
                        property.set(secondPoint).then { _ in
                            expect(notifier.events.count).to(equal(0))
                        }
                    }

                }

                context("changes to a different value than the one requested") {
                    let resultingPoint = CGPoint(x: 50, y: 75)
                    beforeEach {
                        initPropertyWithDelegate(
                            MyPropertyDelegate(value: firstPoint, setTo: resultingPoint)
                        )
                    }

                    it("reports the actual value") {
                        return property.set(secondPoint).then { newValue -> Void in
                            expect(newValue).to(equal(resultingPoint))
                            expect(property.value).to(equal(resultingPoint))
                        }
                    }

                    it("emits a ChangedEvent with the actual value") {
                        return property.set(secondPoint).then { _ -> Void in
                            expect(notifier.events.count).to(equal(1))
                            if let event = notifier.events.first {
                                expect(event.oldValue as? CGPoint).to(equal(firstPoint))
                                expect(event.newValue as? CGPoint).to(equal(resultingPoint))
                            }
                        }
                    }

                    it("marks the event as internal") {
                        return property.set(secondPoint).then { _ -> Void in
                            if let event = notifier.events.first {
                                expect(event.external).to(beFalse())
                            }
                        }
                    }

                }
            }

            // This happens, for instance, if the system notification for the change is received
            // first.
            context("when a refresh is requested before reading back the new value") {
                class MyPropertyDelegate<T: Equatable>: TestPropertyDelegate<T> {
                    let onWrite: () -> Void
                    init(value: T, onWrite: @escaping () -> Void) {
                        self.onWrite = onWrite
                        super.init(value: value)
                    }
                    override func writeValue(_ newValue: T?) throws {
                        systemValue = newValue
                        onWrite()
                    }
                }

                var delegate: MyPropertyDelegate<CGPoint>!
                var property: WriteableProperty<OfType<CGPoint>>!
                beforeEach {
                    delegate = MyPropertyDelegate(value: firstPoint, onWrite: {
                        property.refresh()
                    })
                    property = WriteableProperty(
                        delegate,
                        withEvent: WindowPosChangedEvent.self,
                        receivingObject: Window.self,
                        notifier: notifier)
                    finishPropertyInit()
                }

                it("only emits one event") {
                    return property.set(secondPoint).then { _ -> Void in
                        expect(notifier.events.count).to(equal(1))
                    }
                }

                it("marks the event as internal") {
                    return property.set(secondPoint).then { _ -> Void in
                        if let event = notifier.events.first {
                            expect(event.external).to(beFalse())
                        }
                    }
                }

            }

            context("when the window element becomes invalid") {
                beforeEach {
                    windowElement.throwInvalid = true
                }

                it("returns an error") {
                    expectToFail(property.refresh(), with: PropertyError.invalidObject(
                        cause: AXError.invalidUIElement
                    ))
                }

                it("calls notifier.notifyInvalid()", failOnError: false) {
                    property.set(secondPoint).always {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

                it("does not update the property value, but still allows reading",
                   failOnError: false) {
                    property.set(secondPoint).always {
                        expect(property.value).to(equal(firstPoint))
                    }
                }

                it("does not emit a ChangedEvent", failOnError: false) {
                    property.set(secondPoint).always {
                        expect(notifier.events.count).to(equal(0))
                    }
                }

            }
        }

    }
}
