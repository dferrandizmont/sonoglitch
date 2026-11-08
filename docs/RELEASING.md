# Releasing Sonoglitch

Sonoglitch is free everywhere. It ships through two channels that differ only in the signing key and in the optional "Support the project" row of Settings, which is controlled by one build-time define:

| Channel | Signed by | Donation link (`DONATION_URL`) |
| --- | --- | --- |
| **GitHub releases** | the repository keystore (see [Contributing](../CONTRIBUTING.md#release-workflow)) | `https://ko-fi.com/danielmfdev` |
| **Google Play** | Google Play App Signing, with the upload key below | none: the build is made without the define and the row is hidden |

Google Play's payments policy restricts apps that ask for donations outside Play's own billing, so the Play build must never be built with `DONATION_URL`. Check the current policy before each submission.

## Versionado y trazabilidad

**El número de build es un contador reservado por subida**, no el número de commits: recompilar el mismo commit dos
veces no cambia nada, y la tienda rechaza el segundo build. Además, **iOS y Android llevan contadores independientes**.

| Campo | Regla | Dónde se aplica |
|---|---|---|
| Nombre de versión | Semántica (`0.1.1`), el mismo en todos los canales y el que muestra la app (`--dart-define=APP_VERSION=`) | `pubspec.yaml`, `--build-name` |
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
- Cada release lleva además `fastlane/metadata/android/{en-US,es-ES}/changelogs/<build>.txt` (como mucho 500 bytes) con el mismo número de build.

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
| 29-oct-2026 | GitHub Releases (repositorio público) | 0.2.0-alpha.2 | 22 | `2c27005` (público `eb8041e`) | `sonoglitch-0.2.0-alpha.2.apk`, Actions, clave de depuración | Publicada (prerelease); la etiqueta 0.2.0-alpha.1 del privado nunca se compiló | no archivados |
| 31-oct-2026 | GitHub Releases (repositorio privado) | 0.2.0-alpha.3 | 23 | `9518d9b` | `sonoglitch-0.2.0-alpha.3.apk`, compilado en local (Actions del privado sin cuota), clave de subida | Publicada (prerelease) | no archivados |
| 31-oct-2026 | GitHub Releases (repositorio público) | 0.2.0-alpha.3 | 23 | `9518d9b` (público `9ebfcc8`) | `sonoglitch-0.2.0-alpha.3.apk`, Actions, clave de subida (secretos de firma cargados en ambos repositorios) | Publicada (prerelease); misma firma que el APK del privado | no archivados |
| 01-nov-2026 | GitHub Releases (repositorio privado) | 0.2.0-alpha.4 | 24 | `5f29da6` | `sonoglitch-0.2.0-alpha.4.apk`, compilado en local (Actions del privado sin cuota), clave de subida | Publicada (prerelease) | no archivados |
| 01-nov-2026 | GitHub Releases (repositorio público) | 0.2.0-alpha.4 | 24 | `5f29da6` (público `f670afd`) | `sonoglitch-0.2.0-alpha.4.apk`, Actions, clave de subida | Publicada (prerelease); misma firma que el APK del privado | no archivados |
| 03-nov-2026 | Google Play (prueba cerrada) | 0.2.0-alpha.4 | 24 | `5f29da6` | `sonoglitch-0.2.0-alpha.4-v24.aab` (SHA-256 `3c639458…f421e5a3`), compilado en local, clave de subida; Play lo firmó con una clave generada por Google | Publicada a las 15:33; inservible tras el cambio de clave de firma (0 instalaciones) | dentro del AAB |
| 03-nov-2026 | Google Play (prueba cerrada) | 0.2.0-alpha.5 | 25 | `bece2ef` | `sonoglitch-0.2.0-alpha.5-v25.aab` (SHA-256 `4080d51c…4236bd78`), compilado en local, clave de subida | En revisión; Play firma con la clave de subida | dentro del AAB |
| 03-nov-2026 | GitHub Releases (repositorio privado) | 0.2.0-alpha.5 | 25 | `bece2ef` | `sonoglitch-0.2.0-alpha.5.apk`, compilado en local (Actions del privado sin cuota), clave de subida | Publicada (prerelease) | no archivados |
| 03-nov-2026 | GitHub Releases (repositorio público) | 0.2.0-alpha.5 | 25 | `bece2ef` (público `4fa548d`) | `sonoglitch-0.2.0-alpha.5.apk`, Actions, clave de subida | Publicada (prerelease); misma firma que el APK del privado y que Google Play | no archivados |
| 08-nov-2026 | Google Play (prueba cerrada) | 0.2.0-alpha.6 | 26 | `3e8f9ed` | `sonoglitch-0.2.0-alpha.6-v26.aab` (SHA-256 `40defb5a…47dbc3e3`), compilado en local, clave de subida; subido con `play-upload.py` | Borrador en el track `alpha`, pendiente de que el propietario lo publique | `mapping.txt` subido; símbolos nativos dentro del AAB |

Todavía no hay ninguna subida a TestFlight. El AAB de la build 19 se compiló en local con la clave de subida
(27-oct-2026, commit `de7defc`) y **no se subió**: quedó obsoleto. Los símbolos nativos van dentro del AAB
(`BUNDLE-METADATA/…/debugsymbols`) y los AAB se archivan fuera del repositorio.

**Clave de firma de Play:** desde el 03-nov-2026 Play firma con la clave de subida (`sonoglitch-upload.jks`, SHA-256
`B6:3C:9E:7D:…:C5:5A:49`), exportada con PEPK en Play Console → Firma de aplicaciones → Cambiar clave. Así la versión
de Play, los APK de GitHub (los dos repositorios) y los AAB tienen la misma firma, y se puede pasar de una a otra sin
desinstalar. No generes otra clave de subida: rompería esa igualdad.

- La compilación de los Android de GitHub sin los cuatro secretos de firma usa la clave de depuración: sirve para
  alphas. Una versión estable los exige (véase el flujo *Release APK*).
- Las etiquetas del repositorio público (`ede33da`…) son instantáneas de una sola vez por versión; las del privado
  apuntan al commit de desarrollo.

## Public and private repositories

Development happens in a private repository. This public repository receives one commit per release, a snapshot of the tagged tree, with the version tag; the development history is not published. `tool/publish/publish_public.ps1 -Tag vX.Y.Z` makes the snapshot from tracked files only, scans it for secrets and pushes it (use `-DryRun` first). Pushing the tag starts the *Release APK* workflow, which builds, signs and publishes the GitHub release. Pull requests to this repository are reviewed here and ported to the private repository by the maintainer.

### GitHub Actions in each repository

Actions minutes are free in the public repository and paid in the private one (a CI run takes about 17 minutes, a release build about 32). The workflows are the same files in both, and each job checks `github.event.repository.private`:

| Workflow | Public repository | Private repository |
| --- | --- | --- |
| *CI* (`ci.yml`) | every push to `main` and every pull request | pull requests (Dependabot's included) and manual runs; pushes to `main` are skipped |
| *Release APK* (`release.yml`) | every `v*` tag | skipped on tag pushes; only a manual run on a tag builds |
| *Pages* (`pages.yml`) | pushes to `main` that change `site/` | skipped (GitHub Pages needs a public repository) |

*CI* ignores changes that only touch `docs/`, `fastlane/`, `site/`, `web/` or Markdown files, and a new run cancels the one in progress on the same branch. Run the three checks locally before pushing to `main` of the private repository: nothing checks those pushes there.

From 24 to 31 October 2026 the private repository had no Actions minutes (a failed payment), so its runs failed within seconds and the private releases were built locally. When the minutes came back, the tag pushes of 0.2.0-alpha.4 and 0.2.0-alpha.5 built for 30 minutes and then failed, because the release made by hand already existed. That is why the private repository no longer builds releases on a tag push.

### Identity in the public repository

Only `Daniel Mont Ferrandiz <dev@mainshai.com>` may appear in the public repository, as author, committer and tagger. The script sets it itself (the release tag is annotated, so it carries a tagger), whatever the global or local git config says; change it for another project with the `PUBLIC_AUTHOR_NAME` and `PUBLIC_AUTHOR_EMAIL` environment variables. Before pushing, the script checks that:

- the new commit and the tag have exactly that identity;
- no Gmail address appears in the identity, the commit message, the tag or any file of the snapshot (the secret scan includes a Gmail pattern, so `-DryRun` catches it too).

Any failure stops the script before the push. If a kept clone in `-WorkDir` is used, it is first brought to the remote `main`. Do not commit to the public repository by hand or from the GitHub web editor with a personal account: those commits use whatever identity that account has and the check does not see them.

Tests: `python -m unittest discover -s tool/publish` (Windows, PowerShell). They run the real script against a temporary private repository and a bare "public" one, with a personal identity in the global git config, and mutating the script so it no longer fixes the identity makes them fail.

### Release flow: test privately first, then publish

1. Commit `chore: release`, bump `pubspec.yaml` and `CHANGELOG.md`, and create the tag `vX.Y.Z` in the private repository. Push the commit and the tag there (no workflow runs), build the APK locally with the upload key and publish it as a private prerelease, as described in [GitHub releases](#github-releases).
2. Install that APK on a phone and test it (it carries the upload key signature, so it updates over the previous one).
3. Only if it is good, run `tool/publish/publish_public.ps1 -Tag vX.Y.Z` (first with `-DryRun`). The public workflow builds the public release from the snapshot of the same tree.
4. Add the row to the register of uploads in *Versionado y trazabilidad*.

The public repository needs the four signing secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), and the private one keeps them for a manual run of *Release APK*, always with the **same** upload key, so that every APK has the same signature and installs over the previous one. Without them the workflow signs with a debug key that is new on every run: only acceptable for prereleases, and each build must then be uninstalled before the next one. Set them with `gh secret set <NAME> --repo <owner/repo> --body <value>`, reading the values from `android/key.properties` and the `.jks` without printing them. Never commit or paste them.

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

**Never publish or upload this APK. Play and GitHub release builds must
never pass `SONOGLITCH_SCREENSHOTS=true`.** The section is absent by default.

**Photo source.** To use a JPEG or PNG instead of the emulator camera, launch
the screenshot build once (to create its external files directory), then push
the image to this fixed app-private path. PNG content is accepted even though
the destination filename ends in `.jpg`:

```sh
adb push "photo.jpg" /sdcard/Android/data/es.sonoglitch.app/files/screenshot_source.jpg
adb shell am force-stop es.sonoglitch.app
adb shell monkey -p es.sonoglitch.app -c android.intent.category.LAUNCHER 1
```

Settings shows whether the photo source was selected at startup and its path.
The live viewfinder uses an aspect-preserving YUV420 preview (up to 640 pixels
on the long side, about 30 fps); capture, result and compare use the same photo
with the real effects. EXIF is baked into the pixels once, and landscape photos
stay landscape. Still captures retain the source resolution before the normal
4096-pixel still decode/export limits. Flipping keeps the same photo. Remove
the file with `adb shell rm /sdcard/Android/data/es.sonoglitch.app/files/screenshot_source.jpg`
and restart to restore the camera. Without the screenshot define or the file,
the normal camera is used. On iOS the fixed filename is in the app Documents
directory instead (copy it into the simulator app container).

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
- Privacy policy URL: `https://sonoglitch.mainshai.com/privacy/` (English; source: `docs/legal/politica-privacidad.en.md`).
- Contact email: `sonoglitch@mainshai.com` (forwards to the developer mailbox; the privacy policy, SECURITY.md and the code of conduct keep `dev@mainshai.com`). Website: `https://sonoglitch.mainshai.com`.
- Price: free, no ads, no in-app purchases.
- Assets that must be made on a device: a 512×512 icon, a 1024×500 feature graphic and at least two phone screenshots.

### Data safety form

The app collects and shares nothing: answer *No* to "Does your app collect or share any of the required user data types?". Camera and microphone are used for on-device processing only (see the [privacy policy](legal/politica-privacidad.en.md)); audio is never recorded, stored or sent, and the release build has no `INTERNET` permission. Declared permissions: `CAMERA`, `RECORD_AUDIO`. Content rating: answer the questionnaire in Play Console (no user-generated content, no location sharing, no purchases); do not assume the outcome. The photo or report the user chooses to share goes to another app through the system share sheet at the user's request, which Play's Data safety rules treat as user-initiated, not as the app sharing data; check the current wording of those rules when filling the form.

## F-Droid

Sonoglitch is not published on F-Droid (decided on 2026-11-08): it ships on Google Play and GitHub only. The recipe was removed from the repository.

## GitHub releases

In the public repository, push a `v*` tag (`publish_public.ps1` does it). The [workflow](../.github/workflows/release.yml) builds, signs with the repository secrets and publishes the APK with its checksum, including the Ko-fi link. In the private repository a tag push does not build (see [GitHub Actions in each repository](#github-actions-in-each-repository)); build locally with the same command and `--build-number=N`, copy the APK to `sonoglitch-<version>.apk`, write its checksum with `sha256sum`, and create the release with `gh release create v<version> <apk> <checksum> --target main --prerelease` (use `--prerelease` for every alpha). A local build without `android/key.properties` is signed with the debug key, which is only acceptable for private test builds; stable releases must use the real key.
