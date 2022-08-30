import AXSwift
import Cocoa

public class AppWatcher {
    var apps: [pid_t: NSRunningApplication] = [:]

    var observers: [NSObjectProtocol] = []

    var handler: ((NSRunningApplication) -> Void)?

    public static var launches: AsyncStream<NSRunningApplication> {
        AsyncStream { continuation in
            let watcher = AppWatcher()
            watcher.handler = { continuation.yield($0) }
            continuation.onTermination = { @Sendable _ in
                watcher.stopWatching()
            }
            watcher.startWatching()
        }
    }

    init() {}

    func startWatching() {
        addObserver(NSWorkspace.didLaunchApplicationNotification) { app in
            self.add(app: app)
        }
        addObserver(NSWorkspace.didTerminateApplicationNotification) { app in
            self.remove(app: app)
        }
    }

    func stopWatching() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func add(app: NSRunningApplication) {
        if apps.index(forKey: app.processIdentifier) == nil {
            apps[app.processIdentifier] = app
            handler?(app)
        }
    }

    func remove(app: NSRunningApplication) {
        apps.removeValue(forKey: app.processIdentifier)
    }

    func addObserver(
        _ name: NSNotification.Name,
        callback: @escaping @Sendable (NSRunningApplication) -> Void
    ) {
        let workspace = NSWorkspace.shared
        let observer = workspace.notificationCenter.addObserver(
            forName: name,
            object: workspace,
            queue: nil
        ) { note in
            Task.detached {
                let userInfo = note.userInfo!
                let runningApp =
                    userInfo[NSWorkspace.applicationUserInfoKey] as! NSRunningApplication
                callback(runningApp)
            }
        }
        observers.append(observer)
    }
}
