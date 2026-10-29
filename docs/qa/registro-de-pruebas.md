# Registro de pruebas de Sonoglitch

Plantilla de resultados del plan `docs/qa/plan-de-pruebas.md`. **Una tabla por ejecución** (un build en un entorno, o una fase), rellenada en el momento, no al final. Las evidencias viven en `.local/qa/<fecha>_<versión>+<build>/` (no se suben al repositorio); aquí solo se anota el nombre del fichero.

Valores de la columna **Resultado**: `PASS` · `FAIL` · `BLOQ` (bloqueado por otro fallo o por falta de entorno) · `N/P` (no probado) · `N/A` (no aplica a este entorno) · `VERIF` (comportamiento observado y anotado, pendiente de decisión de producto).

Un `FAIL` lleva siempre un **Bug** (issue `#NN` del repositorio privado) y al menos una evidencia. Un P0 en `N/P` cuenta como fallo para el criterio go/no-go.

---

## Resumen de ejecuciones

| Ejecución | Fecha | Versión + build | Commit | Entorno(s) | P0 PASS / total | P1 PASS / total | S1 abiertos | Go/No-go | Firma |
|---|---|---|---|---|---|---|---|---|---|
| E1 | | | | | / | / | | | |
| E2 | | | | | / | / | | | |

---

## Ejecución E1

**Fecha:** AAAA-MM-DD · **Build:** `X.Y.Z+N` (`APP_VERSION=`) · **Commit:** `abc1234` · **Artefacto y SHA-256:** `sonoglitch-X.Y.Z.apk` `…` · **Fase:** A/B/C/D · **Entorno(s):** EMU / EMU-PS / PX / LOW / SIM / IPH / PC (modelo y versión de SO exactos; para el emulador, nombre del AVD e imagen) · **Quién ejecuta:** · **Notas de preparación:** (permisos reiniciados con `pm clear`, escala de fuente, idioma del sistema, estilo/calidad iniciales…)

