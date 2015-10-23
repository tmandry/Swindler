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
    swindler.onEvent(.WindowCreated) { event in
      var event = event as! WindowEvent
      print("new window: \(event.window)")

      dispatchAfter(4.0) {
        event.window.pos = CGPoint(x: 200, y: 200)
        event.window.size = CGSize(width: 30, height: 30)
      }
    }
    swindler.onWindowPropertyChanged(.Pos) { event in
      let event = event as! WindowPosChangedEvent
      print("Pos changed from \(event.oldVal) to \(event.newVal), external: \(event.external)")
    }
    swindler.onWindowPropertyChanged(.Size) { event in
      let event = event as! WindowSizeChangedEvent
      print("Size changed from \(event.oldVal) to \(event.newVal), external: \(event.external)")
    }
    swindler.onEvent(.WindowDestroyed) { event in
      let event = event as! WindowEvent
      print("window destroyed: \(event.window)")
    }
  }

  func applicationWillTerminate(aNotification: NSNotification) {
    // Insert code here to tear down your application
  }

}
