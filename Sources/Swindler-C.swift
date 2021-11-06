//
//  Swindler-C.swift
//  Swindler
//
//  Created by Jeremy on 9/15/21.
//

import AXSwift
import Cocoa
import PromiseKit

/// Swift --> C type mapping
public typealias SWStateRef = UnsafeMutableRawPointer
public typealias SWWindowRef = UnsafeMutableRawPointer
public typealias SWApplicationRef = UnsafeMutableRawPointer
public typealias SWScreenRef = UnsafeMutableRawPointer
public typealias SWStateCreatedCallback = @convention(c) (SWStateRef) -> Void
public typealias SWCompletionBlock = () -> Void

/* ---- State ---- */
@_cdecl("SWStateInitialize")
public func SWStateInitialize() -> UnsafeMutableRawPointer? {
    AXSwift.checkIsProcessTrusted(prompt: true)
    
    let tryState: State?
    let p = Swindler.initialize()
    
    do {
        tryState = try hang(p)
    } catch {
        tryState = nil
    }
    
    if let state = tryState {
        let retained = Unmanaged.passRetained(state).autorelease().toOpaque()
        return UnsafeMutableRawPointer(retained)
    }
    
    return nil
}

@_cdecl("SWStateInitializeAsync")
public func SwindlerCreateAsync(_ cb: @escaping SWStateCreatedCallback) -> Void {
    AXSwift.checkIsProcessTrusted(prompt: true)
    
    Swindler.initialize().done { state in
        let retained = Unmanaged.passRetained(state).autorelease().toOpaque()
        let ptr = UnsafeMutableRawPointer(retained)
        if (!Thread.current.isMainThread) {
            DispatchQueue.main.async {
                cb(ptr)
            }
        } else {
            cb(ptr)
        }
    }.catch { error in
        print("Fatal error: failed to initialize Swindler: \(error)")
        exit(1)
    }
}

@_cdecl("SwindlerDestroy")
public func SwindlerDestroy(_ stateRef: OpaquePointer) -> Void {
    _ = stateRef
}

@_cdecl("SWStateGetScreens")
public func SWStateGetScreens(_ stateRef: SWStateRef, outPtr: UnsafeMutablePointer<OpaquePointer>?) -> UInt32 {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    let screens = state.screens
    if let ptr = outPtr {
        screens.copyOutCArray(ptr)
    }
    
    return UInt32(state.screens.count)
}

@_cdecl("SWStateGetMainScreen")
public func SWStateGetMainScreen(_ stateRef: SWStateRef) -> OpaquePointer? {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    if let screen = state.mainScreen {
        let retained = Unmanaged.passUnretained(screen).toOpaque()
        return OpaquePointer(retained)
    }
    
    return nil
}

@_cdecl("SWStateGetRunningApplications")
public func SWStateGetRunningApplications(_ stateRef: SWStateRef, outPtr: UnsafeMutablePointer<OpaquePointer>?) -> UInt32 {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    let runningApplications = state.runningApplications
    if let ptr = outPtr {
        runningApplications.copyOutCArray(ptr)
    }
    return UInt32(state.runningApplications.count)
}

@_cdecl("SWStateGetKnownWindows")
public func SWStateGetKnownWindows(_ stateRef: SWStateRef, outPtr: UnsafeMutablePointer<OpaquePointer>?) -> UInt32 {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    let windows = state.knownWindows
    if let ptr = outPtr {
        windows.copyOutCArray(ptr)
    }
    
    return UInt32(state.knownWindows.count)
}

@_cdecl("SWStateGetFrontmostApplication")
public func SWStateGetFrontmostApplication(_ stateRef: SWStateRef) -> OpaquePointer? {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    if let frontmostApplication = state.frontmostApplication.getValue() {
        let retained = Unmanaged.passUnretained(frontmostApplication).toOpaque()
        return OpaquePointer(retained)
    }
    
    return nil
}

@_cdecl("SWStateSetFrontmostApplication")
public func SWStateSetFrontmostApplication(_ stateRef: SWStateRef, appRef: SWApplicationRef, onComplete: SWCompletionBlock?) {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    _ = state.frontmostApplication.set(app).then { result -> Promise<Void> in
        if let done = onComplete { done() }
        return Promise.value(())
    }
}

/* ---- Screens ---- */
@_cdecl("SWScreenGetFrame")
public func SWScreenGetFrame(_ screenRef: SWScreenRef) -> CGRect {
    let screen = Unmanaged<Screen>.fromOpaque(screenRef).takeUnretainedValue()
    return screen.frame;
}

