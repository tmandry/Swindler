import Cocoa
import Quick
import Nimble

@testable import Swindler

class StubSystemSpaceTracker: SystemSpaceTracker {
    init() {}

    var spaceChangeHandler: Optional<() -> ()> = nil
    func onSpaceChanged(_ handler: @escaping () -> ()) {
        spaceChangeHandler = handler
    }

    var trackersMade: [StubSpaceTracker] = []
    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker {
        let tracker = StubSpaceTracker(screen, id: trackersMade.count + 1)
        trackersMade.append(tracker)
        visible.append(tracker.id)
        return tracker
    }

    var visible: [Int] = []
    func visibleIds() -> [Int] { visible }
}

class StubSpaceTracker: SpaceTracker {
    var screen: ScreenDelegate?
    var id: Int
    init(_ screen: ScreenDelegate?, id: Int) {
        self.screen = screen
        self.id = id
    }
    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate? { screen }
}

class OSXSpaceObserverSpec: QuickSpec {
    override func spec() {
        var notifier: EventNotifier!
        var screen1: OSXScreenDelegate<StubNSScreen>!
        var screen2: OSXScreenDelegate<StubNSScreen>!
        var ssd: FakeSystemScreenDelegate!
        var sst: StubSystemSpaceTracker!
        var observer: OSXSpaceObserver!
        var visibleIds: [Int]?
        beforeEach {
            notifier = EventNotifier()
            screen1 = OSXScreenDelegate(nsScreen: StubNSScreen(1))
            screen2 = OSXScreenDelegate(nsScreen: StubNSScreen(2))
            ssd = FakeSystemScreenDelegate(screens: [screen1, screen2])
            sst = StubSystemSpaceTracker()
            observer = OSXSpaceObserver(notifier, ssd, sst)
            notifier.on { (event: SpaceWillChangeEvent) in visibleIds = event.id }
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