| Fecha | Build/versión | Entorno | Caso | Resultado | Evidencia | Bug | Notas |
|---|---|---|---|---|---|---|---|
| | | | INS-01 | | | | |
| | | | INS-02 | | | | |
| | | | INS-03 | | | | |
| | | | INS-04 | | | | |
| | | | INS-05 | | | | |
| | | | INS-06 | | | | |
| | | | INS-07 | | | | |
| | | | INS-08 | | | | |
| | | | INS-09 | | | | |
| | | | INS-10 | | | | |
| | | | INS-11 | | | | |
| | | | INS-12 | | | | |
| | | | INS-13 | | | | |
| | | | INS-14 | | | | |
| | | | CAM-01 | | | | |
| | | | CAM-02 | | | | |
| | | | CAM-03 | | | | |
| | | | CAM-04 | | | | |
| | | | CAM-05 | | | | |
| | | | CAM-06 | | | | |
| | | | CAM-07 | | | | |
| | | | CAM-08 | | | | |
| | | | CAM-09 | | | | |
| | | | CAM-10 | | | | |
| | | | CAM-11 | | | | |
| | | | CAM-12 | | | | |
| | | | CAM-13 | | | | |
| | | | CAM-14 | | | | |
| | | | CAM-15 | | | | |
| | | | CAM-16 | | | | |
| | | | VF-01 | | | | |
| | | | VF-02 | | | | |
| | | | VF-03 | | | | |
| | | | VF-04 | | | | |
| | | | VF-05 | | | | |
| | | | VF-06 | | | | |
| | | | VF-07 | | | | |
| | | | VF-08 | | | | |
| | | | VF-09 | | | | |
| | | | VF-10 | | | | |
| | | | VF-11 | | | | |
| | | | VF-12 | | | | |
| | | | VF-13 | | | | |
| | | | AMB-01 | | | | |
| | | | AMB-02 | | | | |
| | | | AMB-03 | | | | |
| | | | AMB-04 | | | | |
| | | | AMB-05 | | | | |
| | | | AMB-06 | | | | |
| | | | AMB-07 | | | | |
| | | | AMB-08 | | | | |
| | | | AMB-09 | | | | |
| | | | AMB-10 | | | | |
| | | | AMB-11 | | | | |
| | | | AMB-12 | | | | |
| | | | AMB-13 | | | | |
| | | | AMB-14 | | | | |
| | | | AMB-15 | | | | |
| | | | AMB-16 | | | | |
| | | | AMB-17 | | | | |
| | | | AMB-18 | | | | |
| | | | AUTO-01 | | | | |
| | | | AUTO-02 | | | | |
| | | | AUTO-03 | | | | |
| | | | AUTO-04 | | | | |
| | | | AUTO-05 | | | | |
| | | | AUTO-06 | | | | |
| | | | AUTO-07 | | | | |
| | | | STY-01 | | | | |
| | | | STY-02 | | | | |
| | | | STY-03 | | | | |
| | | | STY-04 | | | | |
| | | | STY-05 | | | | |
| | | | STY-06 | | | | |
| | | | CAP-01 | | | | |
| | | | CAP-02 | | | | |
| | | | CAP-03 | | | | |
| | | | CAP-04 | | | | |
| | | | CAP-05 | | | | |
| | | | CAP-06 | | | | |
| | | | CAP-07 | | | | |
| | | | CAP-08 | | | | |
| | | | CAP-09 | | | | |
| | | | RES-01 | | | | |
| | | | RES-02 | | | | |
| | | | RES-03 | | | | |
| | | | RES-04 | | | | |
| | | | RES-05 | | | | |
| | | | RES-06 | | | | |
| | | | RES-07 | | | | |
| | | | RES-08 | | | | |
| | | | RES-09 | | | | |
| | | | RES-10 | | | | |
| | | | RES-11 | | | | |
| | | | RES-12 | | | | |
| | | | RES-13 | | | | |
| | | | RES-14 | | | | |
| | | | RES-15 | | | | |
| | | | SAVE-01 | | | | |
| | | | SAVE-02 | | | | |
| | | | SAVE-03 | | | | |
| | | | SAVE-04 | | | | |
| | | | SAVE-05 | | | | |
| | | | SAVE-06 | | | | |
| | | | SAVE-07 | | | | |
| | | | SAVE-08 | | | | |
| | | | SAVE-09 | | | | |
| | | | SET-01 | | | | |
| | | | SET-02 | | | | |
| | | | SET-03 | | | | |
| | | | SET-04 | | | | |
| | | | SET-05 | | | | |
| | | | SET-06 | | | | |
| | | | SET-07 | | | | |
| | | | SET-08 | | | | |
| | | | L10N-01 | | | | |
| | | | L10N-02 | | | | |
| | | | L10N-03 | | | | |
| | | | L10N-04 | | | | |
| | | | L10N-05 | | | | |
| | | | L10N-06 | | | | |
| | | | A11Y-01 | | | | |
| | | | A11Y-02 | | | | |
| | | | A11Y-03 | | | | |
| | | | A11Y-04 | | | | |
| | | | A11Y-05 | | | | |
| | | | A11Y-06 | | | | |
| | | | A11Y-07 | | | | |
| | | | A11Y-08 | | | | |
| | | | A11Y-09 | | | | |
| | | | UI-01 | | | | |
| | | | UI-02 | | | | |
| | | | UI-03 | | | | |
| | | | UI-04 | | | | |
| | | | UI-05 | | | | |
| | | | UI-06 | | | | |
| | | | PERF-01 | | | | p50/p95 por estilo: Static … Tape … Phosphor … Ripple … Thermal … Prism … |
| | | | PERF-02 | | | | take/decode/render/encode: |
| | | | PERF-03 | | | | PSS base/pico/vuelta (MB): |
| | | | PERF-04 | | | | % batería 15 min, estado térmico: |
| | | | PERF-05 | | | | TotalTime ms: |
| | | | PERF-06 | | | | |
| | | | PERF-07 | | | | |
| | | | PERF-08 | | | | |
| | | | PERF-09 | | | | |
| | | | ROB-01 | | | | |
| | | | ROB-02 | | | | |
| | | | ROB-03 | | | | |
| | | | ROB-04 | | | | |
| | | | ROB-05 | | | | |
| | | | ROB-06 | | | | |
| | | | ROB-07 | | | | |
| | | | ROB-08 | | | | |
| | | | ROB-09 | | | | |
| | | | ROB-10 | | | | |
| | | | PRIV-01 | | | | permisos listados, targetSdk, versionCode: |
| | | | PRIV-02 | | | | |
| | | | PRIV-03 | | | | |
| | | | PRIV-04 | | | | |
| | | | PRIV-05 | | | | SHA-256 del certificado: |
| | | | PRIV-06 | | | | |
| | | | PRIV-07 | | | | |
| | | | PRIV-08 | | | | |
| | | | PRIV-09 | | | | |
| | | | PRIV-10 | | | | |
| | | | PRIV-11 | | | | |
| | | | PRIV-12 | | | | |
| | | | PRIV-13 | | | | |
| | | | UPG-01 | | | | |
| | | | UPG-02 | | | | |
| | | | UPG-03 | | | | |
| | | | UPG-04 | | | | |
| | | | UPG-05 | | | | |
| | | | UPG-06 | | | | |
| | | | UPG-07 | | | | |
| | | | PLAY-01 | | | | |
| | | | PLAY-02 | | | | |
| | | | PLAY-03 | | | | |
| | | | PLAY-04 | | | | |
| | | | PLAY-05 | | | | |
| | | | PLAY-06 | | | | |
| | | | PLAY-07 | | | | |
| | | | PLAY-08 | | | | |
| | | | PLAY-09 | | | | |
| | | | PLAY-10 | | | | |
| | | | PLAY-11 | | | | |
| | | | PLAY-12 | | | | |
| | | | IOS-01 | | | | |
| | | | IOS-02 | | | | |
| | | | IOS-03 | | | | |
| | | | IOS-04 | | | | |
| | | | IOS-05 | | | | |
| | | | IOS-06 | | | | |
| | | | IOS-07 | | | | |
| | | | IOS-08 | | | | |
| | | | IOS-09 | | | | |
| | | | IOS-10 | | | | |
| | | | IOS-11 | | | | |
| | | | IOS-12 | | | | |
| | | | IOS-13 | | | | |
| | | | IOS-14 | | | | |
| | | | IOS-15 | | | | |

