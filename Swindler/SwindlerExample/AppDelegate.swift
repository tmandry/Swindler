//
//  AppDelegate.swift
//  SwindlerExample
//
//  Created by Tyler Mandry on 10/20/15.
//  Copyright © 2015 Tyler Mandry. All rights reserved.
//

import Cocoa
import Swindler

func dispatchAfter(delay: NSTimeInterval, block: dispatch_block_t) {
  let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC)))
  dispatch_after(time, dispatch_get_main_queue(), block)
}

class AppDelegate: NSObject, NSApplicationDelegate {

  var swindler: Swindler.State!

  func applicationDidFinishLaunching(aNotification: NSNotification) {
    swindler = Swindler.state
    swindler.on { (event: WindowCreatedEvent) in
      var window = event.window
      print("new window: \(window)")

      dispatchAfter(4.0) {
        window.pos = CGPoint(x: 200, y: 200)
        window.size = CGSize(width: 30, height: 30)
      }
    }
    swindler.on { (event: WindowPosChangedEvent) in
      print("Pos changed from \(event.oldVal) to \(event.newVal), external: \(event.external)")
    }
    swindler.on { (event: WindowSizeChangedEvent) in
      print("Size changed from \(event.oldVal) to \(event.newVal), external: \(event.external)")
    }
    swindler.on { (event: WindowDestroyedEvent) in
      print("window destroyed: \(event.window)")
    }
  }

  func applicationWillTerminate(aNotification: NSNotification) {
    // Insert code here to tear down your application
  }

}
