# Plan de pruebas previo a la publicación de Sonoglitch

*Versión del plan: 2026-10-28. Base de código: `main` en `0.1.0+21` (`pubspec.yaml`); la primera subida a Google Play usará un build mayor que 21 (docs/RELEASING.md). Resultados: `docs/qa/registro-de-pruebas.md`.*

Este plan se ejecuta antes de enviar la app a Google Play (prueba cerrada y producción) y al App Store (TestFlight y revisión). Está escrito a partir del código actual (`lib/`, `android/`, `ios/`, `test/`) y de `docs/ARCHITECTURE.md`, `docs/legal/politica-privacidad.en.md`, `docs/IOS_STATUS.md` y `docs/RELEASING.md`. Lo que no se ha podido comprobar en el código está marcado como **verificar**.

Convenciones:

- **Prioridad:** **P0** bloquea la publicación; **P1** debe arreglarse antes de producción (puede pasar a prueba cerrada/TestFlight con nota); **P2** se documenta y puede esperar.
- **Entornos:** `EMU` = emulador Android `Sonoglitch_Pixel` (imagen sin Play Store usable) · `EMU-PS` = emulador con imagen Play Store y cuenta Google del grupo de testers · `PX` = Pixel 10 Pro real · `LOW` = Android antiguo o de gama baja, si se consigue · `SIM` = simulador iOS en el Mac · `IPH` = iPhone real por Xcode o TestFlight · `PC` = comprobación estática en el ordenador (APK/AAB, manifiesto, repositorio).
- **Modo:** `A` = lo puede automatizar el asistente desde Windows con `adb`/scripts · `M` = manual (persona con el dispositivo) · `A+M` = el asistente prepara y la persona confirma mirando la pantalla.
- Los textos de la interfaz se citan en español tal como están en `lib/l10n/app_es.arb`; entre paréntesis el inglés cuando ayuda a localizar la cadena en `app_en.arb`. Las claves de widget (`vf-shutter`, `res-compare`…) son las de `lib/features/`.

---

## 0. Lo que necesito de ti

Qué tienes que aportar o hacer tú, y por qué. **Yo nunca escribo tus contraseñas ni inicio sesión por ti**: cada inicio de sesión lo haces tú en el dispositivo o en el navegador.

| # | Qué | Para qué sirve | Cuándo |
|---|---|---|---|
| 1 | **El Pixel 10 Pro con depuración USB o inalámbrica activada** y a mano durante las fases B y D (unas 3-4 h en total, repartibles). | Es el único sitio donde se pueden juzgar cámara real, micrófono, sensores, orientación, rendimiento de los shaders, exportación de 12-24 MP, batería y temperatura. Con cable puedo instalar, sacar capturas y logs con `adb`; sin cable lo haces tú siguiendo los casos marcados `M`. | Fase B |
| 2 | **Un Android viejo o barato** (prestado vale), Android 10 u 11 a ser posible. | Dos cosas que el Pixel no puede comprobar: guardar en Android 10 (sin álbum `Sonoglitch`, `lib/export/export_service.dart` `_galleryAlbum`) y la fluidez con GPU floja. Si no hay, se marca `LOW` como «no probado» y sigue siendo publicable, pero con riesgo. | Fase B, opcional |
| 3 | **Que decidas si la prueba cerrada de Play se hace con una imagen de emulador con Play Store.** Si sí, hay que crear un AVD nuevo: el actual `Sonoglitch_Pixel` tiene `PlayStore.enabled=no` en su `config.ini` aunque use la imagen `google_apis_playstore` (verificar si la tienda arranca). En ese emulador **tú** inicias sesión en Play Store con una cuenta Google que esté en el grupo de testers. | Sin esa sesión no se puede probar la ruta de instalación «enlace de prueba cerrada → Play Store → instalar», que es lo que verán los 12 testers. Todo lo demás no necesita cuenta. | Fase D |
| 4 | **Cuenta de Google Play Console** (ya verificada): subir el AAB, rellenar Data safety, clasificación de contenido, ficha y crear la prueba cerrada con el grupo de Google de 12 testers. Lo haces tú en el navegador; yo te paso los textos (`fastlane/metadata/android/`, `.local/play/PLAY_CONSOLE.es.md`). | Son acciones irreversibles o de cuenta, nunca las hago yo. | Fase D |
| 5 | **Cuenta de Apple Developer activa** (**aceptada el 28-oct-2026**; falta registrar `es.sonoglitch.app` y crear la app en App Store Connect) y **sesión de Xcode con tu equipo** en el Mac. | Sin equipo de firma no se puede compilar para iPhone real ni subir a TestFlight. Tú inicias sesión en Xcode y en App Store Connect. | Fase C |
| 6 | **Un iPhone real (iOS 16 o superior)** con tu Apple ID y, para TestFlight, la app TestFlight instalada con ese Apple ID invitado como tester. | El simulador iOS **no tiene cámara** y **no puede ejecutar builds de TestFlight**; en él solo se prueban permisos (parcialmente), navegación, idioma, accesibilidad y maquetación. | Fase C |
| 7 | **El Mac disponible una sesión de 2-3 h** con Flutter 3.47.7, Xcode y CocoaPods instalados. | iOS nunca se ha compilado ni ejecutado (`docs/IOS_STATUS.md`). Lo primero es `flutter pub get`, `cd ios && pod install` y un `flutter run` real. | Fase C |
| 8 | **Los dos artefactos de la versión candidata**: el APK/AAB firmados con la clave de subida (`tool/release/build_play_bundle.ps1`) y la prerelease privada en GitHub. Para iOS, el `.ipa` sale del Mac. | Las pruebas se hacen sobre el build exacto que se sube, no sobre «el último que compiló». Si cambia el código, se repiten los P0 (sección 6). | Fase A |
| 9 | **Decisiones de producto pendientes antes de congelar el build:** si se activan los 6 estilos ocultos (`isPlaceholder: true` en `lib/effects/style_definition.dart`), si el subtítulo de «Línea de contexto» debe seguir mencionando «presión» (ver dudas al final), y si el icono y la gráfica de Play son definitivos. | Cambiarlos después obliga a repetir la regresión. | Antes de la fase A |
| 10 | **Escenas y sonidos de prueba** en la vida real: una habitación en silencio, una fuente de ruido continuo (altavoz con música o aspiradora), un aplauso/grito, una ventana luminosa y un rincón oscuro, y espacio para agitar y girar el móvil. | Son los estímulos de los casos AMB-* y CAP-*; en el emulador solo se simulan a medias. | Fase B |
| 11 | **Tiempo tuyo estimado:** fase A (Windows) ~0,5 h de confirmaciones visuales; fase B (Pixel) ~3 h; fase C (Mac) ~3 h; fase D (tiendas) ~2 h más los 14 días de prueba cerrada. | Es el coste real del plan; lo demás lo adelanto yo. | — |

**Pruebas que NO necesitan ningún inicio de sesión** (ni Google ni Apple): todas las de instalación por `adb`/Xcode, permisos, cámara, visor, señales, estilos, captura, resultado, guardar/compartir, ajustes, idioma, accesibilidad, rendimiento, robustez, privacidad y actualización (secciones 4.1 a 4.17). La app no tiene cuentas ni login propio (`lib/main.dart`: onboarding → visor, sin red). **Solo necesitan sesión:** la ruta de instalación desde Play Store de la prueba cerrada (PLAY-10, PLAY-11), la subida y configuración en Play Console (PLAY-01…09), la firma y subida a TestFlight en Xcode/App Store Connect (IOS-10…14) y la instalación desde TestFlight en el iPhone (IOS-15).

---

## 1. Objetivos, alcance y criterio de salida

### 1.1 Objetivos

1. Confirmar que la versión candidata hace lo que dicen la ficha de la tienda (`fastlane/metadata/android/*/full_description.txt`) y la política de privacidad (`docs/legal/politica-privacidad.en.md` y su traducción `docs/legal/politica-privacidad.md`), sin inventar nada que la app no haga.
2. Confirmar la promesa de privacidad en el artefacto real: sin permiso `INTERNET`, sin ficheros de audio, sin secretos, sin copias de seguridad, sin rumbo/ritmo/calendario en los diagnósticos.
3. Encontrar los fallos que la batería de tests no puede ver: cámara física, micrófono, sensores, GPU, memoria con fotos de 12-24 MP, galería, compartir, ciclo de vida.
4. Dejar iOS en un estado conocido: compila, arranca, cámara y permisos funcionan en un iPhone, y se sabe qué falta (`docs/IOS_STATUS.md`).
5. Tener las respuestas de Play Console y App Store Connect comprobadas contra el código antes de enviarlas.

### 1.2 Alcance

**Entra:** la app Android (APK de GitHub y AAB de Play) y la app iOS (build de Xcode y TestFlight) de la misma versión semántica; las fichas de tienda; el flujo de instalación de los testers.
**Queda fuera:** F-Droid (su servidor construye y revisa por su cuenta; solo se comprueba que el manifiesto que ve es el mismo), la web de GitHub Pages, los seis estilos ocultos (salvo decisión del punto 0.9), vídeo, cuentas (no existen).

### 1.3 Lo que ya cubren los tests automáticos (no se repite a mano)

`flutter test` ejecuta ~700 declaraciones `test`/`testWidgets` en 109 ficheros (más de 1100 casos contados por el runner según `.local/STATUS.md`). Cubren, sin dispositivo:

