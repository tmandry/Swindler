import Cocoa

let applicationDelegate = AppDelegate()
let application = NSApplication.shared()
application.setActivationPolicy(NSApplicationActivationPolicy.accessory)
application.delegate = applicationDelegate
application.run()
