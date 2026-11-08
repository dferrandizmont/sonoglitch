/// The GPU test oracles of Sonoglitch.
///
/// The shaders live in this dev-only package so that `flutter test` can load
/// them while no release build carries them: Flutter bundles the assets of the
/// packages that are only `dev_dependencies` when it builds the test bundle,
/// and leaves them out of every other build.
///
/// The oracles are frozen copies of older shaders. They are compared pixel by
/// pixel with the current ones, so their source must not change.
library;

/// The name of this package, as it appears in the asset keys of its shaders.
const String sonoglitchTestShadersPackage = 'sonoglitch_test_shaders';

/// The asset key of a GPU test oracle, for example `d2a_delivery1_static`.
///
/// The key is also the path of the shader source inside the repository, so the
/// tests can read the frozen source and load it with the same string.
String testOracleAsset(String name) =>
    'packages/$sonoglitchTestShadersPackage/shaders/$name.frag';
