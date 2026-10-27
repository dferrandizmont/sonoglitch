# Releasing Sonoglitch

Sonoglitch is free everywhere. It ships through three channels that differ only in the signing key and in the optional "Support the project" row of Settings, which is controlled by one build-time define:

| Channel | Signed by | Donation link (`DONATION_URL`) |
| --- | --- | --- |
| **F-Droid** | F-Droid, from this repository | `https://ko-fi.com/danielmfdev` |
| **GitHub releases** | the repository keystore (see [Contributing](../CONTRIBUTING.md#release-workflow)) | `https://ko-fi.com/danielmfdev` |
| **Google Play** | Google Play App Signing, with the upload key below | none: the build is made without the define and the row is hidden |

Google Play's payments policy restricts apps that ask for donations outside Play's own billing, so the Play build must never be built with `DONATION_URL`. Check the current policy before each submission.

## Versions

- `pubspec.yaml` has `version: 0.1.0+N`. `N` is the Android `versionCode` and must grow with every upload to any store.
- `--build-name` is the numeric part (`0.1.0`); `--dart-define=APP_VERSION=0.1.0-alpha.N` sets the version shown in About.
- Add `fastlane/metadata/android/{en-US,es-ES}/changelogs/N.txt` (at most 500 bytes each) and a section in `CHANGELOG.md` for every release. The F-Droid recipe in [`fdroid/`](../fdroid/es.sonoglitch.app.yml) must carry the same version name, code and tag.

## Public and private repositories

Development happens in a private repository. This public repository receives one commit per release, a snapshot of the tagged tree, with the version tag; the development history is not published. `tool/publish/publish_public.ps1 -Tag vX.Y.Z` makes the snapshot from tracked files only, scans it for secrets and pushes it (use `-DryRun` first). Pushing the tag starts the *Release APK* workflow, which builds, signs and publishes the GitHub release. F-Droid builds from these tags. Pull requests to this repository are reviewed here and ported to the private repository by the maintainer.

## Google Play

### One-time: the upload key

On Windows, `tool/release/setup_upload_key.ps1` does the steps below interactively (the password is typed in the console) and `tool/release/build_play_bundle.ps1` builds the bundle and prints the merged manifest.

Create it outside the repository and keep a backup (a password manager plus an offline copy). If it is lost, Play can reset an upload key, but only through support.

```sh
keytool -genkeypair -v -keystore sonoglitch-upload.jks -alias upload \
  -keyalg RSA -keysize 4096 -validity 10000
```

Then create `android/key.properties` (ignored by git) with `storeFile` (an absolute path, or one relative to `android/`; on Windows use forward slashes or doubled backslashes, because it is a Java properties file), `storePassword`, `keyAlias` and `keyPassword`. Never commit either file or paste their contents anywhere.

### Each release

```sh
flutter build appbundle --release --build-name=0.1.0 --build-number=N \
  --dart-define=APP_VERSION=0.1.0-alpha.N
```

Do **not** pass `DONATION_URL`. Upload `build/app/outputs/bundle/release/app-release.aab` in Play Console, enrolling in Play App Signing on the first upload. Use the internal or closed testing track first. At the time of writing, a new personal developer account must run a closed test with at least 12 testers for 14 days before it can publish to production; check the requirement in Play Console.

### Store listing

- Title, short and full descriptions: `fastlane/metadata/android/<locale>/` (English and Spanish).
- Privacy policy URL: the rendered `docs/PRIVACY.md` of the public repository (for example `https://github.com/dferrandizmont/sonoglitch/blob/main/docs/PRIVACY.md`). The repository must be public first.
- Contact email: `dev@mainshai.com`.
- Price: free, no ads, no in-app purchases.
- Assets that must be made on a device: a 512×512 icon, a 1024×500 feature graphic and at least two phone screenshots.

### Data safety form

The app collects and shares nothing: answer *No* to "Does your app collect or share any of the required user data types?". Camera and microphone are used for on-device processing only (see the [privacy policy](PRIVACY.md)); audio is never recorded, stored or sent, and the release build has no `INTERNET` permission. Declared permissions: `CAMERA`, `RECORD_AUDIO`. Content rating: answer the questionnaire in Play Console (no user-generated content, no location sharing, no purchases); do not assume the outcome. The photo or report the user chooses to share goes to another app through the system share sheet at the user's request, which Play's Data safety rules treat as user-initiated, not as the app sharing data; check the current wording of those rules when filling the form.

## F-Droid

F-Droid builds the app from source with its own key. The recipe is [`fdroid/es.sonoglitch.app.yml`](../fdroid/es.sonoglitch.app.yml). Title, descriptions, changelogs and images come from `fastlane/metadata/android`.

1. Tag the release commit (`v0.1.0-alpha.N`) and push the tag.
2. Fork `https://gitlab.com/fdroid/fdroiddata` and copy the recipe to `metadata/es.sonoglitch.app.yml`. Update `versionName`, `versionCode`, `commit`, `CurrentVersion`, `CurrentVersionCode` and, in the `build` command, `--build-name`, `--build-number` and `APP_VERSION`, so the version shown in About matches.
3. Open a merge request. The F-Droid team reviews the recipe and builds it. Fix whatever their scanner or build reports.
4. Later releases need a new `Builds` entry. Automatic updates (`UpdateCheckMode: Tags` with `AutoUpdateMode: Version`) can be configured later, once the tag pattern is stable.
5. The recipe is untested against the real F-Droid build server: expect a round or two of fixes from the reviewers (scanner findings on pub packages, toolchain provisioning).

The *Donate* link of the F-Droid listing comes from the recipe's `Donate:` field; the build also passes `DONATION_URL` for the row in Settings. Check that the merged manifest still declares only `CAMERA` and `RECORD_AUDIO` (no `INTERNET`).

## GitHub releases

Push a `v*` tag. The [workflow](../.github/workflows/release.yml) builds, signs with the repository secrets and publishes the APK with its checksum, including the Ko-fi link. If Actions are unavailable, build locally with the same command and `--build-number=N`, copy the APK to `sonoglitch-<version>.apk`, write its checksum with `sha256sum`, and create the release with `gh release create v<version> <apk> <checksum> --target main --prerelease` (use `--prerelease` for every alpha). A local build without `android/key.properties` is signed with the debug key, which is only acceptable for private test builds; stable releases must use the real key.
