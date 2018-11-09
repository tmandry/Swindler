0.0.2
=====

- Swindler.state has been replaced with Swindler.initialize(), which returns a
  Promise.
- An experimental FakeSwindler API has been added for testing code which depends
  on Swindler. The API is expected to change, but probably not too much.
- Setting the frontmostApplication from Swindler should now work.
- Various bug fixes and improvements.
