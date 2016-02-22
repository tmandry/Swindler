import PromiseKit

// MARK: - Screen

/// A physical display.
public final class Screen: Equatable, CustomDebugStringConvertible {
  internal let delegate: ScreenDelegate
  internal init(delegate: ScreenDelegate) {
    self.delegate = delegate
  }

  public var debugDescription: String { return delegate.debugDescription }

  /// The frame defining the screen boundaries in global coordinates.
  /// -Note: x and y may be negative.
  public var frame: CGRect { return delegate.frame }

  /// The frame defining the screen boundaries in global coordinates, excluding the menu bar and dock.
  public var applicationFrame: CGRect { return delegate.applicationFrame }
}
public func ==(lhs: Screen, rhs: Screen) -> Bool {
  return lhs.delegate.equalTo(rhs.delegate)
}

protocol ScreenDelegate: class, CustomDebugStringConvertible {
  var frame: CGRect { get }
  var applicationFrame: CGRect { get }

  func equalTo(other: ScreenDelegate) -> Bool
}

// MARK: - OSXScreenDelegate

protocol NSScreenType {
  var frame: CGRect { get }
  var visibleFrame: CGRect { get }
  var deviceDescription: [String: AnyObject] { get }

  var displayName: String { get }
}
extension NSScreen: NSScreenType {
  /// The name for the display (usually, the manufacturer and model number).
  /// -Note: This is expensive to get, and should be cached in a stored property.
  var displayName: String {
    guard let info = infoForCGDisplay(numberForScreen(self as NSScreen), options: kIODisplayOnlyPreferredName) else {
      return "Unknown screen"
    }
    guard let localizedNames = info[kDisplayProductName] as! NSDictionary? as Dictionary?,
      name           = localizedNames.values.first as! NSString? as String? else {
        return "Unnamed screen"
    }
    return name
  }
}

private let kNSScreenNumber = "NSScreenNumber"

final class OSXScreenDelegate<NSScreenT: NSScreenType>: ScreenDelegate {
  private let nsScreen: NSScreenT

  // This ID is guaranteed to stay the same for any given display. NSScreen equality checks can fail
  // if the display switches graphics cards.
  private let directDisplayID: CGDirectDisplayID

  init(nsScreen: NSScreenT) {
    self.nsScreen = nsScreen
    self.frame = nsScreen.frame
    self.directDisplayID = numberForScreen(nsScreen)
  }

  func equalTo(other: ScreenDelegate) -> Bool {
    guard let other = other as? OSXScreenDelegate else {
      return false
    }
    return other.directDisplayID == self.directDisplayID
  }

  lazy var displayName: String = { return self.nsScreen.displayName }()

  var debugDescription: String {
    return "\"\(displayName)\" \(frame)"
  }

  // The frame won't change during the delegate's lifetime because it gets recreated every time there
  // is a screen configuration change.
  let frame: CGRect

  var applicationFrame: CGRect { return nsScreen.visibleFrame }
}

extension OSXScreenDelegate {
  static func handleScreenChange(
    newScreens nsScreens: [NSScreenT], oldScreens: [OSXScreenDelegate], state: State
  ) -> ([OSXScreenDelegate], ScreenLayoutChangedEvent) {
    // Make a new screen delegate for every screen, because NSScreen objects can become stale.
    var newScreens: [OSXScreenDelegate] = []
    nsScreens.forEach{ s in newScreens.append(OSXScreenDelegate(nsScreen: s)) }

    let oldIds = Set(oldScreens.map{ $0.directDisplayID })
    let newScreensById = newScreens
      .reduce([CGDirectDisplayID: OSXScreenDelegate<NSScreenT>]()) { (var dict, screen) in
        dict[screen.directDisplayID] = screen
        return dict
      }
    let newIds = Set(newScreens.map{ $0.directDisplayID })

    let addedScreens = newScreens.lazy
      .filter{ !oldIds.contains($0.directDisplayID) }
    let oldScreenNewScreens = oldScreens.lazy
      .map   {  ($0, newScreensById[$0.directDisplayID]) }
    let removedScreens = oldScreenNewScreens
      .filter{ (oldScreen, newScreen) in newScreen == nil }
      .map   { (oldScreen, newScreen) in oldScreen }

    let remainingScreens = oldScreenNewScreens
      .filter{ (oldScreen, newScreen) in newScreen != nil }
    let resizedScreens = remainingScreens
      .filter{ $0.frame != $1!.frame }
      .map   { (oldScreen, newScreen) in newScreen! }
    let unchangedScreens = remainingScreens
      .filter{ $0.frame == $1!.frame }
      .map   { (oldScreen, newScreen) in newScreen! }

    func wrapInScreen(delegate: OSXScreenDelegate<NSScreenT>) -> Screen { return Screen(delegate: delegate) }

    let removedScreensArr = Array(removedScreens)
    let rs: [Screen] = removedScreensArr.map{ Screen(delegate: $0) }
    let event = ScreenLayoutChangedEvent(
      external: false,
      addedScreens: Array(addedScreens).map(wrapInScreen),
      removedScreens: rs,
      resizedScreens: Array(resizedScreens).map(wrapInScreen),
      unchangedScreens: Array(unchangedScreens).map(wrapInScreen)
    )
    return (newScreens, event)
  }
}

private func numberForScreen<NSScreenT: NSScreenType>(nsScreen: NSScreenT) -> CGDirectDisplayID {
  // Get the direct display ID. This is documented to always exist.
  let screenNumber = nsScreen.deviceDescription[kNSScreenNumber]!
  return CGDirectDisplayID((screenNumber as! NSNumber).integerValue)
}

/// Returns the IODisplay info dictionary for the given displayID.
///
/// -Returns: The info dictionary for the first screen with the same vendor and model number as the
///           specified screen.
private func infoForCGDisplay(displayID: CGDirectDisplayID, options: Int) -> [NSObject: AnyObject]? {
  var iter: io_iterator_t = 0

  // Initialize iterator.
  let services = IOServiceMatching("IODisplayConnect")
  let err = IOServiceGetMatchingServices(kIOMasterPortDefault, services, &iter)
  guard err == KERN_SUCCESS else {
    log.warn("Could not find services for IODisplayConnect, error code \(err)")
    return nil
  }

  // Loop through all screens, looking for a vendor and model ID match.
  for var service = IOIteratorNext(iter); service != 0; service = IOIteratorNext(iter) {
    let info = IODisplayCreateInfoDictionary(service, IOOptionBits(options)).takeRetainedValue() as Dictionary

    guard let cfVendorID  = info[kDisplayVendorID] as! CFNumber?,
              cfProductID = info[kDisplayProductID] as! CFNumber? else {
      log.warn("Missing vendor or product ID encountered when looping through screens")
      continue
    }

    var vendorID: CFIndex = 0, productID: CFIndex = 0
    guard CFNumberGetValue(cfVendorID,  .CFIndexType, &vendorID) &&
          CFNumberGetValue(cfProductID, .CFIndexType, &productID) else {
      log.warn("Unexpected failure unwrapping vendor or product ID while looping through screens")
      continue
    }

    if UInt32(vendorID) == CGDisplayVendorNumber(displayID) &&
       UInt32(productID) == CGDisplayModelNumber(displayID) {
      return info
    }
  }

  return nil
}
