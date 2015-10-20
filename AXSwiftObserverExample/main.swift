import Cocoa

let applicationDelegate = AppDelegate()
let application = NSApplication.sharedApplication()
application.setActivationPolicy(NSApplicationActivationPolicy.Accessory)
application.delegate = applicationDelegate
application.run()