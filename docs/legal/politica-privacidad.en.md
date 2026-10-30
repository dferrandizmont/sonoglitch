# Privacy policy

*Last updated: 2026-10-27. Applies to Sonoglitch (all versions).*

Sonoglitch is a camera app that distorts photos according to the sound level, the light and the movement around you. It is free, open source software and it works entirely on your device.

## What the app does with your data

| Data | Why | Where it goes |
| --- | --- | --- |
| Camera image | Live preview with the effect and taking the photo | Stays on your device. While you work on a photo, temporary files may exist in the app's private cache (no other app can read them) until the system clears it or you uninstall the app. Photos are saved to your gallery only when you tap Save. |
| Microphone | Only numbers are measured, in memory, to drive the effect: the **volume level** and the energy of **three frequency bands** (bass, mid, treble) | **No audio is recorded, stored or sent.** The microphone's audio buffers are processed in memory only to compute the volume and the three band energies and are then discarded; only the resulting numbers are kept, briefly. |
| Motion sensors (accelerometer and gyroscope) | Measure how much the phone moves and turns | Used in memory. Readings can appear in the local diagnostics log as plain numbers (see *Diagnostics*); never sent. |
| Image analysis | Brightness, how colourful the scene is, and the difference between consecutive small camera frames, computed to drive the effect | Used in memory. Brightness and movement readings can appear in the local diagnostics log as plain numbers; never sent. |
| Compass (magnetometer) and barometer | The direction the phone faces gives a small variation of the effect; the optional context line can also print the heading and the air pressure of a photo | Read in memory around the moment of the shot, never stored, logged or sent. The compass is approximate and magnetic; there is no location lookup. |
| Clock and calendar | The time of day, the date and the moon phase give a small variation of the effect; the optional context line (off by default) can print them on the exported picture | Computed in memory from the system clock. Only what you choose to export is written into the picture you save or share. |
| Photo gallery | Saves the photo you choose to save | Written to your gallery only when you tap Save. |

## What the app does not do

- It has no accounts, no ads, no analytics and no trackers.
- Release builds do not declare the Android `INTERNET` permission, so the app has no network access. (Debug and profile builds made by developers include it, as Flutter requires for its tooling.)
- On Android it asks for no storage permission: photos are saved through the system media store, and the app does not read other apps' files. On iOS the system asks for access to your photo library so the app can save into its own album.
- On Android, its data is excluded from device and cloud backups.
- It does not share data with anyone. When you tap Share, the photo is handed to the app you choose through the system share sheet; from then on that app's own privacy policy applies.

## Diagnostics

The app keeps a small text log in its private storage on your device: technical events, timings, errors and the numeric readings shown in the diagnostics panel (volume level, brightness, movement as plain numbers), plus the device model and Android version. It never contains audio or photos. It is shared only if you tap *Share logs* or *Copy report* and send it yourself. You can remove it by clearing the app's storage or uninstalling the app.

## Optional links

Some builds (F-Droid and the GitHub releases) show an optional "Support the project" link to a Ko-fi page; the Google Play build has none. Tapping it opens the link in another app on your device, normally your browser. Nothing is sent by the app itself, and the app does not know whether you donate.

## Children

The app does not collect personal data from anyone, including children.

## Changes and contact

Changes to this policy will appear in this file and in the release notes. Questions: write to dev@mainshai.com or open an issue in the project repository.
