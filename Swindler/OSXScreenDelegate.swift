import PromiseKit

private let kNSScreenNumber = "NSScreenNumber"

final class OSXScreenDelegate: ScreenDelegate {
  private let nsScreen: NSScreen

  // This ID is guaranteed to stay the same for any given display. NSScreen equality checks can fail
  // if the display switches graphics cards.
  private let directDisplayID: CGDirectDisplayID

  init(nsScreen: NSScreen) {
    self.nsScreen = nsScreen

    // Get the direct display ID. This is documented to always exist.
    let screenNumber = nsScreen.deviceDescription[kNSScreenNumber]!
    self.directDisplayID = CGDirectDisplayID((screenNumber as! NSNumber).integerValue)
  }

  func equalTo(other: ScreenDelegate) -> Bool {
    guard let other = other as? OSXScreenDelegate else {
      return false
    }
    return other.directDisplayID == self.directDisplayID
  }

  var debugDescription: String {
    return nsScreen.debugDescription
  }

  var frame: CGRect { return nsScreen.frame }
  var applicationFrame: CGRect { return nsScreen.visibleFrame }
}
