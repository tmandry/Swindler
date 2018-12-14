0.0.3
=====

Breaking changes
- `Window.position` and the new `Window.frame` now use Cocoa coordinates (origin
  at bottom-left), to match the behavior of Screen and most modern macOS APIs.
- `Window.position` was made non-writeable (use `Window.frame` instead). It may
  be removed in the future. See #29 for more.
- When a property value is written to, and the new value is changed but does
  not match the desired value, the corresponding event is marked as external.
  See #49.

New features
- A `Window.frame` property was added. You can now atomically change the whole
  frame of a window.

Bug fixes
- `ScreenLayoutChangedEvent` is now correctly detected.

0.0.2
=====

Breaking changes
- `Swindler.state` has been replaced with `Swindler.initialize()`, which returns
  a Promise.

New features
- An experimental FakeSwindler API has been added for testing code which depends
  on Swindler. The API is expected to change, but probably not too much.

Bug fixes
- Setting the frontmostApplication from Swindler should now work.
- Various other bug fixes and improvements.
