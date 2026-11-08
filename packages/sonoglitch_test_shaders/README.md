# sonoglitch_test_shaders

Frozen GPU test oracles for Sonoglitch.

The six `.frag` files in `shaders/` are frozen copies of older app shaders.
The tests render them side by side with the current shaders and compare the
pixels, so their source must never change.

They are declared in this package, and not in the app, because Flutter compiles
every shader that a package declares into the builds that use it. As a
`dev_dependency` of the app, this package is only bundled when `flutter test`
builds the test asset bundle: a release APK carries the twelve app shaders and
none of these oracles.

The tests load them with the asset key
`packages/sonoglitch_test_shaders/shaders/<name>.frag`, which
`package:sonoglitch_test_shaders/sonoglitch_test_shaders.dart` returns with
`testOracleAsset()`.