| Área | Ficheros | Qué queda demostrado |
|---|---|---|
| Señales ambientales | `test/ambient/*` (noise, light, motion, smoothed_value, spectrum, manual mode, signature/*, sensitive_signals, signature_lanes) | Normalización, suelo/techo adaptativos, ráfagas, fusión de movimiento, modo manual, carriles de la firma, que la firma no se serializa (`sensitive_signals_test.dart`) |
| Cámara (lógica) | `test/camera/*` | Cola de operaciones, pausa/reanudación, generaciones de stream, conversión YUV/BGRA, EXIF, orientación por gravedad (`capture_orientation_test.dart`), limpieza del fichero del still |
| Efectos y shaders | `test/effects/*` | Contrato de 28 floats, compilación real de los 6 `.frag` y de los oráculos, respuesta a cada control y a cada carril, cotas de desplazamiento y retención, determinismo por semilla |
| Exportación | `test/export/*` | Planes de recorte y calidad, límites de textura y fallback (`photo_export_test.dart`), composición de banda/póster y modos de lecturas, PNG sin pérdidas, encoder JPEG con canal falso, limpieza de temporales |
| Pantallas (widgets) | `test/features/*` | Onboarding con pasarela falsa, visor (maquetación 320x568, leyenda, hint, manual, momento, ciclo de vida con cámara falsa), hoja de estilos, resultado (selectores, caché, antes/después, resolución completa con exportador falso), ajustes (32 tests) |
| Idioma y tema | `test/l10n/localisation_test.dart`, `test/theme/*` | Que es/en tienen las mismas claves, contraste de los tokens, loader y fringe con animaciones reducidas |

**Lo que solo un dispositivo o emulador puede verificar** (y por eso está en este plan): permisos reales del sistema, cámara física (orientación, espejo, cambio frontal/trasera, otra app que toma la cámara), micrófono y sensores reales (incl. que `noise_meter` y `SpectrumPlugin` abran el micro a la vez), rendimiento de los shaders en GPU real, memoria con 12-24 MP, galería (`Gal`) y hoja de compartir, logcat/consola, instalación/actualización/firma, manifiesto fusionado, TalkBack/VoiceOver, y todo iOS.

### 1.4 Escala de severidad

| Sev. | Definición | Ejemplo |
|---|---|---|
| **S1 Crítico** | Crash, pérdida de la foto, violación de privacidad (audio escrito, red, permiso no declarado), la app no instala o no arranca, incumplimiento de tienda que provoca rechazo. | La app muere al pulsar Guardar en Android 10 |
| **S2 Mayor** | Una función principal no funciona o da un resultado incorrecto sin alternativa. | Foto girada 90° al disparar en horizontal |
| **S3 Menor** | Funciona pero con defecto visible, texto cortado, inconsistencia, lentitud tolerable. | Desbordamiento de un subtítulo al 200 % de escala |
| **S4 Cosmético** | Detalle estético o de redacción. | Tilde que falta |

### 1.5 Criterio go / no-go

**GO a prueba cerrada / TestFlight** si:
- Todos los casos **P0** del entorno correspondiente (Android: `EMU`+`PX`; iOS: `IPH`) están en **PASS**, o su fallo tiene corrección verificada con re-test.
- No hay defectos abiertos de severidad **S1**.
- `dart format --output=none --set-exit-if-changed .`, `flutter analyze` y `flutter test` pasan sobre el commit etiquetado (los ejecuta el líder con `heavy.sh`; el workflow *Release APK* ya los exige).
- Las comprobaciones de privacidad PRIV-01…PRIV-12 están en PASS.

**GO a producción** si además:
- Todos los **P1** en PASS o cerrados como «aceptado con nota» por ti.
- La prueba cerrada ha durado los 14 días con los 12 testers y el informe previo al lanzamiento de Play (pre-launch report) no muestra crashes ni avisos de accesibilidad bloqueantes.
- Los P2 abiertos están anotados en `CHANGELOG.md` (Unreleased) o en issues.

**NO-GO** con cualquier S1 abierto, con un P0 sin ejecutar («no probado» cuenta como fallo para P0), o si el artefacto probado no es el que se sube.

---

## 2. Matriz de entornos

| Entorno | Qué es | Qué SÍ se puede verificar | Qué NO se puede verificar (o solo a medias) |
|---|---|---|---|
| **EMU** — `Sonoglitch_Pixel` (`~/.android/avd/Sonoglitch_Pixel.avd`): Android 16 (`android-36`), imagen `google_apis_playstore` x86_64, perfil Pixel 9 Pro, cámara trasera `virtualscene`, frontal `emulated`, sensores luz/magnético/presión/giroscopio virtuales, micrófono del host | Instalación por `adb` del APK (incluye x86_64: el workflow compila `android-arm64,android-x64`); permisos conceder/denegar/revocar/«solo esta vez» con `pm grant/revoke` y los diálogos; navegación completa; cambio frontal/trasera; ciclo de vida (home, bloqueo, llamada simulada con `adb emu gsm call`, pantalla dividida); inyección de luz/aceleración/magnetómetro/presión con `adb emu sensor set`; sonido por el micrófono del host; idioma, escala de fuente 200 %, TalkBack, animaciones reducidas, tamaños de pantalla (`wm size 320x568`); manifiesto fusionado; capturas y grabaciones | Rendimiento real de los shaders (GPU emulada por SwiftShader/host), calidad del micrófono, orientación por gravedad al girar el aparato (solo con sensor virtual), foto de 12-24 MP a tamaño nativo (la cámara virtual es pequeña — verificar su resolución máxima), batería y temperatura, Play Store (ver nota en 0.3) |
| **EMU-PS** — AVD nuevo con Play Store habilitado y cuenta Google del grupo de testers (la inicias tú) | Ruta de instalación de la prueba cerrada: aceptar invitación → Play Store → instalar → actualizar; que la ficha se vea; informe de firma de Play (la app la firma Play, no la clave de subida) | Lo mismo que EMU en cuanto a cámara, GPU y sensores |
| **PX** — Pixel 10 Pro real (Android 16, `.local/STATUS.md`: stream 720x480 ~29 fps, foto 3072x4080 12,5 MP en alpha.8) | Todo lo físico: cámara, orientación al girar, espejo frontal, micrófono (dB reales, dos lectores a la vez), luz en lux, movimiento, brújula, barómetro, rendimiento p50/p95, memoria, batería, temperatura, galería en Android 11+, compartir a Instagram/WhatsApp, actualización sobre la versión anterior con la misma firma, TalkBack real | Android 10 (no se puede instalar); gama baja |
| **LOW** — Android 10/11 de gama baja (si hay) | Guardar sin álbum en Android 10; fluidez con GPU floja; memoria al exportar en Máxima; pantallas pequeñas reales | Si no se consigue, se anota como «no probado» y el riesgo queda documentado |
| **SIM** — simulador iOS en el Mac (iPhone con iOS 16+) | Que el proyecto compila con CocoaPods y Xcode; arranque; textos de permisos (`NSMicrophoneUsageDescription` sí se puede probar; `NSCameraUsageDescription` aparece pero no hay imagen); navegación hasta el visor con error de cámara controlado; idioma, Dynamic Type, VoiceOver, tamaños de pantalla | **Sin cámara** (el visor mostrará «No se ha podido abrir la cámara.» o similar — verificar), sin micrófono real fiable, sin sensores, sin TestFlight, sin rendimiento |
| **IPH** — iPhone real por Xcode (desarrollo) y por TestFlight | Todo iOS: permisos cámara/micro/fotos, cámara frontal/trasera, orientación, guardar en Fotos con álbum `Sonoglitch`, compartir, ciclo de vida, rendimiento con los fallbacks Dart (JPEG por Dart, sin espectro, sin lux), TestFlight | Nada relevante queda fuera; es el entorno de referencia iOS |
| **PC** — comprobaciones estáticas en Windows/Mac | Manifiesto fusionado del AAB/APK, permisos, firma, tamaño, ABIs, `Info.plist`, ausencia de secretos, textos de tienda, política de privacidad publicada | Comportamiento en ejecución |

---

## 3. Preparación

### 3.1 Builds a usar

| Canal | Cómo se obtiene | Qué se prueba con él |
|---|---|---|
| **APK de prerelease privada** (`sonoglitch-<versión>.apk` del workflow *Release APK* del repo privado, firmado con la clave de subida si los 4 secretos están puestos; si no, clave de depuración nueva en cada run) | Etiquetar `vX.Y.Z` en el repo privado (docs/RELEASING.md «Release flow»). Descargar el `.apk` y su `.sha256`; comprobar el hash. | Todo Android en EMU y PX (fases A y B). Es un release build (sin `INTERNET`, sin triple toque). |
| **AAB de Play** (`build/app/outputs/bundle/release/app-release.aab`) | `tool/release/build_play_bundle.ps1` en Windows (sin `DONATION_URL`). El script imprime el manifiesto fusionado. | Comprobaciones PRIV/PLAY estáticas y la subida a Play. Para instalarlo en un dispositivo: `bundletool build-apks --mode=universal` y `bundletool install-apks` (verificar que `bundletool` está en el SDK) o directamente desde la pista interna de Play. |
| **Build de depuración con panel** (`flutter run --dart-define=SONOGLITCH_DEBUG=true`) | Solo para preparar escenas y leer el panel con triple toque. **No** sirve para los casos PRIV (tiene `INTERNET` por `android/app/src/debug/AndroidManifest.xml`). | Soporte durante las fases A y B |
| **Build manual de efectos** (`--dart-define=SONOGLITCH_MANUAL=0.9,0.1,0`) | Arranca en modo manual con esos valores (`lib/app_config.dart`). | Capturas reproducibles y VF-* en el emulador |
| **iOS** | En el Mac: `flutter pub get`, `cd ios && pod install`, `flutter run --release -d <iPhone>`; para TestFlight, `flutter build ipa --build-name=X.Y.Z --build-number=N --dart-define=APP_VERSION=X.Y.Z` y subir con Xcode Organizer o Transporter. Sin `DONATION_URL` (misma regla de pagos que Play — verificar la política de Apple 3.2.1 sobre donaciones). | Fase C |

Reglas: anota en el registro el build exacto (versión, `versionCode`/`CFBundleVersion`, commit, hash del fichero). En **Ajustes → Acerca de** la app muestra «Versión {APP_VERSION}» (`settingsVersion`), que debe coincidir.

### 3.2 Instalación

```sh
# Emulador (desde Windows; adb en <carpeta del SDK de Android>/platform-tools)
emulator -avd Sonoglitch_Pixel -no-snapshot-load      # arranque limpio cuando se prueba el primer uso
adb devices
adb install -r sonoglitch-X.Y.Z.apk                   # -r conserva datos (caso de actualización)
adb uninstall es.sonoglitch.app                        # primer uso limpio
adb shell pm list packages | grep sonoglitch           # debe salir es.sonoglitch.app y ningún id antiguo
```

Pixel por cable o por depuración inalámbrica (`adb pair`, `adb connect`): mismos comandos. Alternativa sin cable: descargar la prerelease desde el navegador del móvil con tu sesión de GitHub (repo privado) e instalarla («permitir apps desconocidas» para el navegador). Si el APK anterior se firmó con otra clave, hay que desinstalar primero (Android rechaza la actualización: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

### 3.3 Captura de logs y diagnósticos

- **Panel de diagnóstico de la app:** *Ajustes → Solución de problemas → Diagnóstico* (interruptor persistido, `settings.diagnostics`). En builds con `SONOGLITCH_DEBUG=true`, también triple toque sobre la imagen del visor. Líneas del panel (`lib/debug/debug_hud.dart`): `noise … db … base … burst`, `light … luma … lux`, `motion … accel … dir`, `bass mid treble`, `sources scene gyro accel`, `stream WxH fps conv ms drop`, `style <id> v<versión>`, `<plataforma> <SO> <modelo>`, `capture <tiempos>`. Botones **Copiar informe** (JSON al portapapeles) y **Compartir registros** (JSON + fichero de log), interruptor **Manual** con tres deslizadores.
- **Informe desde Ajustes:** *Solución de problemas → Exportar informe de diagnóstico* comparte el JSON con las últimas 300 líneas del anillo en memoria (`DiagnosticExporter`).
- **logcat (Android):** `adb logcat -c && adb logcat -v time > logcat_<caso>.txt` y en otra consola los pasos; filtros útiles: `adb logcat -v time | grep -iE "flutter|sonoglitch|CameraX|Camera2|AudioRecord|AudioFlinger|E/|F/"`. Crashes nativos: `adb logcat -b crash`. El fichero de log rotatorio de la app (`DebugLog`, 512 KiB x 3) está en el almacenamiento privado; en un release no depurable no se lee con `run-as`: usa **Compartir registros**.
- **iOS:** consola de Xcode durante `flutter run`; para builds de TestFlight, *Window → Devices and Simulators → Open Console* o la app Consola del Mac filtrando por `Runner`/`Sonoglitch`; crashes en *Organizer → Crashes* y en TestFlight.
- **Redacción:** el log y los informes redactan rutas absolutas (`lib/debug/redact_paths.dart`), pero revisa modelo y excepciones antes de pegar un informe en un sitio público.

### 3.4 Reinicio del estado

- Borrado total: `adb shell pm clear es.sonoglitch.app` (preferencias `settings.*`, log, caché de temporales `sonoglitch_*`). En iOS: desinstalar la app.
- Permisos sin borrar datos: `adb shell pm revoke es.sonoglitch.app android.permission.CAMERA` / `RECORD_AUDIO`; `adb shell pm grant …`; «Preguntar siempre» (solo esta vez) se elige en el diálogo del sistema o en *Ajustes del sistema → Apps → Sonoglitch → Permisos*. Reiniciar permisos de todas las apps en el emulador: `adb shell pm reset-permissions`.
- Volver a ver el consejo del visor: *Ajustes → Mostrar los consejos otra vez*.
- Caché de temporales: `adb shell ls /data/data/es.sonoglitch.app/cache` no es accesible en release; observa el tamaño en *Ajustes del sistema → Apps → Sonoglitch → Almacenamiento → Caché* antes y después.

### 3.5 Datos y escenas de prueba

- **Escena de referencia** para comparar estilos entre builds: una cara o un texto grande a 1 m, con una ventana al lado (contraste). Se fotografía con los seis estilos y las tres calidades. Para el emulador, la cámara `virtualscene` muestra una habitación 3D; en *Extended controls (⋯) → Camera* se pueden añadir imágenes a las paredes (una foto con texto y una cara ayudan a juzgar el reconocimiento del sujeto).
- **Sonido al emulador:** el micrófono virtual usa la entrada de audio del host (*Extended controls → Microphone → «Virtual microphone uses host audio input»*, activado). Reproduce en el PC un tono de 100 Hz, otro de 1 kHz y otro de 8 kHz (para `bass`/`mid`/`treble`), un metrónomo a 120 BPM (para el pulso) y ruido rosa a dos volúmenes; o habla y aplaude delante del micrófono del PC. Si el host tiene salida y entrada separadas, un cable de audio virtual (VB-Cable) manda la reproducción al micrófono.
- **Sensores en el emulador** (consola `adb emu`, o *Extended controls → Virtual sensors*):
  - Luz: `adb emu sensor set light 5` (oscuro) · `adb emu sensor set light 2000` (muy luminoso). El panel debe mostrar `lux`.
  - Aceleración/orientación: `adb emu sensor set acceleration 0:9.8:0` (vertical) · `9.8:0:0` (horizontal, lado izquierdo arriba) · `0:0:9.8` (plano) · *Virtual sensors → Rotate* para girar con el ratón.
  - Giroscopio: `adb emu sensor set gyroscope 0:0:2`.
  - Magnetómetro (rumbo): `adb emu sensor set magnetic-field 0:40:-20` y variar el eje para cambiar el rumbo.
  - Presión: `adb emu sensor set pressure 950` (la línea de contexto imprime `hPa`).
  - Listar: `adb emu sensor status`.
- **Sensores en el simulador iOS:** solo *Features → Face ID/Shake*; no hay luz, magnetómetro ni barómetro; la cámara no existe. Lo que depende de sensores en iOS se prueba en IPH.
- **Fotos de referencia para la galería:** ninguna; la app no lee fotos ajenas.

### 3.6 Herramientas de medida (Android)

```sh
adb shell dumpsys gfxinfo es.sonoglitch.app reset && sleep 60 && adb shell dumpsys gfxinfo es.sonoglitch.app   # janky frames, percentiles
adb shell dumpsys meminfo es.sonoglitch.app                                                                     # PSS total, Graphics, Native
adb shell dumpsys batterystats --reset ; (sesión de 15 min) ; adb shell dumpsys batterystats es.sonoglitch.app
adb shell dumpsys thermalservice                                                                                  # estado térmico
adb shell am start -W es.sonoglitch.app/io.github.dferrandizmont.sonoglitch.MainActivity                        # tiempo de arranque (verificar el nombre completo de la actividad en el manifiesto fusionado)
adb exec-out screencap -p > <caso>.png ; adb shell screenrecord --time-limit 60 /sdcard/<caso>.mp4 && adb pull /sdcard/<caso>.mp4
```

En el Pixel, `flutter run --profile` + DevTools (*Performance*) da el frame time p50/p95 del hilo raster, que es la medida que pide `docs/ARCHITECTURE.md` («compara p50/p95 contra alpha.15 en el mismo teléfono y escena»).

---

## 4. Casos de prueba

Formato: **ID · P · Entorno · Modo** — Precondición → Pasos → Esperado. Todos los casos presuponen la versión candidata salvo que se diga otra.

### 4.1 Instalación, primer arranque y permisos (INS)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| INS-01 | P0 | EMU, PX | A | Instalación limpia: `adb uninstall` previo → `adb install`. Esperado: `Success`; `pm list packages` muestra solo `es.sonoglitch.app`; icono «Sonoglitch» en el lanzador (`android:label`), icono adaptativo con fondo `ic_launcher_background` y variante monocroma (tema Material You). |
| INS-02 | P0 | EMU, PX, IPH | M | Primer arranque: pantalla de onboarding con el titular «A camera that lets the place distort the photo»/versión es, la frase de la idea y la tarjeta con icono de micrófono tachado y el texto de privacidad; un solo botón «Permitir cámara y micrófono». Nada se corta en 320x568. |
| INS-03 | P0 | EMU, PX, IPH | M | Conceder ambos permisos desde el botón: aparecen dos diálogos del sistema (cámara y luego micrófono); al aceptar ambos se pasa directamente al visor con imagen y efecto. Ninguna pantalla intermedia. |
| INS-04 | P0 | EMU, PX | M | Denegar cámara (una vez): el onboarding muestra «The camera permission is needed to take a photo.» (texto rojo, `onboardingCameraDenied`) y el botón «Permitir cámara y micrófono» vuelve a pedirla. |
| INS-05 | P0 | EMU, PX | M | Denegar cámara permanentemente («No volver a preguntar»/segunda negativa en Android 11+): texto «Permiso denegado. Actívalo en los ajustes del sistema para continuar.» y botón «Abrir ajustes del sistema» que abre la página de la app; al conceder allí y volver, la app re-comprueba (`_openSettings → _check`) y entra al visor sin reiniciar. |
| INS-06 | P0 | EMU, PX, IPH | M | Conceder cámara y denegar micrófono: aviso «Sin micrófono: el ruido se queda en cero y la foto solo muestra la luz y el movimiento.» y botón «Continuar sin micrófono». Al continuar, el visor funciona, el medidor de ruido está a 0 y el panel muestra `db --`. Hacer una foto: la banda de sonido imprime ruido 0 y bandas neutras (verificar cómo se imprimen las bandas sin micrófono). |
| INS-07 | P1 | EMU, PX | M | «Solo esta vez» (Android 11+) para el micrófono: conceder «solo esta vez», usar la app, cerrarla por completo (`am force-stop`), reabrir. Esperado: el onboarding vuelve a pedir el micrófono (o muestra «Continuar sin micrófono»), nunca un crash ni un visor sin efecto por un stream de audio fallido. |
| INS-08 | P0 | EMU, PX | A+M | Revocar en caliente: con el visor abierto, `adb shell pm revoke es.sonoglitch.app android.permission.CAMERA`. Esperado: Android mata el proceso (comportamiento del sistema); al reabrir, la app muestra el onboarding pidiendo la cámara, no una pantalla negra. Repetir con `RECORD_AUDIO`. |
| INS-09 | P1 | EMU, PX | M | Permisos ya concedidos en un segundo arranque: la app salta el onboarding (`_check` → `onContinue(true)`) y abre el visor directamente, sin parpadeo de la pantalla de permisos más allá del spinner. |
| INS-10 | P1 | EMU | A | El onboarding con el botón ocupado (`_busy`): pulsar varias veces rápido «Permitir…» mientras el diálogo del sistema está abierto no abre dos diálogos ni duplica navegación. |
| INS-11 | P1 | PX | M | Idioma del sistema en español: todos los textos del onboarding en español (`app_es.arb`); en inglés, en inglés; otro idioma (p. ej. francés) cae al inglés (`supportedLocales`). |
| INS-12 | P0 | IPH | M | iOS: los diálogos del sistema muestran exactamente los textos de `Info.plist` (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`). Están solo en inglés aunque el iPhone esté en español (no hay `InfoPlist.strings`); anotar como P2 de localización (IOS-04). |
| INS-13 | P0 | IPH | M | iOS, denegar micrófono y «Continuar sin micrófono»: el visor funciona; `permission_handler` devuelve `permanentlyDenied` en iOS tras una negativa, así que el botón «Abrir ajustes del sistema» debe llevar a Ajustes → Sonoglitch. |
| INS-14 | P2 | SIM | M | Simulador: el onboarding aparece y los diálogos de permiso se pueden aceptar; al entrar al visor, sin cámara, la app muestra «No se ha podido abrir la cámara.» (`viewfinderCameraError`) y no se cuelga ni muestra pantalla negra indefinida (verificar el comportamiento exacto). |

### 4.2 Cámara y ciclo de vida (CAM)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| CAM-01 | P0 | PX, IPH | M | Vista previa: imagen con efecto en < 2 s tras conceder permisos; sin franjas ni colores invertidos (conversión YUV420 en Android, BGRA en iOS, `lib/camera/frame_converter.dart`); panel `stream` ~720x480 y `fps` cercano a 30 (Pixel: 29,4 en alpha.8). |
| CAM-02 | P0 | EMU, PX, IPH | M | Cambiar de cámara (`vf-flip`, tooltip «Cambiar de cámara»): la frontal aparece espejada como un espejo en el visor; la foto resultante NO está espejada en el texto (verificar la decisión: `forPhotoTurns(mirrorX)` negó el eje de la firma; comprobar que un cartel con letras se lee en la foto o anotar el comportamiento) y la orientación es correcta. Volver a la trasera. Hacerlo 10 veces seguidas: sin crash, `conv` estable. |
| CAM-03 | P0 | PX, IPH | M | Orientación del disparo (bug real de alpha.8): la UI está bloqueada en vertical (`SystemChrome.setPreferredOrientations([portraitUp])`). Sostener el móvil en horizontal (lado izquierdo arriba) ≥ 0,5 s y disparar; luego el otro lado; luego boca abajo. Esperado: la foto exportada sale «con el cielo arriba» en los 4 casos (`CaptureOrientationTracker`, 400 ms de estabilidad). El póster y la banda se componen alrededor de la foto girada. |
| CAM-04 | P1 | PX | M | Móvil plano sobre la mesa (gravedad en z) y disparar: no se gira la foto (mantiene la última pose, `capture_orientation.dart`); sin excepciones en el log. |
| CAM-05 | P1 | EMU | A | Emulador: `adb emu sensor set acceleration 9.8:0:0`, esperar 1 s, disparar → foto girada en consecuencia; `0:9.8:0` → vertical. Automatizable comparando el ancho/alto del fichero exportado. |
| CAM-06 | P0 | EMU, PX, IPH | M | Fondo/primer plano: con el visor activo, botón Home, esperar 10 s, volver. Esperado: la vista previa se reanuda sola (`didChangeAppLifecycleState → _syncCamera`), los medidores vuelven a moverse, el historial ambiental se ha vaciado (no hay salto), sin «Capturing…» colgado. Repetir 5 veces. |
| CAM-07 | P0 | PX, IPH | M | Bloqueo de pantalla con la app abierta: bloquear 30 s, desbloquear → vista previa en marcha. Con «Disparo auto» armado antes de bloquear: al volver está desarmado (`if (!_appActive) _disarmMoment()`), no se ha hecho ninguna foto sola. |
| CAM-08 | P1 | PX, EMU | M | Llamada entrante durante el visor (en EMU `adb emu gsm call 5551234`, en PX llamar desde otro teléfono): la app pasa a `inactive`/`paused`, la cámara se pausa; al colgar vuelve. Durante la llamada el micrófono lo tiene la telefonía: al volver, el ruido se recupera (`db` deja de ser `--`) sin reiniciar la app. |
| CAM-09 | P1 | PX | M | Pantalla dividida con otra app (Recientes → icono → Pantalla dividida): la app se redibuja en media pantalla sin solapar controles (480 px de alto aprox.); la cámara sigue; al volver a pantalla completa se recupera. `configChanges` incluye `screenSize|smallestScreenSize`. |
| CAM-10 | P0 | PX | M | Otra app toma la cámara: con Sonoglitch en el visor, abrir la app Cámara del sistema (desde la pantalla dividida o volviendo rápido), hacer una foto allí, volver a Sonoglitch. Esperado: Sonoglitch recupera la cámara (reintento y reapertura, `ARCHITECTURE` «Resume retries once…»); si no puede, muestra «No se ha podido abrir la cámara.» y lo intenta al volver, nunca se queda en negro sin mensaje. |
| CAM-11 | P1 | PX, IPH | M | Ir a **Ajustes** y volver, 10 veces, y abrir/cerrar la hoja de estilos 10 veces: la vista previa nativa se pausa mientras está cubierta (sin consumo visible) y vuelve en < 1 s; `fps` estable; sin fugas (`meminfo` Graphics no crece de forma monótona). |
| CAM-12 | P1 | PX, IPH | M | Girar el móvil durante la vista previa: la UI no rota (bloqueo vertical) pero la imagen de la cámara se mantiene derecha respecto al mundo (no se ve el vídeo tumbado al mantener el teléfono en vertical). Anotar el comportamiento en horizontal (esperado: UI en vertical, imagen rotada en el visor, foto corregida por CAM-03). |
| CAM-13 | P1 | PX, IPH | M | Zoom y proporción: la app **no tiene zoom** (no hay código de zoom en `lib/`); pinch no hace nada ni rompe el swipe de estilo. El visor es cover-fit (`cover_uv.dart`): sin bandas negras ni imagen deformada en 20:9 y en 4:3 (tablet/`wm size`). |
| CAM-14 | P0 | PX, IPH | M | Matar la app desde Recientes mientras procesa una foto (loader visible) y reabrir: arranca al visor sin crash; la caché del sistema contiene a lo sumo ficheros `sonoglitch_*` que se borran a las 24 h (`removeStaleTemporaryFiles`); no hay fotos a medias en la galería. |
| CAM-15 | P2 | EMU | A | `adb shell am start` con la app ya abierta (`launchMode singleTop`): no se crea una segunda instancia ni se reinicia el onboarding. |
| CAM-16 | P1 | IPH | M | iOS: cubrir el visor con el Centro de control y la Dynamic Island/llamadas; volver: la cámara se reanuda; sin aviso naranja de micrófono cuando se está en otra pantalla (el punto naranja debe apagarse al salir del visor o al pausar: verificar que el stream de `noise_meter` se cierra al ocultar el visor). |

### 4.3 Visor en vivo: estilos y controles (VF)

Precondición común: visor abierto; para resultados reproducibles, build `SONOGLITCH_MANUAL=n,l,m` o el interruptor **Manual** del panel con sus tres deslizadores.

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| VF-01 | P0 | EMU, PX | A+M | Los seis estilos se seleccionan y compilan: con las flechas (`vf-style-prev`/`vf-style-next`) recorrer Static → Tape → Phosphor → Ripple → Thermal → Prism y vuelta. El nombre en mayúsculas y el contador («1/6»… verificar formato) cambian; la imagen cambia de aspecto en < 300 ms; sin frame negro ni excepción de shader en logcat. |
| VF-02 | P0 | PX | M | **Ruido** en cada estilo (Manual: luz 0,5, movimiento 0, ruido 0 → 0,5 → 1): Static añade bandas/desgarros, Tape tracking/wobble/grano, Phosphor brillo/líneas/nieve, Ripple un frente de onda, Thermal cambia paleta/contornos, Prism dispersión. A ruido 1 el sujeto sigue reconocible (cara/texto legible) en los seis: regla de `AGENTS.md`. |
| VF-03 | P0 | PX | M | **Luz** en cada estilo (ruido 0,3, movimiento 0, luz 0 → 0,5 → 1): tonos fríos/contraste bajo a 0, cálidos/contraste alto a 1; Phosphor va de sombras verdes a blancos suaves; Thermal separa las isotermas. A luz 0,5 y ruido 0 la imagen es casi la original. |
| VF-04 | P0 | PX | M | **Movimiento** en cada estilo (ruido 0,3, luz 0,5, movimiento 0 → 1): estelas en la dirección del movimiento (Static/Tape/Prism), barril y persistencia verde (Phosphor), elipse y latencia (Ripple), desplazamiento (Thermal). Con sensores reales: agitar lateralmente → estelas horizontales; verticalmente → verticales (`uMotionDir`). |
| VF-05 | P0 | PX | M | Neutro: ruido 0, luz 0,5, movimiento 0 en los seis estilos: la imagen es la original salvo la micro-huella (≤ 1 nivel RGB8 por canal, invisible). Sin patrones fijos visibles. |
| VF-06 | P1 | PX | M | Variación entre disparos (semilla): dos fotos seguidas con la misma escena y controles manuales iguales no tienen idéntica disposición de bandas/anillos (semilla por foto); la diferencia es sutil, no un estilo distinto. Anotar si se percibe o no (STATUS: «decidir si se sube la intensidad»). |
| VF-07 | P1 | PX | M | Bandas en vivo (bass/mid/treble, solo Android): con un tono de 100 Hz fuerte, el panel sube `bass`; a 1 kHz `mid`; a 8 kHz `treble`. Visualmente el cambio es pequeño (densidad de bandas ±15 %): confirmar que algo cambia en Static/Tape, sin exigir que sea evidente. |
| VF-08 | P0 | EMU, PX | A+M | Medidores (`vf-meters`): las tres barras segmentadas (violeta ruido, cálida luz, cian movimiento) siguen el panel (`noise/light/motion`); tocarlas abre la hoja «Cómo funciona» con las tres explicaciones, el texto de deslizar y el de disparo auto; «Cerrar» la cierra. Mientras la hoja está abierta el reloj de animación se para (la imagen deja de animarse) y al cerrar continúa. |
| VF-09 | P1 | EMU, PX | M | Consejo de primer uso (`vf-hint`, «El sonido, la luz y el movimiento deforman la imagen. Desliza para cambiar de estilo.»): aparece solo la primera vez; el botón de cerrar lo quita y no vuelve tras reiniciar (`settings.tipsSeen`); *Ajustes → Mostrar los consejos otra vez* lo trae de vuelta y sale el snackbar «The tip will show again…»/es. |
| VF-10 | P1 | EMU, PX | A | Estado (`vf-status`): «Capturando…» mientras se hace la foto; «Esperando un ruido fuerte o un movimiento brusco» con disparo auto armado; vacío en reposo. Nunca dos textos a la vez. |
| VF-11 | P1 | PX | M | El botón de ajustes (`vf-settings`) abre **Ajustes**; atrás vuelve al visor con la cámara en marcha y el mismo estilo seleccionado. |
| VF-12 | P2 | EMU, PX | M | Foco de teclado/D-pad (`CHANGELOG` alpha.14): con un teclado Bluetooth o `adb shell input keyevent KEYCODE_TAB/DPAD_*`, el foco recorre estilo anterior, barra de estilo, siguiente, medidores, disparo auto, disparador, cambiar de cámara, ajustes con un estado de foco visible; Enter activa. |
| VF-13 | P1 | PX | M | Panel de diagnóstico encendido durante 5 min en el visor: se refresca ~4 veces por segundo, no tapa el disparador ni la barra de estilo, los deslizadores del modo Manual responden al instante y el badge pasa de «Auto» a «Manual». |

### 4.4 Señales ambientales (AMB)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| AMB-01 | P0 | PX | M | Silencio vs ruido: habitación tranquila 30 s → anotar `db` y `noise` (esperado `noise` cercano a 0, el suelo se aprende y baja hacia el P10 de los últimos 3 min, acotado 45-70 dB). Música alta/aspiradora → `noise` sube claramente (> 0,5) y el efecto crece; al apagarla baja en ~1 s (release 500 ms). |
| AMB-02 | P0 | PX | M | Aplauso o grito a 30 cm en silencio: `burst` salta (> 0,3) y el efecto da un pico breve distinto del ruido continuo; el techo adaptativo sube (`noiseCeilingDb` en el informe) y decae en los 10 min siguientes. |
| AMB-03 | P1 | PX | M | Suelo aprendido: estar 3 min en un lugar con ruido constante moderado (ventilador): `noise` baja hacia ~0,2-0,3 aunque `db` no cambie (adaptación); al pasar a silencio real, `noise` cae a 0. Anotar los `db` reales del Pixel para la calibración (STATUS pedía estos datos). |
| AMB-04 | P0 | PX, EMU | M | Sin permiso de micrófono (INS-06): `db --`, `noise 0.000`, `bass/mid/treble 0.000`, no hay crash al disparar, el **punto verde/naranja de micrófono** del sistema NO aparece. |
| AMB-05 | P0 | PX | M | Dos lectores de micrófono a la vez (Android): `noise_meter` y `SpectrumPlugin` (`AudioRecord`) abren el micro simultáneamente. Esperado: ambos funcionan (`db` y `bass/mid/treble` se mueven a la vez). Si uno falla, logcat lo dirá (`AudioRecord`/`AudioFlinger`) y es S2. Repetir tras CAM-06 y CAM-08. |
| AMB-06 | P0 | PX | M | Luz: apuntar a una ventana → `lux` alto, `light` > 0,7, tonos cálidos; tapar el sensor/objetivo → `lux` bajo, `light` < 0,2, tonos fríos. El 75 % viene del sensor y el 25 % de la imagen: con el sensor tapado pero la cámara a la luz, `light` queda intermedio (verificar). |
| AMB-07 | P1 | EMU | A | Luz virtual: `adb emu sensor set light 2000` → el panel muestra `lux 2000.0` y `light` sube; `light 1` → baja. Sin sensor (`hw.sensors.light=no` en otro AVD) o en iOS: `lux --` y la luz sale solo de la imagen. |
| AMB-08 | P0 | PX | M | Movimiento: móvil quieto en la mano → `motion` ≈ 0 (no debe estar siempre a 0,1-0,2 por el pulso de la mano). Agitar → `motion` > 0,6 y `sources accel` sube; girar (panorámica) → `gyro` sube; mover la escena (alguien pasa) con el móvil quieto en un soporte → `scene` sube. Estelas en la dirección del movimiento. |
| AMB-09 | P1 | EMU | A | Movimiento virtual: `adb emu sensor set gyroscope 0:0:3` → `gyro` y `motion` suben; `acceleration 0:9.8:5` repetido → `accel` sube. Volver a `0:9.8:0` → vuelve a 0 en ~0,5 s. |
| AMB-10 | P1 | PX | M | Espectro: tono 100 Hz → `bass` > `mid`,`treble`; 1 kHz → `mid` domina; 8 kHz → `treble` domina; silencio → los tres bajan a ~0. La banda de sonido de la exportación imprime escalas coherentes. |
| AMB-11 | P2 | PX | M | Ritmo (pulso, `uSign.z`): metrónomo a 120 BPM 15 s antes de disparar; comparar con silencio. El efecto es ≤ 4 % en un componente: solo se exige que no haya artefactos ni crash; anotar si se percibe. Sin ritmo → neutro (no se puede ver en el panel; se infiere). |
| AMB-12 | P2 | PX | M | Inclinación espectral: ruido grave (motor) vs agudo (siseo) con el mismo `noise`: cambio sutil entre grueso y fino. Solo robustez: sin artefactos. |
| AMB-13 | P1 | PX | M | Brújula (eje de orientación ≤ 12°): girar sobre uno mismo 360° despacio con Static a ruido 0,6: el corte/bandas rota ligeramente (hasta 12°). En un sitio con interferencia magnética (junto a un altavoz) no hay saltos bruscos (filtro 0,8 s; neutro tras 1 s sin datos). |
| AMB-14 | P1 | EMU | A | Sin magnetómetro: AVD con `hw.sensors.magnetic_field=no` o `adb emu sensor set magnetic-field 0:0:0`: la app no falla, el carril queda neutro, la línea de contexto no imprime rumbo (verificar que `validHeading` lo descarta). |
| AMB-15 | P2 | PX | M | Calendario/luna: no es observable en el panel. Cambiar la hora del sistema a 03:00 y a 19:00 (`adb shell date` requiere root → hacerlo en Ajustes del sistema sin hora automática) y disparar la misma escena a ruido 0,5: un leve cambio de temperatura de color (≤ 4 %). Solo se exige que no cambie el aspecto general y que la fecha impresa en la línea de contexto sea la del sistema. |
| AMB-16 | P2 | PX | M | Colorido de la escena (`uMood.z`): escena muy saturada (pantalla con colores) vs gris: el efecto añade menos croma en la saturada; el original no se desatura. Solo robustez. |
| AMB-17 | P1 | PX | M | Intensidad (Ajustes → Intensidad: Sutil/Normal/Extrema): mismo sonido y movimiento: Extrema deforma más que Normal y Sutil menos; la luz no cambia (`settingsIntensitySubtitle`). |
| AMB-18 | P1 | PX | M | Historial al disparar: con un pico de ruido de 1 s y disparar justo después, la foto refleja el pico (P90 de los 1,5 s previos), no el silencio del instante del disparo. Con Manual activo, la foto usa exactamente los valores de los deslizadores. |

### 4.5 Disparo auto (AUTO)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| AUTO-01 | P0 | PX | M | Armar «Disparo auto» (`vf-auto-shot`, tooltip «Disparo auto: hace la foto con un ruido fuerte o un movimiento brusco»): el anillo `moment-ring` y el estado «Esperando un ruido fuerte o un movimiento brusco» aparecen. Silencio 2 s y luego un grito/aplauso: se hace la foto sola (flash, vibración) y se abre el resultado; el modo queda desarmado (por defecto `settings.momentKeepArmed=false`). |
| AUTO-02 | P0 | PX | M | Un lugar que está alto todo el rato (música continua): NO dispara (necesita 1 s por debajo de 0,6 y cruzar 0,85). Esperado: sin fotos solas en 1 min. |
| AUTO-03 | P1 | PX | M | Salto de la escena: móvil en un soporte, escena quieta 2 s, alguien salta/entra de golpe (`sceneMotion` > 0,8 en ≤ 150 ms): dispara. Llevar el móvil en la mano caminando: no dispara. |
| AUTO-04 | P1 | PX | M | *Ajustes → Disparo auto: seguir esperando* activado: tras una foto y volver con «Repetir», sigue armado; respeta el enfriamiento de 8 s (dos aplausos a 3 s → una sola foto). |
| AUTO-05 | P0 | PX | M | Armado y pasar a segundo plano, bloquear, o abrir Ajustes: se desarma (`canFire` y `_disarmMoment`), ninguna foto sin mirar. Volver: hay que armarlo otra vez. |
| AUTO-06 | P1 | PX, EMU | M | Armado y pulsar el disparador a mano: la foto se hace; no se hacen dos (una manual y una auto) por el mismo sonido del obturador/vibración. |
| AUTO-07 | P1 | EMU | A | Sin micrófono (INS-06) y armado: solo dispara por movimiento de escena; aplaudir no dispara. |

### 4.6 Selección de estilo (STY)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| STY-01 | P0 | EMU, PX | A+M | Flechas: anterior/siguiente recorren los seis en bucle; vibración ligera (`HapticFeedback.selectionClick`) en PX; contador coherente. |
| STY-02 | P0 | PX, IPH | M | Deslizar sobre la imagen (`style-preview`): izquierda → siguiente, derecha → anterior; un deslizamiento corto o diagonal (< umbral) no cambia; un toque simple no cambia nada en release (el triple toque solo existe con `SONOGLITCH_DEBUG`). |
| STY-03 | P0 | EMU, PX | M | Hoja de estilos (tocar `vf-style-bar`, semántica «Estilo: Static. Toca para elegir»): seis filas numeradas con nombre y descripción de una línea (`styleDesc*`), la seleccionada marcada; tocar una la selecciona y cierra la hoja; el fondo de la fila seleccionada no se pinta detrás de la hoja (bug alpha.14 corregido). |
| STY-04 | P1 | EMU, PX | M | «Al azar»: elige uno distinto del actual (verificar si puede repetir el actual) y muestra el nombre; «Según el lugar» (`smart_pick.dart`): en silencio y luz alta → el estilo «calmBright» de la lista de preferencias; con ruido alto → el de «loud»; se muestra la explicación de una línea («Lugar ruidoso: {estilo}» etc.). |
| STY-05 | P1 | EMU, PX | M | El estilo seleccionado se mantiene tras ir a Ajustes y volver, tras fondo/primer plano y tras hacer una foto y «Repetir». Verificar si persiste al matar la app (no hay clave `settings.style` en `app_settings.dart`: esperado que vuelva al primero; anotar). |
| STY-06 | P2 | EMU | A | Ruta `Routes.styles` (`styles_screen.dart`): verificar si es alcanzable desde la UI; si lo es, la lista coincide con la hoja y seleccionar vuelve con el estilo aplicado; el badge «Seleccionado» se mueve. |

### 4.7 Captura (CAP)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| CAP-01 | P0 | PX, IPH | M | Disparo normal (`vf-shutter`, «Hacer una foto»): flash breve, vibración media, estado «Capturando…», y en ≤ 5 s el resultado con la foto procesada (alpha.8: take 558 ms + decode 414 + render 22 + encode 1967 a 12,5 MP PNG). La vista previa se restaura al volver (el still usa un controlador `ResolutionPreset.max` separado). |
| CAP-02 | P0 | PX | M | Resolución: con Calidad **Máxima** la foto exportada tiene el tamaño nativo del sensor hasta 24 MP del recorte (Pixel 10 Pro: anotar WxH reales); **Alta** ≤ 4096 px de lado; **Estándar** ≤ 2048 px. Comprobar con las propiedades del fichero en la galería. |
| CAP-03 | P0 | PX | M | La foto refleja los controles del momento: con ruido alto la foto sale rota; en silencio limpia; el estilo es el del visor; el valor de ruido en la pantalla de resultado («Ruido: unos N dB (aproximado)») coincide con el `db` del panel ±3. |
| CAP-04 | P0 | PX | M | Semilla y ID por disparo: hacer 5 fotos seguidas con Banda de sonido: cinco IDs distintos de 8 caracteres Crockford (`0-9 A-Z sin I L O U`), las cinco composiciones no son idénticas. Cambiar formato/calidad en el resultado NO cambia el ID de esa foto. |
| CAP-05 | P0 | PX | M | Firma congelada en el disparador: hacer una foto mientras el sonido cambia rápido (música con cortes). Al cambiar entre Completa/Banda/Póster y entre los 4 formatos, los números impresos y el aspecto del efecto son los mismos en todas las variantes de esa foto (la captura se congela una vez, `AmbientController.snapshot()`). |
| CAP-06 | P1 | PX | M | Diez disparos seguidos tan rápido como permita la app: ninguno se pierde ni se duplica (`_capturing` bloquea reentradas), la vista previa vuelve cada vez, memoria estable (`meminfo` antes/después, ±50 MB). |
| CAP-07 | P1 | PX | M | Fallo del still de alta resolución (difícil de forzar: ocupar la cámara con otra app justo al disparar): la app intenta la captura con el controlador en vivo (fallback) o muestra error en el log y vuelve al visor con «Capturando…» apagado; nunca un cuelgue. |
| CAP-08 | P1 | PX, IPH | M | Fichero temporal del still de la cámara borrado tras cada foto (éxito y fallo): la caché de la app (Ajustes del sistema → Almacenamiento) no crece más de unos pocos MB tras 10 fotos y «Repetir» en cada una. |
| CAP-09 | P1 | IPH | M | iOS: la foto se hace, la orientación es correcta en los 4 sentidos y la frontal no sale espejada en los textos (misma regla que CAM-02); tiempos de `capture` en el panel anotados (el JPEG va por Dart: ver RES-13). |

### 4.8 Pantalla de resultado (RES)

Precondición: una foto hecha con Calidad Alta salvo que se indique.

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| RES-01 | P0 | EMU, PX | A+M | Formato: Original / «Cuadrado 1:1» / «Vertical 4:5» / «Historia 9:16»: la vista previa recorta centrado sin deformar; el fichero exportado tiene esas proporciones (1:1 exacto, 4:5 = 0,8, 9:16 = 0,5625 ±1 px). |
| RES-02 | P0 | EMU, PX | A+M | Composición: «Completa» (solo foto + marca de agua abajo a la derecha), «Banda de sonido» (banda bajo la foto con estilo, números, escaleras y espectro, ID de foto), «Póster» (marco con nombre del estilo, lecturas e ID). La foto conserva su tamaño; el fichero es mayor que la foto (la banda/marco se añaden). Pista de una línea bajo el selector (`resultLayoutHint*`). |
| RES-03 | P0 | EMU, PX | A+M | Selector «Lecturas» (solo visible con Banda o Póster): «Completas» = números + escaleras + espectro; «Solo números» = números y etiquetas; «Ocultas» = sin lecturas. **El ID de la foto, el nombre del estilo y la marca de agua aparecen en los tres modos** (y la línea de contexto si está activada). La banda se estrecha (15,5 % / 13,5 % / 7,5 % del lado corto). En «Completa» el selector no aparece. |
| RES-04 | P0 | PX | M | Persistencia: la última Composición y el último modo de Lecturas se recuerdan para la siguiente foto (`settings.exportLayout`, `settings.exportReadingsMode`); el Formato vuelve a Original en cada foto (verificar: no hay clave de formato en `app_settings.dart`). |
| RES-05 | P0 | PX | M | Loader: al entrar y al cambiar formato/composición/lecturas, el `GlitchLoader` (fila de celdas con franja cromática) se superpone a la zona de la foto con «Procesando N MP…»; se queda quieto con animaciones reducidas; desaparece al terminar; **Guardar/Compartir están deshabilitados mientras se compone** y se habilitan al acabar. Al hacer scroll de los controles, el loader sigue sobre la foto (alpha.21). |
| RES-06 | P1 | PX | M | Cambios rápidos: alternar formato 1:1 → 9:16 → 4:5 → Original en 2 s: solo se aplica la última petición (sin parpadeo de una composición antigua al final), y volver a una ya vista es inmediato (caché LRU de 4). |
| RES-07 | P0 | PX | A+M | Comparar (`res-compare`, «Comparar con el original (o mantén pulsada la foto)»): el botón alterna foto original/procesada; mantener pulsada la foto muestra el original mientras se mantiene. **Guardar y Compartir exportan siempre la procesada**, aunque se esté viendo el original (comprobar el fichero). |
| RES-08 | P0 | PX | M | Calidad **Máxima** + Póster + 9:16 + PNG: el procesado termina (anotar tiempo), la memoria no supera el límite (sin «Application Not Responding», sin muerte por OOM en logcat `Low on memory`/`lowmemorykiller`). Si el plan baja de nivel (log `export fallback … -> …` o `export layout fallback`), anotar como P1 observado, no como fallo. |
| RES-09 | P1 | LOW, PX | M | Fallback por memoria/textura: en un dispositivo con poca RAM, Máxima + Póster debe degradar a Alta/Estándar automáticamente y mostrar la foto igualmente (`PhotoExporter` baja de nivel ante `OutOfMemoryError`); nunca una pantalla vacía ni crash. |
| RES-10 | P1 | PX | M | «Repetir» durante el procesado (loader visible): vuelve al visor con la animación de cierre, la cámara en marcha; el fichero temporal se borra; sin excepción en el log («crop generations reject late results»). |
| RES-11 | P1 | PX | M | Botón atrás del sistema durante el procesado y durante Guardar: igual que RES-10; durante Guardar el botón «Repetir» y los selectores están deshabilitados (`_busy`). |
| RES-12 | P0 | PX | M | PNG vs JPEG (Ajustes → Tipo de archivo): PNG guarda `.png` sin pérdida; JPEG guarda `.jpg` (extensión real del fichero en la galería) con calidad 95 por el encoder nativo (`ImageEncoderPlugin`); si el encoder falla, el fichero es `.png` y el log dice «the PNG is kept». Tamaño JPEG ≪ PNG a la misma resolución. |
| RES-13 | P0 | IPH | M | iOS JPEG: no hay encoder nativo (`MethodChannel sonoglitch/encoder` sin handler en `AppDelegate.swift`): esperado hoy que la llamada falle y se conserve el PNG. Verificar: ¿la app exporta PNG silenciosamente aunque el ajuste diga JPEG? Si es así es S2/P1 de producto (ajuste engañoso) a decidir antes del App Store. |
| RES-14 | P1 | PX | M | Las lecturas del resultado: «Ruido: unos N dB (aproximado)», «Luz: baja/media/alta», «Movimiento: baja/media/alta» con los umbrales 0,33/0,66; sin micrófono el ruido muestra 0 o «--» (verificar el texto exacto). |
| RES-15 | P1 | PX | M | Volver al resultado tras fondo/primer plano o tras una llamada: la foto sigue, los botones responden, no se vuelve a componer innecesariamente. |

### 4.9 Guardar y compartir (SAVE)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| SAVE-01 | P0 | PX (Android 11+) | M | «Guardar»: snackbar «Foto guardada en la galería.»; en Google Fotos/Galería aparece en el álbum **Sonoglitch** (`Gal.putImage(album: 'Sonoglitch')` desde API 30), con la fecha actual y el tamaño de RES-01/CAP-02. Sin pedir ningún permiso de almacenamiento. |
| SAVE-02 | P0 | LOW (Android 10) | M | Guardar en Android 10: se guarda en la galería **sin álbum** (`_galleryAlbum` devuelve null si `sdkInt < 30`), sin diálogo de permiso y sin error. Si no hay dispositivo Android 10, probar en un AVD API 29 (crear uno; cámara virtual basta porque la foto se genera igual). |
| SAVE-03 | P1 | PX | M | Guardar dos veces la misma foto: dos ficheros en la galería (verificar que no se deduplica ni falla por nombre repetido). |
| SAVE-04 | P0 | PX | M | «Compartir»: se abre la hoja de compartir del sistema con la imagen (sin texto, asunto «Sonoglitch»); compartir a Instagram (historia y publicación), WhatsApp y «Guardar en Drive»: la imagen llega completa con la banda/póster. Cancelar la hoja → snackbar o nada, pero no error. Snackbar «Compartido.» al volver (verificar en qué casos se muestra: `share_plus` no siempre informa del resultado). |
| SAVE-05 | P1 | PX | M | Compartir y después Guardar la misma foto sin recomponer: inmediato (reutiliza el fichero codificado en caché). |
| SAVE-06 | P1 | PX | M | La foto guardada abierta en la galería: marca de agua «sonoglitch» abajo a la derecha, legible pero discreta (≈2,2 % del lado corto); con Banda/Póster la marca está en la banda/marco y no sobre la foto. |
| SAVE-07 | P0 | IPH | M | iOS Guardar: la primera vez el sistema pide acceso a Fotos con el texto `NSPhotoLibraryUsageDescription` («…find or create the Sonoglitch album…»). Con «Permitir acceso total»: la foto aparece en Fotos y en el álbum **Sonoglitch**. Con «Acceso limitado»/«Añadir solo» (iOS 14+): verificar si `Gal` puede crear el álbum; si no, debe guardar sin álbum o mostrar «The photo could not be saved.» — anotar el comportamiento real. Denegar: snackbar de error, sin crash. |
| SAVE-08 | P0 | IPH | M | iOS Compartir: hoja nativa con la imagen; AirDrop, Mensajes e Instagram reciben el PNG/JPEG completo. La app es solo para iPhone (sin iPad desde el 29-oct-2026); la app pasa igualmente `sharePositionOrigin` (`origin`), que no hace falta comprobar en iPad. |
| SAVE-09 | P1 | PX | M | Almacenamiento casi lleno (llenar con un fichero grande: `adb push` de un fichero de varios GB a `/sdcard/` hasta < 200 MB libres): Guardar falla con «The photo could not be saved.»/es, sin crash; procesar una foto Máxima con la caché llena: fallback o error controlado. Limpiar después. |

### 4.10 Marca de agua, línea de contexto y ajustes (SET)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| SET-01 | P0 | EMU, PX | A+M | Estructura de **Ajustes**: sección «Cámara» (Calidad de foto: Estándar/Alta/Máxima · Intensidad: Sutil/Normal/Extrema · Línea de contexto · Marca de agua · Disparo auto: seguir esperando · Tipo de archivo: PNG (sin pérdidas)/JPEG (alta calidad) · Mostrar los consejos otra vez), sección «Solución de problemas» (Diagnóstico · Exportar informe de diagnóstico), «Acerca de» (Versión X · Licencia: Apache-2.0 · Privacidad con su texto). La fila «Apoya el proyecto» **no** aparece en el build de Play ni en el de iOS; sí en el APK de GitHub (abre Ko-fi en el navegador). |
| SET-02 | P0 | EMU, PX | A | Persistencia de cada ajuste: cambiar todos a un valor no predeterminado (Máxima, Extrema, contexto ON, marca OFF, seguir esperando ON, JPEG, Diagnóstico ON), `am force-stop`, reabrir: todos conservados. Valores por defecto en instalación limpia: Alta, Normal, contexto OFF, marca ON, seguir esperando OFF, PNG, Diagnóstico OFF (`AppSettings.load`). |
| SET-03 | P0 | PX | M | Marca de agua OFF: la foto exportada (Completa) no lleva «sonoglitch»; con Banda/Póster tampoco aparece la marca (verificar que `watermark=false` también la quita de la banda). ON: vuelve. Cambiar el ajuste con la pantalla de resultado abierta detrás y volver: la composición se refresca (`Settings notifications refresh watermark…`). |
| SET-04 | P0 | PX | M | Línea de contexto ON + Banda o Póster: imprime fecha y hora locales `AAAA-MM-DD HH:MM`, el rumbo `NNN°` con la aguja y la presión `NNNN hPa` si el barómetro responde en 500 ms, la fase lunar dibujada. Sin barómetro/magnetómetro: solo la fecha. OFF (predeterminado): no se imprime nada. Comprobar que la hora impresa es la del disparo, no la del guardado (esperar 3 min entre disparar y guardar). |
| SET-05 | P1 | PX | M | Interruptores redibujan al tocarlos (bug alpha.13 corregido): cada Switch cambia visualmente al primer toque; dos toques vuelven al estado inicial. |
| SET-06 | P1 | EMU, PX | A+M | «Exportar informe de diagnóstico»: abre la hoja de compartir con un JSON (y el log si existe). Abrirlo: contiene `appVersion`, `buildMode: release`, `device`, `ambient` (solo las claves de `AmbientState.toJson`), `camera`, `style`, `lastCapture`, `logs`. Ver PRIV-08 para lo que NO debe contener. |
| SET-07 | P2 | EMU | A | Enlace de donación con URL no https (solo con `--dart-define=DONATION_URL=http://…` en un build local): la fila aparece pero al tocar se registra un aviso y no se abre nada (`'the donation link is not an https link'`). |
| SET-08 | P1 | PX | M | Scroll de Ajustes con escala de fuente 200 %: todas las filas legibles, los `SegmentedButton` de tres opciones no se salen de la pantalla (si se cortan, S3). |

### 4.11 Localización (L10N)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| L10N-01 | P0 | EMU, PX | A+M | Sistema en español: recorrer onboarding, visor (hint, estado, hoja de estilos, «Cómo funciona»), resultado, ajustes, panel: todo en español salvo nombres de estilo (Static, Tape… intencionado) y los términos del panel técnico (`noise`, `db`… intencionado). Capturas de cada pantalla. |
| L10N-02 | P0 | EMU, PX | A+M | Sistema en inglés: lo mismo en inglés. |
| L10N-03 | P1 | EMU | A | Desbordamientos a 200 % (`adb shell settings put system font_scale 2.0`): onboarding (botón con `ellipsis`), barra de estilo, hoja de estilos (descripciones), resultado (pistas y botones «Repetir/Compartir/Guardar»), ajustes (subtítulos largos como `settingsQualitySubtitle`). Esperado: sin texto encima de otro ni `RenderFlex overflow` amarillo/negro (en release no se pinta, pero logcat lo registra). |
| L10N-04 | P1 | EMU | A | Pantalla 320x568 (`adb shell wm size 320x568 && wm density 160`) en es y en en: nada se solapa en el visor (alpha.13 lo prometía), controles ≥ 48 dp. Restaurar con `wm size reset`. |
| L10N-05 | P2 | PX | M | Textos impresos en la exportación (banda/póster) con el sistema en español: ¿los rótulos de la banda están localizados o son fijos en inglés? Anotar lo que se ve (verificar en `export_layout_painter.dart`); no es defecto si es decisión de diseño. |
| L10N-06 | P2 | EMU | A | Cambiar el idioma del sistema con la app abierta (`configChanges` incluye `locale`): los textos cambian sin reiniciar o, al menos, sin crash. |
| L10N-07 | P2 | — | — | RTL no requerido (no hay locales RTL en `supportedLocales`). Sin caso. |

### 4.12 Accesibilidad (A11Y)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| A11Y-01 | P0 | PX | M | TalkBack activado (`adb shell settings put secure enabled_accessibility_services com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService` o en Ajustes): cada control del visor anuncia una etiqueta útil: «Estilo anterior», «Estilo: Static. Toca para elegir», «Estilo siguiente», «Sonido, luz y movimiento en directo. Toca para ayuda» (verificar es), «Disparo auto: hace la foto…», «Hacer una foto», «Cambiar de cámara», «Ajustes». Sin controles sin nombre («botón» a secas). |
| A11Y-02 | P0 | PX | M | TalkBack en resultado: los selectores anuncian valor y estado seleccionado; «Comparar con el original (o mantén pulsada la foto)»; las tres lecturas anuncian «Ruido: unos N dB…», «Luz: …», «Movimiento: …» (`semanticsLabel`); el loader anuncia «Procesando». |
| A11Y-03 | P1 | PX | M | TalkBack en ajustes: cada `SwitchListTile` anuncia título, subtítulo y estado; los segmentados anuncian la opción seleccionada. |
| A11Y-04 | P1 | PX, EMU | A+M | Animaciones reducidas (`adb shell settings put global animator_duration_scale 0` y «Eliminar animaciones» en accesibilidad): la hoja «Cómo funciona», el hint, el loader y el botón de onboarding no animan; el efecto del shader en vivo sí sigue (no es animación de UI). Sin saltos. |
| A11Y-05 | P1 | EMU | A | Escala de fuente 130 % y 200 %: ver L10N-03; además los medidores y el contador de estilo siguen legibles. |
| A11Y-06 | P1 | PX | M | Contraste: contador de estilo y segmentos apagados de los medidores sobre una escena muy clara (ventana) siguen distinguibles (bug alpha.14 corregido); el estado «Capturando…» sobre escena oscura legible. |
| A11Y-07 | P1 | EMU | A | Tamaño de objetivos táctiles ≥ 48x48 dp en visor y resultado: medir con *Opciones de desarrollador → Mostrar límites de diseño* o con `uiautomator dump` (`adb shell uiautomator dump && adb pull /sdcard/window_dump.xml`, leer `bounds`). |
| A11Y-08 | P0 | IPH | M | VoiceOver: los mismos controles de A11Y-01/02 con etiqueta; el gesto de deslizar para cambiar de estilo tiene alternativa (las flechas). Dynamic Type al máximo: sin solapes. |
| A11Y-09 | P2 | PX | M | Teclado/D-pad (VF-12) con TalkBack: el orden de foco es lógico (arriba-abajo, izquierda-derecha). |

### 4.13 Tema, tablets y pantallas pequeñas (UI)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| UI-01 | P1 | EMU, PX | A | La app usa un único tema oscuro (`AppTheme.dark()`): con el sistema en modo claro (`adb shell cmd uimode night no`) la app sigue oscura, la barra de estado tiene iconos claros legibles y el splash (`LaunchTheme`, `values/styles.xml` y `values-night/styles.xml`) no parpadea en blanco. |
| UI-02 | P1 | EMU | A | Tablet (`wm size 1600x2560 && wm density 320` o AVD tablet): el visor se dibuja a pantalla completa con los controles anclados abajo, sin estirar la imagen; la hoja de estilos no ocupa toda la anchura de forma absurda (anotar). Anotar si hay espacio excesivo: es P2. |
| UI-03 | P1 | EMU | A | 320x568 (L10N-04) en resultado y ajustes: botones «Repetir/Compartir/Guardar» en una fila sin cortar o apilados; selectores con scroll. |
| UI-04 | P2 | PX | M | Pantalla con recorte (notch/cámara frontal) y gestos de navegación: ningún control queda bajo la barra de gestos ni bajo la cámara perforada (`SafeArea`). |
| UI-05 | P2 | IPH | M | iPhone con Dynamic Island y iPhone SE (pantalla pequeña, si hay): lo mismo. `UISupportedInterfaceOrientations` declara horizontal pero la app bloquea vertical: comprobar que en iPhone la app sigue usable en vertical (la app es solo para iPhone; ya no hay iPad). |
| UI-06 | P1 | EMU, PX | A | Icono de la app en los tamaños del lanzador, redondo y temático (Android 13+ icono monocromo). Splash → onboarding sin salto de color. |

### 4.14 Rendimiento y térmico (PERF)

Referencia: `docs/ARCHITECTURE.md` pide comparar p50/p95 de frame time contra alpha.15 en la misma escena; alpha.8 en el Pixel dio 29,4 fps de stream y `conv 17,6 ms`.

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| PERF-01 | P0 | PX | M | Fluidez del visor por estilo: escena de referencia, 60 s por estilo con ruido ~0,5 y movimiento ocasional. Objetivo: p50 ≤ 16,7 ms y p95 ≤ 33 ms del hilo raster (DevTools en perfil) o, con el release, `dumpsys gfxinfo` con < 10 % de janky frames y percentil 95 < 33 ms. `fps` del panel ≥ 25. Anotar los seis valores; Phosphor es el más caro (11 lecturas de textura). |
| PERF-02 | P0 | PX | M | Tiempo de disparo a resultado: Estándar < 2 s, Alta < 4 s, Máxima PNG < 8 s, Máxima JPEG < 6 s (orientativos; anotar `capture take/decode/render/encode` del panel). |
| PERF-03 | P0 | PX | M | Memoria: `dumpsys meminfo` en reposo en el visor (base), tras una foto Máxima + Póster (pico) y tras «Repetir» (vuelta). Esperado: la vuelta está a ≤ base + 50 MB; el pico no provoca `lowmemorykiller` ni ANR. Repetir 5 fotos: sin crecimiento monótono (fuga). |
| PERF-04 | P1 | PX | M | Sesión larga 15 min en el visor con cambios de estilo cada minuto y 5 fotos: la app sigue fluida al final (PERF-01 al minuto 14 vs minuto 1), temperatura del aparato tolerable al tacto, `dumpsys thermalservice` sin estado `SEVERE`; `batterystats` anota el % consumido (orientativo: < 8 % en 15 min). |
| PERF-05 | P1 | PX | M | Arranque en frío: `am start -W` → `TotalTime` < 2 s hasta el onboarding/visor; sin pantalla blanca. |
| PERF-06 | P1 | PX | M | Consumo en segundo plano: tras 10 min con la app en segundo plano (visor abierto antes), `batterystats` no muestra uso de cámara/micrófono/sensores de Sonoglitch; los indicadores verdes de cámara/micro del sistema se apagan al salir. |
| PERF-07 | P1 | LOW | M | Gama baja: PERF-01 y PERF-02 en el dispositivo barato; si p95 > 50 ms, es P1 de producto (la SPEC prevé bajar resolución de preview o aplicar el efecto solo al capturar). |
| PERF-08 | P1 | IPH | M | iOS: PERF-01/02/03 con los fallbacks Dart (sin espectro: `bass/mid/treble` 0; JPEG por Dart si llega a existir, ver RES-13). |
| PERF-09 | P2 | PX | M | Panel de diagnóstico encendido vs apagado: diferencia de fps < 2. |

### 4.15 Robustez (ROB)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| ROB-01 | P0 | PX, EMU | A+M | Toques rápidos: 20 toques seguidos al disparador: una sola foto por disparo real, sin cuelgue; 20 toques alternos a las flechas de estilo; abrir/cerrar la hoja de estilos 10 veces rápido. Sin excepciones en el log. |
| ROB-02 | P1 | PX | M | Girar el móvil mientras procesa (loader): la UI no rota, el procesado termina con la orientación congelada en el disparo. |
| ROB-03 | P1 | PX, EMU | A+M | Modo avión activado (`adb shell cmd connectivity airplane-mode enable`): todo funciona igual (la app no usa red). Comprobar con `adb shell dumpsys netstats detail | grep es.sonoglitch` o `dumpsys package es.sonoglitch.app | grep INTERNET`: sin permiso, sin tráfico. |
| ROB-04 | P1 | PX | M | Almacenamiento bajo: ver SAVE-09. |
| ROB-05 | P1 | PX | M | Batería al 5-10 % con ahorro de energía: la app funciona (puede bajar fps); sin crash al tomar una foto Máxima. |
| ROB-06 | P1 | PX, EMU | A+M | Interrumpir con notificaciones de pantalla completa (alarma) y con la cámara de la pantalla de bloqueo: al volver todo se reanuda. |
| ROB-07 | P1 | EMU | A | «No conservar actividades» (Opciones de desarrollador → Don't keep activities) y fondo/primer plano desde el resultado: la app vuelve al visor o al resultado sin crash (si se pierde la foto no guardada, anotar como P2 conocido). |
| ROB-08 | P1 | PX | M | Hora del sistema cambiada hacia atrás con la app abierta: la línea de contexto y el log no fallan (relojes monótonos para edades; `moonAge` admite fechas anteriores a la época). |
| ROB-09 | P2 | PX | M | Pulsar «Compartir» y, con la hoja abierta, girar/bloquear/volver: sin crash; la hoja se cierra o se mantiene según el sistema. |
| ROB-10 | P1 | EMU | A | Monkey acotado: `adb shell monkey -p es.sonoglitch.app --pct-syskeys 0 --throttle 200 -v 1500` con cámara virtual. Esperado: 0 crashes/ANR en logcat. (Puede disparar y guardar fotos: limpiar la galería del emulador después.) |

### 4.16 Privacidad y seguridad (PRIV)

Las hace el líder (nunca se delegan a un motor externo). Se ejecutan sobre el **artefacto que se sube** (AAB de Play, APK de GitHub, IPA).

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| PRIV-01 | P0 | PC | A | Manifiesto fusionado del AAB/APK: `aapt2 dump badging app-release.aab`/`.apk` (o `bundletool dump manifest --bundle=…`) y `apkanalyzer manifest print`: `package="es.sonoglitch.app"`, `uses-permission` **solo** `android.permission.CAMERA` y `android.permission.RECORD_AUDIO`; **ningún** `INTERNET`, `ACCESS_NETWORK_STATE`, `READ/WRITE_EXTERNAL_STORAGE`, `READ_MEDIA_*`, `ACCESS_*_LOCATION`, `HIGH_SAMPLING_RATE_SENSORS`; `android:allowBackup="false"`, `dataExtractionRules` presente; `minSdkVersion 29`, `targetSdkVersion` igual al que exige Play (verificar el número en el dump; Flutter 3.47.7 fija `flutter.targetSdkVersion`); `versionCode` > 21. `tool/release/build_play_bundle.ps1` ya imprime estas líneas. |
| PRIV-02 | P0 | PX | A | En el dispositivo: `adb shell dumpsys package es.sonoglitch.app | grep -A3 "requested permissions"` muestra solo las dos; `grep -i internet` vacío. |
| PRIV-03 | P0 | PX | A+M | Sin audio escrito: usar la app 5 min con micrófono, hacer 5 fotos, compartir una. Después, `adb shell ls -la /sdcard/Android/data/es.sonoglitch.app/ /sdcard/Android/media/es.sonoglitch.app/ 2>/dev/null` vacío o inexistente; en *Ajustes del sistema → Almacenamiento* de la app, «Datos» de pocos KB (preferencias + log < 1,5 MB) y «Caché» ≤ unos MB de `sonoglitch_*.png/.jpg`. Buscar en la galería y en Archivos ficheros `.wav/.m4a/.pcm/.aac` recientes: ninguno. |
| PRIV-04 | P0 | PC | A | Sin secretos en el artefacto: descomprimir el APK/AAB (`unzip -l`) y `grep -rIE "ko-fi|ANDROID_KEYSTORE|key.properties|password|BEGIN (RSA|PRIVATE)|AKIA|ghp_|sk_live" --include=* .` sobre `assets/`, `res/`, `lib/*/libapp.so` (con `strings`). Esperado: solo la URL de Ko-fi en el APK de GitHub (y **ninguna** en el AAB de Play), sin rutas personales (tu nombre de usuario, `C:/Users`, `F:/Users`), sin claves. `tool/publish/publish_public.ps1` ya escanea el snapshot del repo; esto es sobre el binario. |
| PRIV-05 | P0 | PC | A | Firma: `apksigner verify --print-certs sonoglitch-X.Y.Z.apk`: v2/v3 válidas y el certificado es el de la clave de subida (mismo SHA-256 que el de la release anterior estable). El AAB se firma con la misma clave de subida; Play lo re-firma (App Signing). Si el APK de GitHub sale con clave de depuración (secretos no puestos), es **no-go** para una versión estable. |
| PRIV-06 | P0 | PX | A+M | Copias de seguridad: `adb shell bmgr enabled` y `adb shell bmgr backupnow es.sonoglitch.app` → el log de `bmgr` indica que la app está excluida (`allowBackup=false`); en Android 12+ `data_extraction_rules.xml` excluye todo de la nube y de la transferencia. Alternativa: *Ajustes del sistema → Google → Copia de seguridad → Datos de apps* no lista Sonoglitch tras una copia. |
| PRIV-07 | P0 | PX | A | Red en ejecución: tras 10 min de uso, `adb shell dumpsys netstats detail | grep -i sonoglitch` sin entradas, o `adb shell cat /proc/net/xt_qtaguid/stats` (si existe) sin el UID de la app. Sin permiso `INTERNET` ninguna conexión es posible: este caso solo confirma que el artefacto es el release (el debug sí lo tiene). |
| PRIV-08 | P0 | PX, EMU | A+M | Contenido de los diagnósticos: «Copiar informe» y «Exportar informe de diagnóstico» y el fichero de log de «Compartir registros». Buscar en el JSON: **no** debe haber `heading`, `rumbo`, `bpm`, `pulse`, `rhythm`, `tilt`, `calendar`, `moon`, `warmth`, `hue`, `chroma`, `seed`, `fingerprint`, `photoId`, `nonce`, `pressure`, ni rutas absolutas (`/data/`, `/storage/`, `C:\`). **Sí** puede haber: `noise, light, motion, motionDirX/Y, bass, mid, treble, rawDb, rawLuma, rawAccel, rawLux, baselineDb, burst, noiseCeilingDb, sceneMotion, gyroMotion, accelMotion, rawGyro`, modelo, versión de SO, tiempos. (`test/ambient/sensitive_signals_test.dart` lo cubre en unidad; aquí se confirma el artefacto real.) |
| PRIV-09 | P1 | PX | A+M | Temporales: tras 10 fotos con «Repetir», 3 guardadas y 2 compartidas, la caché contiene ≤ 4 ficheros `sonoglitch_*` (LRU) más los conservados por Guardar/Compartir hasta salir del resultado; tras cerrar el resultado, se borran. Adelantar el reloj del sistema 25 h y reabrir: los que queden desaparecen (`removeStaleTemporaryFiles`). Observable por el tamaño de «Caché». |
| PRIV-10 | P0 | PC | A | La política de privacidad pública (`https://sonoglitch.mainshai.com/privacy/`) responde 200 sin sesión y su texto coincide con la versión del repo privado que se publica (misma fecha «Last updated»). Menciona cámara, micrófono (solo niveles y tres bandas), sensores de movimiento, brújula, barómetro, reloj, galería, diagnósticos locales, sin red, sin cuentas, correo `dev@mainshai.com`. |
| PRIV-11 | P1 | PC | A | Dependencias: `flutter pub outdated` y revisión de licencias de las 11 dependencias directas de `pubspec.yaml` (todas permisivas: verificar `gal`, `noise_meter`, `share_plus`); `dart pub deps` sin paquetes con acceso a red salvo `url_launcher` (abre el navegador, no conecta). Confirmar que `url_launcher` solo se usa para Ko-fi (`settings_screen.dart`). |
| PRIV-12 | P0 | PC | A | Revisión de seguridad del líder con `security-reviewer` (Fable `medium`) sobre el diff desde la última auditoría (`.local/security-review.md`, F03-F05 iOS pendientes) antes de fusionar la release: cero hallazgos críticos/altos abiertos. |
| PRIV-13 | P1 | IPH | M | iOS: con la app en el visor, el indicador naranja (micro) y verde (cámara) están encendidos; al ir a Ajustes o al fondo se apagan. En *Ajustes → Privacidad → Registro de actividad de apps* (si está activado) solo aparecen cámara, micrófono y fotos, y ningún dominio de red. |

### 4.17 Instalación, actualización y desinstalación (UPG)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| UPG-01 | P0 | PX | A+M | Actualizar sobre la versión anterior firmada con la misma clave (p. ej. la prerelease previa del repo privado): `adb install -r nuevo.apk` → `Success`; al abrir, **no** vuelve el onboarding (permisos conservados), todos los ajustes de SET-02 conservados, el estilo según STY-05, el consejo no reaparece. Versión en «Acerca de» actualizada. |
| UPG-02 | P0 | PX | A | Firma distinta (APK de depuración sobre el de la clave de subida o viceversa): `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: documentar en las notas de la prueba cerrada que los testers deben desinstalar las alphas de GitHub antes de instalar desde Play (Play firma con su propia clave: es otra firma). |
| UPG-03 | P1 | PX | A | Downgrade: `adb install -r -d anterior.apk` solo con `-d`; sin `-d` falla por `versionCode`: confirma que el `versionCode` es estrictamente creciente. |
| UPG-04 | P1 | PX, EMU | A | Desinstalar: `adb uninstall es.sonoglitch.app` → `Success`; las fotos guardadas siguen en la galería (son del usuario); la caché y las preferencias desaparecen; en Android 10 u 11 el álbum «Sonoglitch» puede quedar vacío o desaparecer (comportamiento del sistema; anotar). Reinstalar: estado de primer uso. |
| UPG-05 | P1 | PX | A | El id antiguo (`io.github.dferrandizmont.sonoglitch`, alphas ≤ 17) instalado a la vez que el nuevo: conviven como dos apps (CHANGELOG alpha.18); desinstalar el antiguo no afecta al nuevo. |
| UPG-06 | P0 | EMU-PS | M | Instalación desde Play (ver PLAY-10/11). |
| UPG-07 | P0 | IPH | M | iOS: instalar la build de desarrollo por Xcode, luego la de TestFlight con el mismo bundle id `es.sonoglitch.app`: TestFlight sustituye la de desarrollo (misma firma de equipo) o pide desinstalar — anotar; ajustes conservados si sustituye. |

### 4.18 Google Play (PLAY)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| PLAY-01 | P0 | PC | M | Subida del AAB a la pista **interna** primero (tú en Play Console), inscripción en Play App Signing con la clave de subida (`android/key.properties`, nunca compartida). Play acepta el AAB sin errores de «API objetivo», «64 bits» (arm64-v8a incluido por defecto en el AAB) ni «tamaño». Tamaño descargado estimado por Play anotado (APK alpha ≈ 35 MB; los 6 shaders de test `test/effects/fixtures/*.frag` viajan en el bundle — verificar si inflan y si conviene excluirlos antes de 1.0). |
| PLAY-02 | P0 | PC | A+M | **Data safety** coincide con la app: «¿Recopila o comparte alguno de los tipos de datos requeridos?» → **No** (`docs/RELEASING.md`). Justificación anotada en el registro: sin red, sin cuentas, procesado local; compartir es iniciado por el usuario vía hoja del sistema. Si Play obliga a declarar «Fotos y vídeos» por guardar en la galería, releer la ayuda vigente: guardar en el dispositivo del usuario no es «recopilar». Marcar `verificar` y guardar captura de la pantalla rellenada. |
| PLAY-03 | P0 | PC | M | Clasificación de contenido: cuestionario IARC respondido (sin contenido generado por usuarios compartido en la app, sin ubicación, sin compras, sin violencia). Resultado anotado; no asumirlo. |
| PLAY-04 | P0 | PC | M | Declaraciones de permisos: Play no pide declaración especial para `CAMERA`/`RECORD_AUDIO` en primer plano; confirmar que no aparece ningún aviso de «permiso sensible» pendiente. Anuncios: «No contiene anuncios». Apps gubernamentales/financieras/salud/noticias: No. Público objetivo: adultos (sin marcar «niños» para no entrar en Families). |
| PLAY-05 | P0 | PC | M | Ficha: título «Sonoglitch» (`title.txt`), descripción corta (≤ 80) y larga (≤ 4000) de `fastlane/metadata/android/en-US` y `es-ES` pegadas sin cortes; icono 512x512 y gráfica 1024x500 de `fastlane/metadata/android/*/images/`; ≥ 2 capturas de teléfono por idioma hechas con el build candidato (las 8 de `docs/readme/README.md` sirven; sin barra de estado con datos personales); URL de política de privacidad (PRIV-10); correo `dev@mainshai.com`; categoría Fotografía; gratis, sin compras. **Nada de la ficha promete lo que la app no hace** (releer: «six styles», «Auto shot», «context line», «no network access»: todo verificado en 4.3-4.10). |
| PLAY-06 | P1 | PC | M | Notas de la versión: `fastlane/metadata/android/{en-US,es-ES}/changelogs/<versionCode>.txt` existen para el `versionCode` subido (≤ 500 bytes) y coinciden con `CHANGELOG.md`. |
| PLAY-07 | P0 | PC | M | **Informe previo al lanzamiento** (pre-launch report) de la pista interna/cerrada: 0 crashes, 0 ANR; revisar los avisos de accesibilidad y seguridad; las capturas automáticas muestran el onboarding y, si concede permisos, el visor (los robots suelen denegar: aceptable). Cualquier crash es S1. |
| PLAY-08 | P1 | PC | M | Play Console → *Estadísticas/Android vitals* vacío al inicio; configurar alertas de crash. Comprobar en *Versión → Detalles* que `targetSdk` y las ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) son las esperadas. |
| PLAY-09 | P0 | PC | M | Prueba cerrada: lista/grupo de Google con los 12 testers, enlace de participación generado, países, y la cuenta de pruebas sin tarjeta. Fecha de inicio anotada (los 14 días cuentan desde que hay 12 testers activos — verificar el criterio vigente en Play Console). |
| PLAY-10 | P0 | EMU-PS o PX | M | Ruta del tester (con **tu** cuenta Google del grupo, sesión iniciada por ti): abrir el enlace de participación → «Convertirse en tester» → Play Store muestra la ficha con «(Beta)»/«Prueba cerrada» → Instalar → la app abre en el onboarding. Capturas de cada paso para las instrucciones a los testers. |
| PLAY-11 | P0 | PX | M | Actualización por Play: subir un segundo build (`versionCode`+1) a la misma pista; Play Store ofrece «Actualizar»; tras actualizar, UPG-01 se cumple (ajustes y permisos conservados). Confirma que la firma de Play es estable entre builds. |
| PLAY-12 | P1 | PC | M | Política de pagos: el AAB se compiló **sin** `DONATION_URL` (SET-01 en el build instalado desde Play: no hay fila «Apoya el proyecto»). `strings`/`unzip` del AAB sin `ko-fi` (PRIV-04). |

### 4.19 App Store (IOS)

| ID | P | Ent. | Modo | Caso |
|---|---|---|---|---|
| IOS-01 | P0 | Mac | M | Primera sesión Mac (`docs/IOS_STATUS.md`): `flutter pub get`, `cd ios && pod install` sin errores; `Podfile.lock` generado; deployment target 16.0 en Pods y Runner; macros `PERMISSION_CAMERA=1`, `PERMISSION_MICROPHONE=1` en `GCC_PREPROCESSOR_DEFINITIONS` de los Pods. Anotar versiones de Xcode y CocoaPods. |
| IOS-02 | P0 | Mac | M | Firma: en Xcode, Runner → Signing & Capabilities → tu equipo; bundle id `es.sonoglitch.app` (Runner y RunnerTests); `flutter build ios --release` compila sin warnings bloqueantes; `flutter run --release -d <iPhone>` arranca en el iPhone. |
| IOS-03 | P0 | IPH | M | Ejecutar en el iPhone todo lo marcado `IPH` en 4.1-4.17 (INS-12/13, CAM-01/02/03/06/07/16, CAP-09, RES-13, SAVE-07/08, A11Y-08, PERF-08, PRIV-13, UPG-07). Registrar en `docs/IOS_STATUS.md` lo que se confirme (lo pide el propio documento). |
| IOS-04 | P1 | PC | A | Textos de permiso en los idiomas que se publican: `Info.plist` solo tiene inglés y **no hay `ios/Runner/es.lproj/InfoPlist.strings`**: si la ficha del App Store se publica en español, Apple puede pedir (5.1.1) que el propósito sea claro para ese usuario; recomendación: añadir `InfoPlist.strings` en español antes de enviar. Marcar como defecto P1 de preparación si falta. |
| IOS-05 | P0 | PC | A | **`PrivacyInfo.xcprivacy`**: no existe en `ios/Runner/` (lista de ficheros del repo). Apple exige el manifiesto de privacidad para las *required reason APIs* (p. ej. `UserDefaults` que usa `shared_preferences`, `file timestamp` que usa `path_provider`): los plugins recientes traen el suyo, pero el de la app debe declarar `NSPrivacyTracking=false`, sin dominios de tracking, y los tipos de datos recopilados = ninguno. Crear antes del primer upload o App Store Connect avisará por correo (ITMS-91053). **Verificar** en el primer upload. |
| IOS-06 | P0 | PC | M | Etiquetas de privacidad (App Privacy en App Store Connect): «Data Not Collected». Coherente con PRIV-10 y con Data safety de Play. |
| IOS-07 | P0 | PC | A | Export compliance: la app usa `crypto` (HMAC-SHA256) solo para derivar semillas; no cifra datos ni comunicaciones. Añadir `ITSAppUsesNonExemptEncryption = NO` a `Info.plist` (hoy **falta**) para no responder el cuestionario en cada build; **verificar** que el uso de hash sin cifrado encaja en la exención. |
| IOS-08 | P1 | PC | A | `Info.plist`: `UISupportedInterfaceOrientations` declara Portrait + Landscape aunque la app bloquea vertical en Dart (`main.dart`); El bloque `~ipad` se eliminó el 29-oct-2026 y `TARGETED_DEVICE_FAMILY` es 1 (solo iPhone), por lo que no hacen falta capturas de iPad. Pendiente de decidir: limitar el plist a Portrait (coherente y evita que la revisión pruebe en horizontal) o comprobar UI-05. |
| IOS-09 | P1 | PC | M | Riesgos de App Review a repasar con el build en la mano: **2.1 Completitud** (sin placeholders: los 6 estilos ocultos no se ven; «Apoya el proyecto» oculto; sin texto «alpha» en la UI salvo la versión); **4.2 Funcionalidad mínima** (cámara con 6 estilos, exportación, 4 formatos, 3 composiciones: argumentar en las notas al revisor qué la diferencia de un filtro); **5.1.1 Privacidad** (los textos de permiso explican el propósito; el micrófono es opcional y el flujo funciona sin él: dejar claro en las notas al revisor que el audio no se graba); **2.3 Metadatos** (capturas hechas con el build, sin funciones inexistentes); **3.1.1** (sin donaciones ni enlaces externos de pago: el build iOS sin `DONATION_URL`); **2.5.4** (sin audio en segundo plano); **5.1.2** (sin compartir datos). Notas al revisor redactadas con la cuenta demo «no aplica: la app no tiene cuentas». |
| IOS-10 | P0 | Mac | M | Archivo y subida: `flutter build ipa --build-name=X.Y.Z --build-number=N --dart-define=APP_VERSION=X.Y.Z` (sin `DONATION_URL`) → Xcode Organizer → *Distribute → App Store Connect* (o Transporter). App Store Connect procesa el build sin avisos ITMS por correo (si llega ITMS-91053, volver a IOS-05). `CFBundleShortVersionString` = versión semántica, `CFBundleVersion` = contador iOS propio, anotados en el registro de subidas de `docs/RELEASING.md`. |
| IOS-11 | P0 | PC | M | Registro de la app en App Store Connect: nombre «Sonoglitch» disponible, bundle id registrado en el portal, SKU, idioma principal, categoría Fotografía y vídeo, precio gratis, sin compras. |
| IOS-12 | P0 | PC | M | Capturas para la ficha en los tamaños que exige App Store Connect en la fecha (hoy 6,9" obligatorio — 1320x2868 o 1290x2796 — y opcionalmente 6,5"/6,1"; **verificar** en App Store Connect → Media Manager), hechas en el iPhone real con el build candidato, sin datos personales; al menos 3 por idioma (en y es). |
| IOS-13 | P0 | PC | M | TestFlight interno: añadir tu Apple ID como tester interno (hasta 100, sin revisión); si se invitan externos, pasa la *Beta App Review* (misma lista de IOS-09). Notas de prueba y correo de contacto (`dev@mainshai.com`) rellenos. |
| IOS-14 | P0 | IPH | M | Instalar desde TestFlight en el iPhone (sesión de tu Apple ID en la app TestFlight, iniciada por ti): la invitación llega, «Instalar», abre en el onboarding; repetir INS-03, CAP-01, SAVE-07, SAVE-08 con esa build (es la que firma Apple, no la de desarrollo). Crashes de TestFlight: 0. |
| IOS-15 | P1 | SIM | M | Simulador (lo que se puede): compilar en Debug, arrancar, onboarding, diálogos de permiso, visor con error de cámara controlado (INS-14), Ajustes completos, idioma es/en (`Settings → General → Language`), Dynamic Type máximo, VoiceOver (Accessibility Inspector), iPhone SE (3.ª gen) y iPhone 16 Pro Max: sin solapes. |

---

## 5. Calendario de ejecución

### 5.1 Orden y reparto

| Fase | Entorno | Quién | Qué | Tiempo |
|---|---|---|---|---|
| **A. Windows + emulador** | EMU, PC | Asistente (automatiza) + tú (confirmas 10 capturas) | Congelar el build candidato (0.8, 0.9). Pasar `heavy.sh flutter test/analyze/format` una vez. PRIV-01/04/05/10/11 sobre el artefacto. INS-01…11, INS-14 (parcial), CAM-05/06/15, VF-01/08/09/10, AMB-07/09/14, AUTO-07, STY-01/03/04/06, RES-01/02/03 (con cámara virtual), SET-01/02/06/07, L10N-01…06, A11Y-04/05/07, UI-01/02/03/06, ROB-03/07/10, UPG-04. Capturas y `logcat` por caso. | Asistente 3-4 h de máquina; tú 30 min |
| **B. Pixel 10 Pro** | PX (+LOW) | Tú con el móvil; el asistente con `adb` si hay cable (instala, captura, `gfxinfo`, `meminfo`, logs) | Instalar el candidato (UPG-01 sobre la versión anterior). Luego en este orden, porque cada bloque deja el estado para el siguiente: INS-02…08 (requiere `pm clear`), CAM-01…04/06…14/16, VF-02…07/11…13, AMB-01…06/08/10…13/15…18, AUTO-01…06, STY-02/05, CAP-01…08, RES-04…12/14/15, SAVE-01/03…06/09, SET-03/04/05/08, A11Y-01/02/03/06/09, UI-04, PERF-01…06/09, ROB-01/02/05/06/08/09, PRIV-02/03/06/07/08/09, UPG-02/03/05. LOW: SAVE-02, PERF-07, RES-09 si hay dispositivo. | Tú ~3 h (dos sesiones); asistente 1 h |
| **C. Mac** | SIM, IPH | Tú (el asistente no tiene acceso al Mac; puede preparar los comandos y revisar logs que le pegues) | IOS-01/02 → IOS-15 (simulador, 30 min) → IOS-03 en el iPhone (todas las `IPH`, ~1,5 h) → IOS-04/05/07/08 (ficheros del proyecto; el asistente redacta los cambios en Windows y tú los compilas) → IOS-10…14 (TestFlight). Actualizar `docs/IOS_STATUS.md`. | Tú ~3 h + esperas de procesado de Apple |
| **D. Tiendas** | PC, EMU-PS, PX | Tú en las consolas; el asistente prepara textos y verifica contra el código | PLAY-01…09 (Play Console), PLAY-10/11 (ruta del tester), PLAY-12; IOS-06/09/11/12/13. Arranque de la prueba cerrada (14 días). | Tú ~2 h + 14 días |
| **E. Cierre** | — | Líder | PRIV-12 (`security-reviewer`), re-test de los FIX (sección 6), hoja de firma (6.3), fila en el registro de subidas de `docs/RELEASING.md`, `CHANGELOG.md`. | 1 h |

Lo que el asistente **puede automatizar desde Windows** con `adb`: instalación/desinstalación, `pm grant/revoke/clear`, inyección de sensores del emulador, `wm size/density`, `settings put` (escala de fuente, animaciones, TalkBack, modo noche), `monkey`, capturas y grabaciones, `gfxinfo/meminfo/batterystats/netstats/package`, lectura de `logcat`, análisis del APK/AAB (`aapt2`, `apksigner`, `unzip`, `strings`), y la recopilación de todo en `.local/qa/`. Lo que **no** puede: mirar la pantalla del Pixel sin cable, oír, mover el móvil, iniciar sesiones, usar el Mac, pulsar en las consolas de las tiendas.

### 5.2 Evidencias

- Carpeta por ejecución: `.local/qa/<AAAA-MM-DD>_<versión>+<build>/` (`.local/` está en `.gitignore`: nunca se sube). Dentro: `capturas/`, `videos/`, `logs/`, `informes/` (JSON de «Copiar informe»), `artefactos.txt` (nombres y SHA-256 de APK/AAB/IPA).
- Nombre de fichero: `<ID>_<entorno>_<nn>.png|mp4|txt` (p. ej. `CAM-03_PX_02.png`). Un caso con resultado FAIL lleva siempre una captura o vídeo **y** el `logcat`/consola del momento.
- Capturas Android: `adb exec-out screencap -p > fichero.png`; vídeo: `adb shell screenrecord --time-limit 60 /sdcard/x.mp4`; iOS: botón lateral + volumen arriba, o `xcrun simctl io booted screenshot`. Nada de la barra de estado con datos personales en las capturas que vayan a la tienda.
- Métricas (PERF) se anotan como números en el registro, con la escena y el estilo.

### 5.3 Cómo se registran los defectos

- Un defecto = un issue en el repositorio **privado** (`dferrandizmont/sonoglitch-dev`) con la plantilla `.github/ISSUE_TEMPLATE/bug_report.yml`, título `[<ID del caso>] <qué falla>`, severidad S1-S4 en etiqueta, build, entorno, pasos, esperado/obtenido, evidencias. El id del issue (`#NN`) se copia a la columna «Bug» del registro.
- Los defectos que afectan a la privacidad o a la seguridad **no** se abren como issue público ni se delegan: los gestiona el líder y se anotan en `.local/security-review.md`.
- Las dudas de producto (sección «Dudas abiertas» de este plan) se anotan en `.local/QUESTIONS.md` y las decides tú; no son defectos.

---

## 6. Re-test, regresión y firma final

### 6.1 Re-test

- Cada FIX se verifica repitiendo **el caso que falló** y los casos del mismo bloque marcados P0, en el **mismo entorno** y con el **nuevo build** (nuevo `versionCode`/`CFBundleVersion`: nunca se re-prueba «el mismo número recompilado», `docs/RELEASING.md`).
- Un arreglo en `lib/export/` o `lib/features/result/` obliga a repetir RES-01…08, RES-12, SAVE-01/04, SET-03/04 y CAP-04/05. Un arreglo en `lib/camera/` o `lib/features/viewfinder/` obliga a CAM-01…03/06/10, CAP-01…03, AUTO-01/05, PERF-01. Un arreglo en `lib/ambient/` obliga a AMB-01/02/04/05/06/08 y PRIV-08. Un cambio en shaders obliga a VF-01…05 y PERF-01 en el Pixel. Un cambio en `android/` o `ios/` obliga a PRIV-01…07 e INS-01…08 (o IOS-01…03).
- Máximo dos rondas FIX → re-test por defecto; a la tercera, decisión tuya: aplazar la función, degradarla o posponer la publicación.

### 6.2 Regresión mínima por cada build nuevo (≈ 45 min en el Pixel, 20 en el emulador)

Smoke obligatorio antes de cualquier subida (pista interna, TestFlight, release de GitHub): INS-01, INS-03, INS-06, CAM-01, CAM-02, CAM-03, CAM-06, VF-01, AMB-01, AMB-04, AUTO-01, CAP-01, CAP-04, RES-01, RES-02, RES-03, RES-07, RES-12, SAVE-01, SAVE-04, SET-01, SET-02, L10N-01, PRIV-01, PRIV-04, PRIV-05, PRIV-08, UPG-01. En iOS, los equivalentes `IPH` más IOS-10.

La regresión completa (todos los P0 y P1) se repite cuando cambia la versión **minor** o cuando se acumulan más de 10 FIX desde la última completa.

### 6.3 Hoja de firma (sign-off)

Antes de pulsar «Enviar a revisión» en cualquiera de las dos tiendas, todas las casillas en sí, con tu inicial y fecha en el registro:

- [ ] El artefacto subido es exactamente el probado (hash en `artefactos.txt` = hash del fichero en la consola).
- [ ] `dart format`, `flutter analyze`, `flutter test` en verde sobre el commit etiquetado (ejecutados por el líder con `heavy.sh`; CI del repo privado en verde).
- [ ] Todos los P0 en PASS en EMU + PX (Android) / IPH (iOS); ningún «no probado» entre los P0.
- [ ] Cero S1 abiertos; los P1 abiertos están aceptados por ti con nota en el registro.
- [ ] PRIV-01…PRIV-12 en PASS; `security-reviewer` sin hallazgos críticos/altos.
- [ ] Data safety (Play) y App Privacy (Apple) = «no se recopilan datos», con captura guardada.
- [ ] Textos de ficha, capturas y notas de la versión corresponden al build; política de privacidad accesible públicamente con la fecha correcta.
- [ ] `CHANGELOG.md` tiene la sección de la versión; `fastlane/.../changelogs/<build>.txt` existe; receta F-Droid actualizada (si procede).
- [ ] Fila añadida al registro de subidas de `docs/RELEASING.md` (fecha, canal, versión, build, commit, artefacto, resultado, símbolos archivados fuera del repo).
- [ ] Para Play: prueba cerrada creada con los 12 testers e instrucciones enviadas (incluida la de desinstalar las alphas de GitHub, UPG-02).
- [ ] Para iOS: `docs/IOS_STATUS.md` actualizado con lo verificado en el iPhone; `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption` y `InfoPlist.strings` resueltos (IOS-04/05/07).
- [ ] Emulador cerrado, worktrees eliminados, `.local/qa/` completo.

---

## Dudas abiertas encontradas al leer el código (para decidir antes de la fase A)

1. **Presión en la línea de contexto.** `settingsContextLineSubtitle` dice «fecha, dirección y presión», `context_sensors.dart` lee el barómetro de `sensors_plus` y `export_context.dart` imprime `hPa`; pero `docs/ARCHITECTURE.md` dice «No pressure or barometer» (referido al carril del shader `uSign.w`). Es coherente (contexto sí, shader no), pero en iOS el barómetro puede requerir `NSMotionUsageDescription` (lo apunta `docs/IOS_STATUS.md`): decidir si se declara o se desactiva la presión en iOS.
2. **JPEG en iOS** (RES-13): sin `ImageEncoderPlugin` en `AppDelegate.swift`, el ajuste «JPEG (alta calidad)» produciría siempre PNG. Decidir: implementar el encoder en Swift, ocultar la opción en iOS, o avisar en la UI.
3. **Persistencia del estilo** (STY-05): no hay clave en `AppSettings`; al reabrir la app volverá al primer estilo. ¿Es lo deseado?
4. **Formato de exportación no persistido** (RES-04): la composición y las lecturas se recuerdan, el formato no. ¿Intencionado?
5. **Espejo de la cámara frontal en la foto** (CAM-02): el visor espeja; comprobar en el Pixel si la foto exportada sale espejada o no, y decidir el comportamiento deseado (la mayoría de cámaras guardan la frontal sin espejar).
6. **Shaders de prueba en el bundle**: `test/effects/fixtures/*.frag` están registrados en `flutter.shaders` y viajan en el APK/AAB (ARCHITECTURE lo reconoce). Decidir si se excluyen antes de 1.0 (tamaño y limpieza).
7. **`Info.plist`**: orientaciones horizontales declaradas pese al bloqueo vertical; faltan `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption` e `InfoPlist.strings` en español; `TARGETED_DEVICE_FAMILY` sin verificar.
8. **AVD `Sonoglitch_Pixel`** usa la imagen `google_apis_playstore` pero `PlayStore.enabled=no`: verificar si la Play Store funciona o crear otro AVD para PLAY-10.
9. **Dos lectores de micrófono** (AMB-05): `noise_meter` y `SpectrumPlugin` abren `AudioRecord` a la vez. Funciona en el Pixel (alpha.10+ en campo) pero en otros fabricantes puede fallar uno; sin `LOW` queda sin cubrir.
10. **`targetSdkVersion`** real del manifiesto fusionado: depende de Flutter 3.47.7; comprobar que cumple el mínimo que exige Play en la fecha de subida.
11. **Resolución máxima de la cámara virtual del emulador**: si es pequeña, CAP-02 y RES-08 solo valen en el Pixel.
12. **Hoja de compartir: snackbar «Compartido.»** (SAVE-04): `share_plus` no siempre informa si el usuario completó o canceló; verificar qué muestra la app al cancelar.