@_cdecl("SWScreenGetDebugDescription")
public func SWScreenGetDebugDescription(_ screenRef: SWScreenRef) -> UnsafePointer<CChar>? {
    let screen = Unmanaged<Screen>.fromOpaque(screenRef).takeUnretainedValue()
    return (screen.debugDescription as NSString).utf8String ?? nil
}

@_cdecl("SWScreenGetSpaceID")
public func SWScreenGetSpaceID(_ screenRef: SWScreenRef) -> CInt {
    let screen = Unmanaged<Screen>.fromOpaque(screenRef).takeUnretainedValue()
    return CInt(screen.spaceId)
}


/* ---- Applications ---- */
@_cdecl("SWApplicationGetPid")
public func SWApplicationGetPid(_ appRef: SWApplicationRef) -> pid_t {
    let app = Unmanaged<Application>.fromOpaque(appRef).takeUnretainedValue()
    return app.processIdentifier
}

@_cdecl("SWApplicationGetBundleIdentifier")
public func SWApplicationGetBundleIdentifier(_ appRef: SWApplicationRef) -> UnsafePointer<CChar>? {
    let app = Unmanaged<Application>.fromOpaque(appRef).takeUnretainedValue()
    if let bid = app.bundleIdentifier {
        return (bid as NSString).utf8String
    }
    
    return nil
}

@_cdecl("SWApplicationGetKnownWindows")
public func SWApplicationGetKnownWindows(_ appRef: SWApplicationRef, outPtr: UnsafeMutablePointer<OpaquePointer>?) -> UInt32 {
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    let windows = app.knownWindows
    if let ptr = outPtr {
        windows.copyOutCArray(ptr)
    }
    
    return UInt32(app.knownWindows.count)
}

@_cdecl("SWApplicationGetMainWindow")
public func SWApplicationGetMainWindow(_ appRef: SWApplicationRef) -> OpaquePointer? {
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    if let mainWindow = app.mainWindow.getValue() {
        let retained = Unmanaged.passRetained(mainWindow).toOpaque()
        return OpaquePointer(retained)
    }
    
    return nil
}

@_cdecl("SWApplicationSetMainWindow")
public func SWApplicationSetMainWindow(_ appRef: SWApplicationRef, windowRef: SWWindowRef, onComplete: SWCompletionBlock?) {
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(windowRef)).takeUnretainedValue()
    _ = app.mainWindow.set(window).asVoid()
    if let done = onComplete { done() }
}

@_cdecl("SWApplicationGetFocusedWindow")
public func SWApplicationGetFocusedWindow(_ appRef: SWApplicationRef) -> OpaquePointer? {
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    if let focusedWindow = app.focusedWindow.getValue() {
        let retained = Unmanaged.passRetained(focusedWindow).autorelease().toOpaque()
        return OpaquePointer(retained)
    }
    
    return nil
}

@_cdecl("SWApplicationGetIsHidden")
public func SWApplicationGetIsHidden(_ appRef: SWApplicationRef) -> CBool {
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    return CBool(app.isHidden.getValue())
}

@_cdecl("SWApplicationSetIsHidden")
public func SWApplicationSetIsHidden(_ appRef: SWApplicationRef, isHidden: CBool, onComplete: SWCompletionBlock?) {
    let app = Unmanaged<Application>.fromOpaque(UnsafeRawPointer(appRef)).takeUnretainedValue()
    _ = app.isHidden.set(Bool(isHidden)).asVoid()
    if let done = onComplete { done() }
}


/* ---- Windows ---- */
@_cdecl("SWWindowGetApplication")
public func SWWindowGetApplication(_ winRef: SWWindowRef) -> OpaquePointer? {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    let app = window.application
    let ret = Unmanaged.passRetained(app).autorelease().toOpaque()
    return OpaquePointer(ret)
}

@_cdecl("SWWindowGetPosition")
public func SWWindowGetPosition(_ winRef: SWWindowRef) -> CGPoint {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    let frame = window.frame.getValue()
    return frame.origin
}

@_cdecl("SWWindowGetTitle")
public func SWWindowGetTitle(_ winRef: SWWindowRef) -> UnsafePointer<CChar>? {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    return (window.title.getValue() as NSString).utf8String ?? nil
}

