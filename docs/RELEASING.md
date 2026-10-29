# Releasing Sonoglitch

Sonoglitch is free everywhere. It ships through three channels that differ only in the signing key and in the optional "Support the project" row of Settings, which is controlled by one build-time define:

| Channel | Signed by | Donation link (`DONATION_URL`) |
| --- | --- | --- |
| **F-Droid** | F-Droid, from this repository | `https://ko-fi.com/danielmfdev` |
| **GitHub releases** | the repository keystore (see [Contributing](../CONTRIBUTING.md#release-workflow)) | `https://ko-fi.com/danielmfdev` |
| **Google Play** | Google Play App Signing, with the upload key below | none: the build is made without the define and the row is hidden |

Google Play's payments policy restricts apps that ask for donations outside Play's own billing, so the Play build must never be built with `DONATION_URL`. Check the current policy before each submission.

## Versionado y trazabilidad

**El número de build es un contador reservado por subida**, no el número de commits: recompilar el mismo commit dos
veces no cambia nada, y la tienda rechaza el segundo build. Además, **iOS y Android llevan contadores independientes**.

| Campo | Regla | Dónde se aplica |
|---|---|---|
| Nombre de versión | Semántica (`0.1.1`), el mismo en todos los canales y el que muestra la app (`--dart-define=APP_VERSION=`) | `pubspec.yaml`, `--build-name`, receta de F-Droid |
| Número de build | **Estrictamente creciente**: uno nuevo por cada subida | `pubspec.yaml` (`0.1.1+22`), `--build-number` |
| `pubspec.yaml` | Lleva la versión y el build que se va a compilar; se sube en el commit `chore: release` | `pubspec.yaml` |
| Commit | El que se compila, etiquetado `vX.Y.Z` y anotado en el registro | etiqueta de git |
| Artefacto | El `.apk` / `.aab` / `.ipa` **exactos** que se suben (nunca «el último que salió») | registro de subidas |
| Símbolos | `build/symbols/<versión>-<build>/` **archivada fuera del repositorio**, junto al build | registro de subidas |
| Resultado | Fecha, estado de la tienda y enlaces públicos | registro de subidas |

Qué número sube (decidido el 27-oct-2026):

| Cambio | Número | Ejemplo |
|---|---|---|
| Arreglos y retoques | **patch** | 0.1.1 → 0.1.2 |
| Funciones nuevas | **minor** | 0.1.x → 0.2.0 |
| Salida a producción en las tiendas | **major** | → 1.0.0 |
| Si ya está en producción: cambios grandes | **major** | 1.x → 2.0.0 |

Hasta ahora las versiones fueron `0.1.0-alpha.N` (con `N` igual al build); la `0.1.0-alpha.21` es la última con ese
formato y la siguiente ya sigue esta tabla.

- **Vías rápidas, cada versión probada:** GitHub Releases (APK de Android) y **TestFlight** (iOS).
- **Tiendas, versiones agrupadas:** **Google Play** y **App Store** reciben varias juntas, nunca mientras la anterior
  está en revisión. Pueden saltar números (0.1.4 → 0.2.0), y no hace falta que las dos tiendas vayan a la vez.
- **Un número de versión es siempre el mismo código en todos los canales:** se compila del mismo commit y no se
  reutiliza para otro código.
- **Android lleva un solo contador de build** (`versionCode`) para Play y GitHub, estrictamente creciente. Con
  `--split-per-abi`, Flutter suma 1000 (armeabi-v7a) o 2000 (arm64-v8a) al build; las releases actuales usan un APK
  único (`--target-platform android-arm64,android-x64`), sin esa suma.
- **iOS:** `CFBundleShortVersionString` es la misma versión semántica (`--build-name`) y `CFBundleVersion` es el
  contador de build propio de iOS (`--build-number`), estrictamente creciente; se apunta en el registro como los de
  Android.
- Lo que va a salir se apunta en **[CHANGELOG.md](../CHANGELOG.md)** (en inglés, sección «Unreleased»), con cada cambio que note
  el usuario. El día de la versión se convierte en su sección y es la base de las notas de la release y de la ficha.
- Cada release lleva además `fastlane/metadata/android/{en-US,es-ES}/changelogs/<build>.txt` (como mucho 500 bytes) y la
  receta de [F-Droid](../fdroid/es.sonoglitch.app.yml) con el mismo nombre de versión, build y etiqueta.

**Registro de subidas** (una fila por subida; se rellena en el momento, no al final):

| Fecha | Canal | Versión | Build | Commit | Artefacto | Resultado | Símbolos |
|---|---|---|---|---|---|---|---|
| 24-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.1 | 1 | `011520e` | `sonoglitch-0.1.0-alpha.1.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 26-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.11 | 11 | `ba55b35` | `sonoglitch-0.1.0-alpha.11.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 26-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.12 | 12 | `6194089` | `sonoglitch-0.1.0-alpha.12.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 26-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.13 | 13 | `9a218a4` | `sonoglitch-0.1.0-alpha.13.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 26-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.14 | 14 | `611e68b` | `sonoglitch-0.1.0-alpha.14.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 27-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.15 | 15 | `fca0045` | `sonoglitch-0.1.0-alpha.15.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 27-oct-2026 | GitHub Releases (repositorio privado) | 0.1.0-alpha.16 | 16 | `5eb410c` | `sonoglitch-0.1.0-alpha.16.apk`, clave de depuración | Publicada (prerelease) | no archivados |
| 27-oct-2026 | GitHub Releases (repositorio público) | 0.1.0-alpha.17 | 17 | `882eb8c` (público `bf675aa`) | ninguno: el flujo de la release falló en un test | Sin publicar; la etiqueta se borró | — |
| 27-oct-2026 | GitHub Releases (repositorio público) | 0.1.0-alpha.18 | 18 | `89cd91e` (público `ede33da`) | `sonoglitch-0.1.0-alpha.18.apk`, compilado por Actions, clave de depuración | Publicada (prerelease) | no archivados |
| 27-oct-2026 | GitHub Releases (repositorio público) | 0.1.0-alpha.19 | 19 | `de7defc` (público `2607798`) | `sonoglitch-0.1.0-alpha.19.apk`, Actions, clave de depuración | Publicada (prerelease) | no archivados |
| 27-oct-2026 | GitHub Releases (repositorio público) | 0.1.0-alpha.20 | 20 | `0f0dc34` (público `2ba3a60`) | `sonoglitch-0.1.0-alpha.20.apk`, Actions, clave de depuración | Publicada (prerelease) | no archivados |
| 27-oct-2026 | GitHub Releases (repositorio público) | 0.1.0-alpha.21 | 21 | `4439eeb` (público `9bd315d`) | `sonoglitch-0.1.0-alpha.21.apk`, Actions, clave de depuración | Publicada (prerelease) | no archivados |

Todavía no hay ninguna subida a Google Play ni a TestFlight. El AAB de la build 19 se compiló en local con la clave de
subida (27-oct-2026, commit `de7defc`) y **no se subió**: quedó obsoleto, y la primera subida a Play usará un build
mayor que 21.

- La compilación de los Android de GitHub sin los cuatro secretos de firma usa la clave de depuración: sirve para
  alphas. Una versión estable los exige (véase el flujo *Release APK*).
- Las etiquetas del repositorio público (`ede33da`…) son instantáneas de una sola vez por versión; las del privado
  apuntan al commit de desarrollo.

## Public and private repositories

Development happens in a private repository. This public repository receives one commit per release, a snapshot of the tagged tree, with the version tag; the development history is not published. `tool/publish/publish_public.ps1 -Tag vX.Y.Z` makes the snapshot from tracked files only, scans it for secrets and pushes it (use `-DryRun` first). Pushing the tag starts the *Release APK* workflow, which builds, signs and publishes the GitHub release. F-Droid builds from these tags. Pull requests to this repository are reviewed here and ported to the private repository by the maintainer.

### Release flow: test privately first, then publish

1. Commit `chore: release`, bump `pubspec.yaml`, `CHANGELOG.md` and the F-Droid recipe, and create the tag `vX.Y.Z` in the private repository. Push the commit and the tag there: its *Release APK* workflow builds a private prerelease with the same tree.
2. Install that APK on a phone and test it (it carries the signature of the signing secrets, so it updates over the previous one).
3. Only if it is good, run `tool/publish/publish_public.ps1 -Tag vX.Y.Z` (first with `-DryRun`). The public workflow builds the public release from the snapshot of the same tree.
4. Add the row to the register of uploads in *Versionado y trazabilidad*.

Both repositories need the four signing secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) with the **same** upload key, so that every APK has the same signature and installs over the previous one. Without them the workflow signs with a debug key that is new on every run: only acceptable for prereleases, and each build must then be uninstalled before the next one. Set them with `gh secret set <NAME> --repo <owner/repo> --body <value>`, reading the values from `android/key.properties` and the `.jks` without printing them. Never commit or paste them.

### Screenshot build

Use this private build to photograph real scenes with fixed demo readings:

```sh
flutter build apk --release --dart-define=SONOGLITCH_SCREENSHOTS=true --dart-define=APP_VERSION=<version>-screenshots
```

Replace `<version>` before running the command. In Settings, open **Screenshot
mode (not for stores)**, enable **Demo values**, and choose Calm, Lively, Intense
or adjust Custom. The values survive navigation and captures, but reset on app
restart. Presets also set illustrative bass, mid and treble levels; sliders can
adjust all nine values independently.

**Never publish or upload this APK. Play, F-Droid and GitHub release builds must
never pass `SONOGLITCH_SCREENSHOTS=true`.** The section is absent by default.

For a clean Android status bar, allow and enter System UI demo mode, then set the
clock, battery, network and notifications (support depends on the device):

```sh
adb shell settings put global sysui_demo_allowed 1
adb shell am broadcast -a com.android.systemui.demo -e command enter
adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 1200
adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
```

Restore the normal status bar after the captures:

```sh
adb shell am broadcast -a com.android.systemui.demo -e command exit
```

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
