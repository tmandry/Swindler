import Cocoa

let applicationDelegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(NSApplication.ActivationPolicy.accessory)
application.delegate = applicationDelegate
application.run()