@_cdecl("SWWindowGetScreen")
public func SWWindowGetScreen(_ winRef: SWWindowRef) -> OpaquePointer? {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    if let screen = window.screen {
        let ret = Unmanaged.passRetained(screen).autorelease().toOpaque()
        return OpaquePointer(ret)
    }
    return nil
}

@_cdecl("SWWindowGetFrame")
public func SWWindowGetFrame(_ winRef: SWWindowRef) -> CGRect {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    let frame = window.frame.getValue()
    return frame
}

@_cdecl("SWWindowSetFrame")
public func SWWindowSetFrame(_ winRef: SWWindowRef, frame: CGRect, onComplete: SWCompletionBlock?) -> Void {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    _ = window.frame.set(frame).asVoid()
    if let done = onComplete { done() }
}

@_cdecl("SWWindowGetSize")
public func SWWindowGetSize(_ winRef: SWWindowRef) -> CGSize {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    let size = window.size.getValue()
    return size
}

@_cdecl("SWWindowSetSize")
public func SWSetSize(_ winRef: SWWindowRef, size: CGSize, onComplete: SWCompletionBlock?) -> Void {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    _ = window.size.set(size).asVoid()
    if let done = onComplete { done() }
}

@_cdecl("SWWindowGetIsMinimized")
public func SWWindowGetIsMinimized(_ winRef: SWWindowRef) -> CBool {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    let isMinimized = window.isMinimized.getValue()
    return isMinimized
}

@_cdecl("SWWindowSetIsMinimized")
public func SWSetIsMinimized(_ winRef: SWWindowRef, minimized: Bool, onComplete: SWCompletionBlock?) -> Void {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    _ = window.isMinimized.set(minimized).asVoid()
    if let done = onComplete { done() }
}

@_cdecl("SWWindowGetIsFullscreen")
public func SWWindowGetIsFullscreen(_ winRef: SWWindowRef) -> CBool {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    let isFullscreen = window.isFullscreen.getValue()
    return isFullscreen
}

@_cdecl("SWWindowSetIsFullscreen")
public func SWWindowSetIsFullscreen(_ winRef: SWWindowRef, fullscreen: Bool, onComplete: SWCompletionBlock?) -> Void {
    let window = Unmanaged<Window>.fromOpaque(UnsafeRawPointer(winRef)).takeUnretainedValue()
    _ = window.isFullscreen.set(fullscreen).asVoid()
    if let done = onComplete { done() }
}


/* ---- Events ---- */
@_cdecl("SWStateOnSpaceWillChange")
public func SWStateOnSpaceWillChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ ids: UnsafeMutablePointer<UInt32>?, _ count: CInt) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: SpaceWillChangeEvent) in
        var c_ids = event.ids.map { UInt32($0) }
        let a = c_ids.withUnsafeMutableBufferPointer { ptr in
            return ptr
        }
        
        handler(CBool(event.external), UnsafeMutablePointer(a.baseAddress), CInt(event.ids.count))
    }
}

@_cdecl("SWStateOnSpaceDidChange")
public func SWStateOnSpaceDidChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ ids: UnsafeMutablePointer<UInt32>?, _ count: CInt) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: SpaceDidChangeEvent) in
        var c_ids = event.ids.map { UInt32($0) }
        let a = c_ids.withUnsafeMutableBufferPointer { ptr in
            return ptr
        }
        
        handler(CBool(event.external), UnsafeMutablePointer(a.baseAddress), CInt(event.ids.count))
    }
}

@_cdecl("SWStateOnFrontmostApplicationDidChange")
public func SWStateOnFrontmostApplicationDidChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ from: OpaquePointer?, _ to: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: FrontmostApplicationChangedEvent) in
        var old: UnsafeMutableRawPointer? = nil
        if let oldValue = event.oldValue {
            old =  Unmanaged.passRetained(oldValue).autorelease().toOpaque()
        }
        
        var new: UnsafeMutableRawPointer? = nil
        if let newValue = event.newValue {
            new = Unmanaged.passRetained(newValue).autorelease().toOpaque()
        }
        
        handler(CBool(event.external), OpaquePointer(old), OpaquePointer(new))
    }
}

@_cdecl("SWStateOnApplicationDidLaunch")
public func SWStateOnApplicationDidLaunch(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: ApplicationLaunchedEvent) in
        let app = Unmanaged.passRetained(event.application).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(app))
    }
}

