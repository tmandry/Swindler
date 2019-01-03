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
        return Promise.value(systemValue)
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

        // Set up a frame property on a test AX window.
        var windowElement: TestWindowElement!
        var notifier: TestPropertyNotifier!

        func setUpWithAttributes(_ attrs: [AXSwift.Attribute: Any])
        -> WriteableProperty<OfType<CGRect>> {
            windowElement = TestWindowElement(forApp: TestApplicationElement())
            for (attr, value) in attrs {
                windowElement.attrs[attr] = value
            }
            let initPromise = Promise<[AXSwift.Attribute: Any]>.value(attrs)
            notifier = TestPropertyNotifier()
            let delegate = AXPropertyDelegate<CGRect, TestWindowElement>(
                windowElement, .frame, initPromise
            )
            return WriteableProperty(
                delegate,
                withEvent: WindowFrameChangedEvent.self,
                receivingObject: Window.self,
                notifier: notifier)
        }

        let firstFrame = CGRect(x: 5, y: 5, width: 20, height: 50)
        let secondFrame = CGRect(x: 100, y: 100, width: 200, height: 500)

        var property: WriteableProperty<OfType<CGRect>>!
        func finishPropertyInit() {
            waitUntil { done in
                property.initialized.done {
                    done()
                }.cauterize()
            }
        }

        beforeEach {
            property = setUpWithAttributes([.frame: firstFrame])
            finishPropertyInit()
        }

        describe("initialization") {

            it("doesn't leak") {
                weak var property = setUpWithAttributes([.frame: firstFrame])
                waitUntil { done in
                    if let prop = property {
                        prop.initialized.done { done() }.cauterize()
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
                    return property.initialized.ensure {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

            }

            context("when an optional attribute is missing") {

                var optProperty: WriteableProperty<OfOptionalType<CGRect>>!
                beforeEach {
                    let initPromise = Promise<[AXSwift.Attribute: Any]>.value([:])
                    let delegate = AXPropertyDelegate<CGRect, TestWindowElement>(
                        windowElement, .frame, initPromise
                    )
                    optProperty = WriteableProperty(delegate, notifier: notifier)
                }

                it("reports no error") { () -> Promise<Void> in
                    return optProperty.initialized
                }

                it("does not mark the object as invalid") { () -> Promise<Void> in
                    return optProperty.initialized.done {
                        expect(notifier.stillValid).to(beTrue())
                    }
                }

            }
        }

        describe("refresh") {
            context("when the attribute has changed") {
                beforeEach {
                    windowElement.attrs[.frame] = secondFrame
                }

                it("resolves to the new value") {
                    property.refresh().done { newValue in
                        expect(newValue).to(equal(secondFrame))
                    }
                }

                it("emits a ChangedEvent of the correct type") {
                    property.refresh().done { _ in
                        expect(notifier.events.count).to(equal(1))
                        if let event = notifier.events.first {
                            expect(event.type == WindowFrameChangedEvent.self).to(beTrue())
                        }
                    }
                }

                it("includes the correct oldValue and newValue in the event") {
                    property.refresh().done { _ in
                        if let event = notifier.events.first {
                            expect(event.oldValue as? CGRect).to(equal(firstFrame))
                            expect(event.newValue as? CGRect).to(equal(secondFrame))
                        }
                    }
                }

                it("marks the event as external") {
                    property.refresh().done { _ in
                        if let event = notifier.events.first {
                            expect(event.external).to(beTrue())
                        }
                    }
                }

            }

            context("when the attribute has not changed") {

                it("resolves to the correct value") {
                    property.refresh().done { newValue in
                        expect(newValue).to(equal(firstFrame))
                    }
                }

                it("does not emit a ChangedEvent") {
                    property.refresh().done { _ in
                        expect(notifier.events.count).to(equal(0))
                    }
                }

            }

            context("when a non-optional attribute is missing") {

                it("reports an error") { () -> Promise<Void> in
                    windowElement.attrs.removeValue(forKey: .frame)
                    let expectedError = PropertyError.invalidObject(
                        cause: PropertyError.missingValue
                    )
                    return expectToFail(property.refresh(), with: expectedError)
                }

                it("marks the object as invalid", failOnError: false) { () -> Promise<Void> in
                    windowElement.attrs.removeValue(forKey: .frame)
                    return property.refresh().asVoid().ensure {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

            }

            context("when an optional attribute is missing") {
                var optProperty: WriteableProperty<OfOptionalType<CGRect>>!
                beforeEach {
                    let initPromise = Promise<[AXSwift.Attribute: Any]>.value([.frame: firstFrame])
                    let delegate = AXPropertyDelegate<CGRect, TestWindowElement>(
                        windowElement, .frame, initPromise
                    )
                    optProperty = WriteableProperty(delegate, notifier: notifier)
                    waitUntil { done in
                        optProperty.initialized.done { done() }.cauterize()
                    }
                }

                it("reports no error") { () -> Promise<Void> in
                    windowElement.attrs.removeValue(forKey: .frame)
                    return optProperty.refresh().asVoid()
                }

                it("does not mark the object as invalid") { () -> Promise<Void> in
                    return optProperty.initialized.done {
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
                    property.refresh().ensure {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

                it("still allows reading", failOnError: false) {
                    property.refresh().ensure {
                        expect(property.value).to(equal(firstFrame))
                    }
                }

                it("does not emit a ChangedEvent", failOnError: false) {
                    property.refresh().ensure {
                        expect(notifier.events.count).to(equal(0))
                    }
                }

            }

            context("when called before the property is initialized") {

                var initPromiseSeal: Resolver<[AXSwift.Attribute: Any]>!
                beforeEach {
                    let (initPromise, seal) = Promise<[AXSwift.Attribute: Any]>.pending()
                    initPromiseSeal = seal
                    let delegate = AXPropertyDelegate<CGRect, TestWindowElement>(
                        windowElement, .frame, initPromise
                    )
                    property = WriteableProperty(
                        delegate,
                        withEvent: WindowFrameChangedEvent.self,
                        receivingObject: Window.self,
                        notifier: notifier)
                }

                it("doesn't crash") { () -> Void in
                    property.refresh()
                }

                it("refreshes the property value after initialization is complete") {
                    () -> Promise<Void> in

                    let promise = property.refresh().done { newValue in
                        expect(newValue).to(equal(secondFrame))
                    }
                    windowElement.attrs[.frame] = secondFrame
                    initPromiseSeal.fulfill([.frame: firstFrame])
                    return promise
                }

            }
        }

        describe("set") {

            it("eventually updates the property value") {
                property.set(secondFrame).cauterize()
                expect(property.value).toEventually(equal(secondFrame))
            }

            it("resolves to the new value") {
                property.set(secondFrame).done { newValue in
                    expect(newValue).to(equal(secondFrame))
                }
            }

            it("sets the attribute on the UIElement") {
                property.set(secondFrame).done { _ in
                    expect(windowElement.attrs[.frame]! is CGRect).to(beTrue())
                    expect(windowElement.attrs[.frame]! as? CGRect).to(equal(secondFrame))
                }
            }

            it("emits a ChangedEvent of the correct type") {
                property.set(secondFrame).done { _ in
                    expect(notifier.events.count).to(equal(1))
                    if let event = notifier.events.first {
                        expect(event.type == WindowFrameChangedEvent.self).to(beTrue())
                    }
                }
            }

            it("includes the correct oldValue and newValue in the event") {
                property.set(secondFrame).done { _ in
                    if let event = notifier.events.first {
                        expect(event.oldValue as? CGRect).to(equal(firstFrame))
                        expect(event.newValue as? CGRect).to(equal(secondFrame))
                    }
                }
            }

            it("marks the event as internal") {
                property.set(secondFrame).done { _ in
                    if let event = notifier.events.first {
                        expect(event.external).to(beFalse())
                    }
                }
            }

            it("updates the property value before emitting the event") {
                property.set(secondFrame).done { _ in
                    expect(property.value).to(equal(secondFrame))
                }
            }

            context("when the new value is the same as the old value") {
                it("does not emit a ChangedEvent") {
                    property.set(firstFrame).done { _ in
                        expect(notifier.events.count).to(equal(0))
                    }
                }
            }

            context("when the UIElement") {
                class MyPropertyDelegate: TestPropertyDelegate<CGRect> {
                    let setTo: CGRect?
                    init(value: CGRect, setTo: CGRect) {
                        self.setTo = setTo
                        super.init(value: value)
                    }
                    override func writeValue(_ newValue: CGRect?) throws {
                        systemValue = setTo
                    }
                }

                var delegate: MyPropertyDelegate!
                func initPropertyWithDelegate(_ delegate_: MyPropertyDelegate) {
                    delegate = delegate_
                    property = WriteableProperty(
                            delegate,
                            withEvent: WindowFrameChangedEvent.self,
                            receivingObject: Window.self,
                            notifier: notifier)
                    finishPropertyInit()
                }

                context("does not change its value") {
                    beforeEach {
                        initPropertyWithDelegate(
                            MyPropertyDelegate(value: firstFrame, setTo: firstFrame)
                        )
                    }

                    it("reports the actual value") {
                        property.set(secondFrame).done { newValue in
                            expect(newValue).to(equal(firstFrame))
                            expect(property.value).to(equal(firstFrame))
                        }
                    }

                    it("does not emit a ChangedEvent") {
                        property.set(secondFrame).done { _ in
                            expect(notifier.events.count).to(equal(0))
                        }
                    }

                }

                context("changes to a different value than the one requested") {
                    let resultingFrame = CGRect(x: 50, y: 75, width: 300, height: 400)
                    beforeEach {
                        initPropertyWithDelegate(
                            MyPropertyDelegate(value: firstFrame, setTo: resultingFrame)
                        )
                    }

                    it("reports the actual value") {
                        return property.set(secondFrame).done { newValue in
                            expect(newValue).to(equal(resultingFrame))
                            expect(property.value).to(equal(resultingFrame))
                        }
                    }

                    it("emits a ChangedEvent with the actual value") {
                        return property.set(secondFrame).done { _ in
                            expect(notifier.events.count).to(equal(1))
                            if let event = notifier.events.first {
                                expect(event.oldValue as? CGRect).to(equal(firstFrame))
                                expect(event.newValue as? CGRect).to(equal(resultingFrame))
                            }
                        }
                    }

                    it("marks the event as external") {
                        return property.set(secondFrame).done { _ in
                            if let event = notifier.events.first {
                                expect(event.external).to(beTrue())
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

                var delegate: MyPropertyDelegate<CGRect>!
                var property: WriteableProperty<OfType<CGRect>>!
                beforeEach {
                    delegate = MyPropertyDelegate(value: firstFrame, onWrite: {
                        property.refresh()
                    })
                    property = WriteableProperty(
                        delegate,
                        withEvent: WindowFrameChangedEvent.self,
                        receivingObject: Window.self,
                        notifier: notifier)
                    finishPropertyInit()
                }

                it("only emits one event") {
                    return property.set(secondFrame).done { _ in
                        expect(notifier.events.count).to(equal(1))
                    }
                }

                it("marks the event as internal") {
                    return property.set(secondFrame).done { _ in
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
                    property.set(secondFrame).ensure {
                        expect(notifier.stillValid).to(beFalse())
                    }
                }

                it("does not update the property value, but still allows reading",
                   failOnError: false) {
                    property.set(secondFrame).ensure {
                        expect(property.value).to(equal(firstFrame))
                    }
                }

                it("does not emit a ChangedEvent", failOnError: false) {
                    property.set(secondFrame).ensure {
                        expect(notifier.events.count).to(equal(0))
                    }
                }

            }
        }

    }
}