**Totales E1:** P0 PASS __ / __ · P1 PASS __ / __ · P2 PASS __ / __ · FAIL __ · BLOQ __ · N/P __ · **Decisión:** GO / NO-GO · **Firma y fecha:**

---

## Ejecución E2 (re-test / regresión)

Copiar la tabla anterior dejando solo los casos que se repiten (sección 6.1 del plan: el caso que falló más los P0 de su bloque, o el smoke de 6.2). Indicar en **Notas de preparación** qué bug motivó la ejecución.

| Fecha | Build/versión | Entorno | Caso | Resultado | Evidencia | Bug | Notas |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

---

## Tabla de defectos

Un defecto por fila. El **Id** es el número del issue en el repositorio privado (`#NN`); si todavía no se ha abierto, `BUG-nn` provisional. **Sev.** S1-S4 según la sección 1.4 del plan. **Prioridad** P0/P1/P2 heredada del caso. **Estado:** `Abierto` · `En arreglo` · `Arreglado (pendiente re-test)` · `Cerrado` · `Aceptado con nota` (P1/P2 que se publica igual, con tu inicial) · `Descartado`.

| Id | Caso(s) | Sev. | Prio. | Entorno | Build detectado | Título | Pasos mínimos / esperado vs obtenido | Evidencia | Estado | Build arreglado | Re-test (ejecución, resultado) | Decisión / notas |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | | |
| | | | | | | | | | | | | |

### Dudas de producto registradas (no son defectos)

Las de la sección «Dudas abiertas» del plan y las que surjan al probar; se copian a `.local/QUESTIONS.md` y las decide el propietario.

| # | Caso | Duda | Observado | Decisión | Fecha |
|---|---|---|---|---|---|
| 1 | SET-04 / IOS | Presión (barómetro) en la línea de contexto en iOS sin `NSMotionUsageDescription` | | | |
| 2 | RES-13 | JPEG en iOS sin encoder nativo | | | |
| 3 | STY-05 | Persistencia del estilo entre arranques | | | |
| 4 | RES-04 | Formato de exportación no persistido | | | |
| 5 | CAM-02 | Espejo de la cámara frontal en la foto | | | |
| 6 | PLAY-01 | Shaders de test en el bundle | | | |
| 7 | IOS-04/05/07/08 | `InfoPlist.strings`, `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption`, orientaciones, `TARGETED_DEVICE_FAMILY` | | | |
| 8 | PLAY-10 | AVD con Play Store usable | | | |
| 9 | AMB-05 | Dos lectores de micrófono en otros fabricantes | | | |
| 10 | PRIV-01 | `targetSdkVersion` real frente al mínimo de Play | | | |
| 11 | CAP-02 | Resolución máxima de la cámara virtual del emulador | | | |
| 12 | SAVE-04 | Snackbar «Compartido.» al cancelar la hoja | | | |

---

## Hoja de firma final

Copia de la sección 6.3 del plan, para marcar en la última ejecución antes de enviar a cada tienda.

| Comprobación | Android (Play) | iOS (App Store) | Inicial / fecha |
|---|---|---|---|
| Artefacto subido = artefacto probado (hash) | | | |
| `dart format`, `flutter analyze`, `flutter test` en verde sobre el commit etiquetado | | | |
| Todos los P0 en PASS, ninguno N/P | | | |
| Cero S1 abiertos; P1 abiertos aceptados con nota | | | |
| PRIV-01…12 en PASS; `security-reviewer` sin críticos/altos | | | |
| Data safety / App Privacy = no se recopilan datos (captura) | | | |
| Ficha, capturas y notas de versión corresponden al build; política pública con fecha correcta | | | |
| `CHANGELOG.md`, `fastlane/.../changelogs/<build>.txt`, receta F-Droid | | n/a | |
| Fila en el registro de subidas de `docs/RELEASING.md` | | | |
| Prueba cerrada creada, 12 testers, instrucciones enviadas (incl. desinstalar alphas) | | n/a | |
| `docs/IOS_STATUS.md` actualizado; `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption`, `InfoPlist.strings` resueltos | n/a | | |
| Emulador cerrado, worktrees eliminados, `.local/qa/` completo | | | |