@_cdecl("SWStateOnApplicationDidTerminate")
public func SWStateOnApplicationDidTerminate(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: ApplicationTerminatedEvent) in
        let app = Unmanaged.passRetained(event.application).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(app))
    }
}

@_cdecl("SWStateOnWindowCreate")
public func SWStateOnWindowCreate(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: WindowCreatedEvent) in
        let window = Unmanaged.passRetained(event.window).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(window))
    }
}

@_cdecl("SWStateOnWindowDestroy")
public func SWStateOnWindowDestroy(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: WindowDestroyedEvent) in
        let window = Unmanaged.passRetained(event.window).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(window))
    }
}

@_cdecl("SWStateOnWindowDidResize")
public func SWStateOnWindowDidResize(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ window: OpaquePointer?, _ from: CGRect, _ to: CGRect) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: WindowFrameChangedEvent) in
        let window = Unmanaged.passRetained(event.window).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(window), event.oldValue, event.newValue)
    }

}

@_cdecl("SWStateOnWindowDidChangeTitle")
public func SWStateOnWindowDidChangeTitle(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ window: OpaquePointer?, _ from: UnsafePointer<CChar>?, _ to: UnsafePointer<CChar>?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: WindowTitleChangedEvent) in
        let window = Unmanaged.passRetained(event.window).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(window), event.oldValue, event.newValue)
    }

}

@_cdecl("SWStateOnWindowMinimizeDidChange")
public func SWStateOnWindowMinimizeDidChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ window: OpaquePointer?, _ from: CBool, _ to: CBool) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: WindowMinimizedChangedEvent) in
        let window = Unmanaged.passRetained(event.window).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(window), CBool(event.oldValue), CBool(event.newValue))
    }
}

@_cdecl("SWStateOnApplicationIsHiddenDidChange")
public func SWStateOnApplicationIsHiddenDidChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?, _ from: CBool, _ to: CBool) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: ApplicationIsHiddenChangedEvent) in
        let app = Unmanaged.passRetained(event.application).autorelease().toOpaque()
        handler(CBool(event.external), OpaquePointer(app), CBool(event.oldValue), CBool(event.newValue))
    }
}

@_cdecl("SWStateOnApplicationMainWindowDidChange")
public func SWStateOnApplicationMainWindowDidChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?, _ from: OpaquePointer?, _ to: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: ApplicationMainWindowChangedEvent) in
        let app = Unmanaged.passRetained(event.application).autorelease().toOpaque()
        var from: UnsafeMutableRawPointer? = nil
        if let oldValue = event.oldValue {
            from = Unmanaged<Window>.passRetained(oldValue).autorelease().toOpaque()
        }
        
        var to: UnsafeMutableRawPointer? = nil
        if let newValue = event.newValue {
            to = Unmanaged<Window>.passRetained(newValue).autorelease().toOpaque()
        }
        
        handler(CBool(event.external), OpaquePointer(app), OpaquePointer(from), OpaquePointer(to))
    }
}

@_cdecl("SWStateOnApplicationFocusWindowDidChange")
public func SWStateOnApplicationFocusWindowDidChange(_ stateRef: SWStateRef, handler: @escaping (_ external: CBool, _ app: OpaquePointer?, _ from: OpaquePointer?, _ to: OpaquePointer?) -> Void) -> Void {
    let state = Unmanaged<State>.fromOpaque(UnsafeRawPointer(stateRef)).takeUnretainedValue()
    state.on { (event: ApplicationFocusedWindowChangedEvent) in
        let app = Unmanaged.passRetained(event.application).autorelease().toOpaque()
        var from: UnsafeMutableRawPointer? = nil
        if let oldValue = event.oldValue {
            from = Unmanaged<Window>.passRetained(oldValue).autorelease().toOpaque()
        }
        
        var to: UnsafeMutableRawPointer? = nil
        if let newValue = event.newValue {
            to = Unmanaged<Window>.passRetained(newValue).autorelease().toOpaque()
        }
        
        handler(CBool(event.external), OpaquePointer(app), OpaquePointer(from), OpaquePointer(to))
    }
}

extension Collection {
    public func copyOutCArray(_ outPtr: UnsafeMutablePointer<OpaquePointer>) -> Void {
        for (i, element) in self.enumerated() {
            let e = element as AnyObject
            let elemRef = Unmanaged.passRetained(e).autorelease().toOpaque()
            outPtr[i] = OpaquePointer(elemRef)
        }
    }
}
