// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get settingsVolumeButtonsTitle => 'Botones de volumen';

  @override
  String get settingsVolumeButtonsSubtitle =>
      'Pulsa subir o bajar volumen para hacer la foto.';

  @override
  String get settingsContextLineTitle => 'Línea de contexto';

  @override
  String get settingsContextLineSubtitle =>
      'Añade la fecha, dirección y presión de la toma a Banda de sonido y Póster.';

  @override
  String get viewfinderMomentTooltip =>
      'Disparo auto: hace la foto con un ruido fuerte o un movimiento brusco';

  @override
  String get viewfinderMomentArmed =>
      'Esperando un ruido fuerte o un movimiento brusco';

  @override
  String stylePickCalmBright(String style) {
    return 'Calma y mucha luz: $style';
  }

  @override
  String stylePickCalmDark(String style) {
    return 'Calma y poca luz: $style';
  }

  @override
  String stylePickLoud(String style) {
    return 'Lugar ruidoso: $style';
  }

  @override
  String stylePickMoving(String style) {
    return 'En movimiento: $style';
  }

  @override
  String stylePickMixed(String style) {
    return 'Ambiente variado: $style';
  }

  @override
  String get onboardingHeadline =>
      'Una cámara que deja que el lugar deforme la foto';

  @override
  String get onboardingIdea =>
      'El ruido, la luz y el movimiento que te rodean se miden y se usan para deformar la imagen.';

  @override
  String get onboardingPrivacy =>
      'Nunca se graba audio. Solo se lee el nivel de volumen, en memoria, y nunca sale del teléfono.';

  @override
  String get onboardingGrant => 'Permitir cámara y micrófono';

  @override
  String get onboardingCameraDenied =>
      'El permiso de cámara hace falta para hacer fotos.';

  @override
  String get onboardingMicrophoneDeniedNotice =>
      'Sin micrófono: el ruido se queda en cero y la foto solo muestra la luz y el movimiento.';

  @override
  String get onboardingPermanentlyDenied =>
      'Permiso denegado. Actívalo en los ajustes del sistema para continuar.';

  @override
  String get onboardingOpenSettings => 'Abrir ajustes del sistema';

  @override
  String get onboardingSkip => 'Continuar sin micrófono';

  @override
  String get viewfinderShutterTooltip => 'Hacer una foto';

  @override
  String get viewfinderFlipTooltip => 'Cambiar de cámara';

  @override
  String get viewfinderSettingsTooltip => 'Ajustes';

  @override
  String get viewfinderCapturing => 'Capturando…';

  @override
  String get viewfinderCameraError => 'No se ha podido abrir la cámara.';

  @override
  String get viewfinderLegendNoiseTooltip =>
      'Ruido: lo fuerte que está el sitio';

  @override
  String get viewfinderLegendLightTooltip => 'Luz: iluminada o en sombra';

  @override
  String get viewfinderLegendMotionTooltip =>
      'Movimiento: cuánto se sacude el teléfono';

  @override
  String get viewfinderLegendNoiseBody =>
      'El ruido es lo fuerte que está el sitio. Cuanto más alto, más se rompe la foto.';

  @override
  String get viewfinderLegendLightBody =>
      'La luz es si la escena está iluminada o en sombra. Cuanto más oscura, más efecto tiene.';

  @override
  String get viewfinderLegendMotionBody =>
      'El movimiento es cuánto se está sacudiendo el teléfono. Cuanto más se mueve, más se rompe la foto.';

  @override
  String get viewfinderTipDismiss => 'Cerrar el consejo';

  @override
  String get levelNoise => 'Ruido';

  @override
  String get levelLight => 'Luz';

  @override
  String get levelMotion => 'Movimiento';

  @override
  String get stylesTitle => 'Estilos';

  @override
  String get stylesSelected => 'Seleccionado';

  @override
  String get resultTitle => 'Foto';

  @override
  String resultNoiseLabel(int db) {
    return 'Ruido: unos $db dB (aproximado)';
  }

  @override
  String resultLightLabel(String level) {
    return 'Luz: $level';
  }

  @override
  String resultMotionLabel(String level) {
    return 'Movimiento: $level';
  }

  @override
  String get resultLevelLow => 'baja';

  @override
  String get resultLevelMedium => 'media';

  @override
  String get resultLevelHigh => 'alta';

  @override
  String get resultFormatLabel => 'Formato';

  @override
  String get resultFormatOriginal => 'Original';

  @override
  String get resultFormatSquare => 'Cuadrado 1:1';

  @override
  String get resultFormatPortrait => 'Vertical 4:5';

  @override
  String get resultFormatStory => 'Historia 9:16';

  @override
  String get resultLayoutLabel => 'Composición';

  @override
  String get resultLayoutFull => 'Completa';

  @override
  String get resultLayoutSoundStrip => 'Banda de sonido';

  @override
  String get resultLayoutPoster => 'Póster';

  @override
  String get resultShowProcessedTooltip => 'Mostrar la foto procesada';

  @override
  String get resultCompareTooltip =>
      'Comparar con el original (o mantén pulsada la foto)';

  @override
  String get resultSave => 'Guardar';

  @override
  String get resultShare => 'Compartir';

  @override
  String get resultRetake => 'Repetir';

  @override
  String get resultSaved => 'Foto guardada en la galería.';

  @override
  String get resultShared => 'Compartido.';

  @override
  String get resultSaveFailed => 'No se ha podido guardar la foto.';

  @override
  String get resultShareFailed => 'No se ha podido compartir la foto.';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsCameraSectionTitle => 'Cámara';

  @override
  String get settingsTroubleshootingTitle => 'Solución de problemas';

  @override
  String get settingsWatermarkTitle => 'Marca de agua';

  @override
  String get settingsWatermarkSubtitle =>
      'Añade una firma discreta «sonoglitch» a la foto exportada.';

  @override
  String get settingsDiagnosticsTitle => 'Diagnóstico';

  @override
  String get settingsDiagnosticsSubtitle =>
      'Muestra el panel en pantalla con los valores medidos.';

  @override
  String get settingsMomentKeepArmedTitle => 'Disparo auto: seguir esperando';

  @override
  String get settingsMomentKeepArmedSubtitle =>
      'Sigue esperando después de cada foto, para pillar también el siguiente pico.';

  @override
  String get settingsTipsTitle => 'Mostrar los consejos otra vez';

  @override
  String get settingsTipsSubtitle =>
      'Vuelve a mostrar el consejo que explica los tres controles.';

  @override
  String get settingsTipsReset =>
      'El consejo se mostrará otra vez en la pantalla de la cámara.';

  @override
  String get settingsExportReportTitle => 'Exportar informe de diagnóstico';

  @override
  String get settingsExportReportSubtitle =>
      'Comparte un informe JSON y el archivo de registro.';

  @override
  String get settingsAboutTitle => 'Acerca de';

  @override
  String settingsVersion(String version) {
    return 'Versión $version';
  }

  @override
  String settingsLicense(String license) {
    return 'Licencia: $license';
  }

  @override
  String get settingsPrivacyTitle => 'Privacidad';

  @override
  String get settingsPrivacyBody =>
      'Todo ocurre en el teléfono. Sin cuentas, sin servidores, sin analíticas. El micrófono solo se lee para saber el nivel de volumen: no se guarda ni se envía ningún audio.';

  @override
  String get settingsSupportTitle => 'Apoya el proyecto';

  @override
  String get debugCopyReport => 'Copiar informe';

  @override
  String get debugShareLogs => 'Compartir registros';

  @override
  String get debugReportCopied => 'Informe copiado al portapapeles.';

  @override
  String get debugShareFailed => 'No se han podido compartir los registros.';

  @override
  String get debugAuto => 'Auto';

  @override
  String get debugManual => 'Manual';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get settingsQualityTitle => 'Calidad de foto';

  @override
  String get settingsQualitySubtitle =>
      'Estándar: hasta 2048 px. Alta: hasta 4096 px. Máxima: tamaño original, hasta 24 MP. Los límites del dispositivo pueden reducir el tamaño. PNG conserva los píxeles exportados.';

  @override
  String get qualityStandard => 'Estándar';

  @override
  String get qualityHigh => 'Alta';

  @override
  String get qualityMaximum => 'Máxima';

  @override
  String get settingsFileTypeTitle => 'Tipo de archivo';

  @override
  String get settingsFileTypeSubtitle =>
      'El PNG no tiene pérdidas y conserva cada píxel exportado. El JPEG pesa menos y lo codifica el teléfono con calidad 95.';

  @override
  String get fileTypePng => 'PNG (sin pérdidas)';

  @override
  String get fileTypeJpeg => 'JPEG (alta calidad)';

  @override
  String processingMegapixels(String megapixels) {
    return 'Procesando $megapixels MP…';
  }

  @override
  String get settingsIntensityTitle => 'Intensidad';

  @override
  String get settingsIntensitySubtitle =>
      'Cuánto influyen el ruido y el movimiento en tus fotos. La luz no se ve afectada.';

  @override
  String get intensitySubtle => 'Sutil';

  @override
  String get intensityNormal => 'Normal';

  @override
  String get intensityExtreme => 'Extrema';

  @override
  String viewfinderStyleButton(String name) {
    return 'Estilo: $name. Toca para elegir';
  }

  @override
  String get viewfinderPrevStyle => 'Estilo anterior';

  @override
  String get viewfinderNextStyle => 'Estilo siguiente';

  @override
  String get viewfinderMetersTooltip =>
      'Sonido, luz y movimiento en directo. Toca para ayuda';

  @override
  String get viewfinderHint =>
      'El sonido, la luz y el movimiento deforman la imagen. Desliza para cambiar de estilo.';

  @override
  String get helpTitle => 'Cómo funciona';

  @override
  String get helpOpen => 'Cómo funciona';

  @override
  String get helpSwipe =>
      'Desliza sobre la imagen, o usa las flechas, para cambiar de estilo.';

  @override
  String get helpAutoShot =>
      'El disparo auto espera y hace la foto solo con un ruido fuerte o un movimiento brusco.';

  @override
  String get styleSheetRandom => 'Al azar';

  @override
  String get styleSheetMatch => 'Según el lugar';

  @override
  String get styleDescStatic => 'Bandas y desgarros digitales';

  @override
  String get styleDescTape => 'VHS gastado: temblor, líneas y grano';

  @override
  String get styleDescPhosphor => 'Pantalla CRT antigua con estelas verdes';

  @override
  String get styleDescRipple => 'El sonido se extiende como ondas en el agua';

  @override
  String get styleDescThermal => 'Colores y curvas de cámara térmica';

  @override
  String get styleDescPrism => 'Deformación fluida que separa colores';

  @override
  String get resultLayoutHintFull => 'Solo la foto.';

  @override
  String get resultLayoutHintSoundStrip =>
      'Añade una banda con el sonido, la luz y el movimiento.';

  @override
  String get resultLayoutHintPoster => 'Un marco con el estilo y las lecturas.';

  @override
  String get processingLabel => 'Procesando';

  @override
  String get resultReadingsLabel => 'Lecturas';

  @override
  String get resultReadingsFull => 'Completas';

  @override
  String get resultReadingsNumbers => 'Solo números';

  @override
  String get resultReadingsHidden => 'Ocultas';

  @override
  String get resultReadingsHintFull => 'Números, escalas y espectro.';

  @override
  String get resultReadingsHintNumbers => 'Solo los números y sus etiquetas.';

  @override
  String get resultReadingsHintHidden =>
      'Sin lecturas. El ID de la foto se queda.';
}
