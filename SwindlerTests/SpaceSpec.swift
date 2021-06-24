import Cocoa
import Quick
import Nimble

@testable import Swindler

class OSXSpaceObserverSpec: QuickSpec {
    override func spec() {
        var notifier: EventNotifier!
        var screen1: OSXScreenDelegate<StubNSScreen>!
        var screen2: OSXScreenDelegate<StubNSScreen>!
        var ssd: FakeSystemScreenDelegate!
        var sst: FakeSystemSpaceTracker!
        var observer: OSXSpaceObserver!
        var visibleIds: [Int]?
        beforeEach {
            notifier = EventNotifier()
            screen1 = OSXScreenDelegate(nsScreen: StubNSScreen(1))
            screen2 = OSXScreenDelegate(nsScreen: StubNSScreen(2))
            ssd = FakeSystemScreenDelegate(screens: [screen1, screen2])
            sst = FakeSystemSpaceTracker()
            observer = OSXSpaceObserver(notifier, ssd, sst)
            notifier.on { (event: SpaceWillChangeEvent) in visibleIds = event.ids }
            observer.emitSpaceWillChangeEvent()
        }

        describe("spaces") {
            it("work") {
                expect(sst.trackersMade).to(haveCount(2))
                expect(visibleIds).to(contain(1, 2))
                sst.visible = [1]
                sst.spaceChangeHandler?()
                expect(sst.trackersMade).to(haveCount(3))
                expect(visibleIds) == [1, 3]
                expect(sst.trackersMade.last?.screen?.equalTo(screen2)) == true

                // Simulate spaces being combined
                sst.visible = [1, 3, 2]
                sst.spaceChangeHandler?()
                expect(sst.trackersMade).to(haveCount(3))
                expect(visibleIds) == [1, 2]
            }
        }
    }
}
