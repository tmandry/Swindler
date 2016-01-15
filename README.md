# Swindler
_A Swift window management framework for OS X_

In the past few years, many developers formerly on Linux and Windows have migrated to Mac for their
excellent hardware and UNIX-based OS that "just works".

But along the way we gave up something dear to us: control over our desktop environment.

**The goal of Swindler is to help us take back that control**, and give us the best of both worlds.

## What Swindler Does

Writing window managers for OS X is hard. There are a lot of systemic challenges, including limited
and poorly-documented APIs. All window managers on OS X must use the C-based accessibility APIs, which
are difficult to use and are surprisingly buggy themselves.

As a result, the selection of window managers is pretty limited, and many of the ones out there have
annoying bugs, like freezes, race conditions, "phantom windows", and not "seeing" windows that are
actually there. The more sophisticated the window manager is, the more it relies on these APIs and
the more these bugs start to show up.

Swindler's job is to make it easy to write powerful window managers using a well-documented Swift
API and abstraction layer. It addresses the problems of the accessibility API with these features:

#### Type safety

[Swindler's API](https://github.com/tmandry/Swindler/blob/master/Swindler/API.swift) is
fully documented and type-safe thanks to Swift. It's much easier and safer to use than the C-based
accessibility APIs. (See the example below.)

#### In-memory model

Window managers on OS X rely on IPC: you _ask_ an application for a window's position, _wait_ for it
to respond, _request_ that it be moved or focused, then _wait_ for the application to comply (or
not). Most of the time this works okay, but it works at the mercy of the remote application's event
loop, which can lead to long, multi-second delays.

Swindler maintains a model of all applications and window states, so your code knows everything
about the windows on the screen. **Reads are instantaneous**, because all state is cached within your
application's process and stays up to date. Swindler is extensively tested to ensure it stays
consistent with the system in any situation.

#### Asynchronous writes and refreshes

If you need to resize a lot of windows simultaneously, for example, you can do so without fear of
one unresponsive application holding everything else up. Write requests are dispatched
asynchronously and concurrently, and Swindler's promise-based API makes it easy to keep up with the
state of operations.

#### Friendly events

More sophisticated window managers have to observe events on windows, but the observer API is
not well documented and often leaves out events you might expect, or delivers them in the wrong order.
For example, the following situation is common when a new window pops up:

```
1. MainWindowChanged on com.google.chrome to <window1>
2. WindowCreated on com.google.chrome: <window1>
```

See the problem? With Swindler, all events are emitted in the expected order, and missing ones are
filled in. Swindler's in-memory state will always be consistent with itself and with the events you
receive, avoiding many bugs that are difficult to diagnose.

As a bonus, **events caused by your code are marked** as such, so you don't respond to them as user
actions. This feature alone makes a whole new level of sophistication possible.

## Example

The following code assigns all windows on the screen to a grid. Note the simplicity and power of the
promise-based API. Requests are dispatched concurrently and in the background, not serially.

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

Watching for events is simple. Here's how you would implement snap-to-grid:

```swift
swindler.on { (event: WindowMovedEvent) in
  guard event.external == true else {
    // Ignore events that were caused by us.
    return
  }
  let snapped = closestGridPosition(event.window.position.value)
  event.window.position.set(snapped)
}
```

## Project Status

Swindler is in development and is in **alpha**. Here is the state of its major features:

- Asynchronous property system: **100% complete**
- Event system: **100% complete**
- Window API: **80% complete**
- Application API: **80% complete**
- Screen API: **0% complete**
- Spaces API: **0% complete**

You can see the entire [planned API here](https://github.com/tmandry/Swindler/blob/master/Swindler/API.swift).

## Contact

Follow me on Twitter: [@tmandry](https://twitter.com/tmandry)

## Related Projects

- [Silica](https://github.com/ianyh/Silica)
- [Mjolnir](https://github.com/sdegutis/mjolnir)
- [Hammerspoon](https://github.com/Hammerspoon/hammerspoon), a fork of Mjolnir
