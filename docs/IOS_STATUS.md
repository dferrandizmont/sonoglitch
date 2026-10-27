# iOS status

iOS is not release-ready. Android remains the primary target. The shared Dart code and iOS project configuration do not establish that an iOS build or device flow works.

This configuration was reviewed on Windows, where CocoaPods installation, Xcode compilation, signing and iOS simulator/device testing cannot be verified.

## Configuration in this repository

- The Podfile and the Xcode project's Debug, Profile and Release deployment targets use iOS 16.0.
- The Podfile post-install hook enables only `PERMISSION_CAMERA=1` and `PERMISSION_MICROPHONE=1` for `permission_handler`, preserving inherited preprocessor definitions. This follows the CocoaPods example in the locked `permission_handler_apple` 9.6.4 package. Gallery permissions are handled by Gal; no photo permission macros are enabled for `permission_handler`.
- `Info.plist` describes camera use, microphone level measurement, adding photos and photo-library access to find/create the named Sonoglitch album. The broader photo-library string is needed for album access, rather than just adding an image.
- iOS has no ambient-lux channel implementation; light falls back to camera-image brightness.

## Required Mac and device verification

On a Mac with Flutter 3.47.7, Xcode and CocoaPods, resolve the locked dependencies, run `pod install` in `ios/` and inspect the resolved deployment targets and permission macros. Build the app, configure signing and test on a physical iPhone running iOS 16 or later before considering a release.

Check camera and microphone grant/deny/revocation, continuing without microphone access, level-only microphone behavior and calibration, front/back orientation and mirroring, background/foreground and covered-viewfinder lifecycle, repeated capture, crops, album creation/saving, limited or denied photo-library access and sharing. Confirm temporary-file cleanup on success and failure. No iOS build, simulator run or physical-device validation is claimed by this change.
