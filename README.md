# Swindler
_A Swift window management framework for OS X_

In the past few years, many developers formerly on Linux and Windows have migrated to Mac for their
excellent hardware and UNIX-based OS that "just works".

But along the way we gave up something dear to us: **control over our desktop environment**. The
goal of Swindler is to help us take back that control and give us the best of both worlds.

## What Swindler Does

**Writing window managers for OS X is hard.** There are a lot of systemic challenges, including limited
and poorly-documented APIs. As a result, the selection of window managers is pretty limited. Swindler's
job is to make it easy to write powerful window managers using Swift.

All window managers on OS X must use the C-based accessibility APIs. The difficulty is that this
relies on IPC: you _ask_ an application for a window's position, _request_ that it be moved or
focused, then _wait_ for the application to comply. Most of the time this works fine, but it works
at the mercy of the remote application's event loop, which can sometimes lead to *long, multi-second
delays*.

Swindler addresses the problems of the accessibility API with these features:

#### In-memory model

Swindler maintains a model of all applications and window states, so your code knows everything
about the windows on the screen. Reading the state is always fast because all state is kept within
your application's process. The framework subscribes to changes on every window to stay up to date.
It's extensively tested to ensure it stays consistent with the system in any situation.

#### Asynchronous writes and refreshes

If you need to resize a lot of windows simultaneously, for example, you can do so without fear of
one unresponsive application holding things up. Write requests are dispatched asynchronously and
concurrently, and Swindler's promise-based API makes it easy to keep up with the state of
operations.

#### Type-safety

[Swindler's API](https://github.com/tmandry/Swindler/blob/master/Swindler/Swindler/API.swift) is
fully documented and type-safe thanks to Swift. It's much easier and safer to use than the C-based
accessibility APIs.

#### Well-ordered events
The following situation is common in accessibility API notifications:

```
MainWindowChanged on com.google.chrome: <window1>
WindowCreated on com.google.chrome: <window1>
```

See the problem? You won't receive updates about a window you don't know exists: you'll always
receive "window created" events first, followed by the others. Swindler's in-memory state will
always be consistent with itself and with the events you receive, avoiding many bugs that are
difficult to diagnose.

As a bonus, events caused by your code are marked, so you don't respond to them as user actions.

## Example

The following code assigns all windows on the first screen to a grid. Note the simplicity and power
of the promise-based API. Requests are dispatched concurrently, not serially.

```swift
let screen = Swindler.state.screens.first!
let allPlacedOnGrid = screen.knownWindows.enumerate().map { index, window in
  let rect = gridRect(screen, index)
  return window.position.set(rect.origin).then { window.size.set(rect.size) }
}

when(allPlacedOnGrid) { _ in
  print("all done!")
}

func gridRect(screen: Swindler.Screen, index: Int) -> CGRect {
  let gridSteps = 3
  let position  = CGSize(width: screen.width / gridSteps, height: screen.height / gridSteps)
  let size      = CGPoint(x: gridSize.width * (index % gridSteps), y: gridSize.height * (index / gridSteps))
  return CGRect(origin: position, size: size)
}
```

Watching for events is simple:

```swift
swindler.on { (event: MainWindowChangedEvent) in
  let window = event.newValue
  print("new main window: \(window?.title.value)")
}
```

## Project Status

Swindler is in development and is in **alpha**. Here is the state of its major features:

- Asynchronous property updates: **100% complete**
- Event system: **100% complete**
- Window API: **80% complete**
- Application API: **80% complete**
- Screen API: **0% complete**
- Spaces API: **0% complete**

You can see the entire [planned API here](https://github.com/tmandry/Swindler/blob/master/Swindler/Swindler/API.swift).

## Contact

Follow me on Twitter: [@tmandry](https://twitter.com/tmandry)

## Related Projects

- [Silica](https://github.com/ianyh/Silica)
- [Mjolnir](https://github.com/sdegutis/mjolnir)
- [Hammerspoon](https://github.com/Hammerspoon/hammerspoon), a fork of Mjolnir
