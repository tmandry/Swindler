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

  /// The name for the display (usually, the manufacturer and model number).
  lazy var displayName: String = {
    guard let info = infoForCGDisplay(self.directDisplayID, options: kIODisplayOnlyPreferredName) else {
      return "Unknown screen"
    }
    guard let localizedNames = info[kDisplayProductName] as! NSDictionary? as Dictionary?,
              name           = localizedNames.values.first as! NSString? as String? else {
      return "Unnamed screen"
    }
    return name
  }()

  var debugDescription: String {
    return "\"\(displayName)\" \(frame)"
  }

  var frame: CGRect { return nsScreen.frame }
  var applicationFrame: CGRect { return nsScreen.visibleFrame }
}

/// Returns the IODisplay info dictionary for the given displayID.
///
/// -Returns: The info dictionary for the first screen with the same vendor and model number as the
///           specified screen.
func infoForCGDisplay(displayID: CGDirectDisplayID, options: Int) -> [NSObject: AnyObject]? {
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
    guard CFNumberGetValue(cfVendorID, .CFIndexType, &vendorID) &&
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
