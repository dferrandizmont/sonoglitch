// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsContextLineTitle => 'Context line';

  @override
  String get settingsContextLineSubtitle =>
      'Adds the shot’s date, direction and pressure to Sound strip and Poster.';

  @override
  String get viewfinderMomentTooltip =>
      'Auto shot: takes the photo on a loud sound or sudden move';

  @override
  String get viewfinderMomentArmed =>
      'Waiting for a loud sound or a sudden move';

  @override
  String stylePickCalmBright(String style) {
    return 'Calm and bright: $style';
  }

  @override
  String stylePickCalmDark(String style) {
    return 'Calm and dark: $style';
  }

  @override
  String stylePickLoud(String style) {
    return 'Loud place: $style';
  }

  @override
  String stylePickMoving(String style) {
    return 'In motion: $style';
  }

  @override
  String stylePickMixed(String style) {
    return 'Mixed ambience: $style';
  }

  @override
  String get onboardingHeadline =>
      'A camera that lets the place distort the photo';

  @override
  String get onboardingIdea =>
      'The noise, the light and the movement around you are measured and used to distort the picture.';

  @override
  String get onboardingPrivacy =>
      'Audio is never recorded. Only the volume level is read, in memory, and it never leaves the phone.';

  @override
  String get onboardingGrant => 'Allow camera and microphone';

  @override
  String get onboardingCameraDenied =>
      'The camera permission is needed to take a photo.';

  @override
  String get onboardingMicrophoneDeniedNotice =>
      'No microphone: the noise stays at zero and the photo only shows the light and the movement.';

  @override
  String get onboardingPermanentlyDenied =>
      'Permission refused. Enable it in the system settings to continue.';

  @override
  String get onboardingOpenSettings => 'Open system settings';

  @override
  String get onboardingSkip => 'Continue without microphone';

  @override
  String get viewfinderShutterTooltip => 'Take a photo';

  @override
  String get viewfinderFlipTooltip => 'Switch camera';

  @override
  String get viewfinderSettingsTooltip => 'Settings';

  @override
  String get viewfinderCapturing => 'Capturing…';

  @override
  String get viewfinderCameraError => 'The camera could not be started.';

  @override
  String get viewfinderLegendNoiseTooltip => 'Noise: how loud the place is';

  @override
  String get viewfinderLegendLightTooltip => 'Light: bright or in shadow';

  @override
  String get viewfinderLegendMotionTooltip =>
      'Movement: how much the phone shakes';

  @override
  String get viewfinderLegendNoiseBody =>
      'Noise is how loud the place is. The louder it is, the more the photo breaks.';

  @override
  String get viewfinderLegendLightBody =>
      'Light is whether the scene is bright or in shadow. The darker it is, the stronger the effect.';

  @override
  String get viewfinderLegendMotionBody =>
      'Movement is how much the phone is being shaken. The more it moves, the more the photo breaks.';

  @override
  String get viewfinderTipDismiss => 'Dismiss the tip';

  @override
  String get levelNoise => 'Noise';

  @override
  String get levelLight => 'Light';

  @override
  String get levelMotion => 'Movement';

  @override
  String get stylesTitle => 'Styles';

  @override
  String get stylesSelected => 'Selected';

  @override
  String get resultTitle => 'Photo';

  @override
  String resultNoiseLabel(int db) {
    return 'Noise: about $db dB (approximate)';
  }

  @override
  String resultLightLabel(String level) {
    return 'Light: $level';
  }

  @override
  String resultMotionLabel(String level) {
    return 'Movement: $level';
  }

  @override
  String get resultLevelLow => 'low';

  @override
  String get resultLevelMedium => 'medium';

  @override
  String get resultLevelHigh => 'high';

  @override
  String get resultFormatLabel => 'Format';

  @override
  String get resultFormatOriginal => 'Original';

  @override
  String get resultFormatSquare => 'Square 1:1';

  @override
  String get resultFormatPortrait => 'Portrait 4:5';

  @override
  String get resultFormatStory => 'Story 9:16';

  @override
  String get resultLayoutLabel => 'Layout';

  @override
  String get resultLayoutFull => 'Full';

  @override
  String get resultLayoutSoundStrip => 'Sound strip';

  @override
  String get resultLayoutPoster => 'Poster';

  @override
  String get resultShowProcessedTooltip => 'Show the processed photo';

  @override
  String get resultCompareTooltip =>
      'Compare with the original (or hold the photo)';

  @override
  String get resultSave => 'Save';

  @override
  String get resultShare => 'Share';

  @override
  String get resultRetake => 'Retake';

  @override
  String get resultSaved => 'Photo saved in the gallery.';

  @override
  String get resultShared => 'Shared.';

  @override
  String get resultSaveFailed => 'The photo could not be saved.';

  @override
  String get resultShareFailed => 'The photo could not be shared.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsCameraSectionTitle => 'Camera';

  @override
  String get settingsTroubleshootingTitle => 'Troubleshooting';

  @override
  String get settingsWatermarkTitle => 'Watermark';

  @override
  String get settingsWatermarkSubtitle =>
      'Adds a discreet \"sonoglitch\" signature to the exported photo.';

  @override
  String get settingsDiagnosticsTitle => 'Diagnostics';

  @override
  String get settingsDiagnosticsSubtitle =>
      'Shows the on screen panel with the measured values.';

  @override
  String get settingsMomentKeepArmedTitle => 'Auto shot: keep waiting';

  @override
  String get settingsMomentKeepArmedSubtitle =>
      'Keeps waiting after every photo, so the next peak is caught too.';

  @override
  String get settingsTipsTitle => 'Show tips again';

  @override
  String get settingsTipsSubtitle =>
      'Brings back the tip that explains the three controls.';

  @override
  String get settingsTipsReset =>
      'The tip will show again on the camera screen.';

  @override
  String get settingsExportReportTitle => 'Export diagnostic report';

  @override
  String get settingsExportReportSubtitle =>
      'Shares a JSON report and the log file.';

  @override
  String get settingsAboutTitle => 'About';

  @override
  String settingsVersion(String version) {
    return 'Version $version';
  }

  @override
  String settingsLicense(String license) {
    return 'Licence: $license';
  }

  @override
  String get settingsPrivacyTitle => 'Privacy';

  @override
  String get settingsPrivacyBody =>
      'Everything happens on the phone. No accounts, no servers, no analytics. The microphone is only read for the volume level: no audio is stored or sent.';

  @override
  String get settingsSupportTitle => 'Support the project';

  @override
  String get debugCopyReport => 'Copy report';

  @override
  String get debugShareLogs => 'Share logs';

  @override
  String get debugReportCopied => 'Report copied to the clipboard.';

  @override
  String get debugShareFailed => 'The logs could not be shared.';

  @override
  String get debugAuto => 'Auto';

  @override
  String get debugManual => 'Manual';

  @override
  String get commonClose => 'Close';

  @override
  String get settingsQualityTitle => 'Photo quality';

  @override
  String get settingsQualitySubtitle =>
      'Standard: up to 2048 px. High: up to 4096 px. Maximum: native size, up to 24 MP. Device limits may reduce the size. PNG preserves the exported pixels.';

  @override
  String get qualityStandard => 'Standard';

  @override
  String get qualityHigh => 'High';

  @override
  String get qualityMaximum => 'Maximum';

  @override
  String get settingsFileTypeTitle => 'File type';

  @override
  String get settingsFileTypeSubtitle =>
      'PNG is lossless and keeps every exported pixel. JPEG is smaller and is encoded by the phone at quality 95.';

  @override
  String get fileTypePng => 'PNG (lossless)';

  @override
  String get fileTypeJpeg => 'JPEG (high quality)';

  @override
  String processingMegapixels(String megapixels) {
    return 'Processing $megapixels MP…';
  }

  @override
  String get settingsIntensityTitle => 'Intensity';

  @override
  String get settingsIntensitySubtitle =>
      'How strongly noise and movement affect your photos. Light is not affected.';

  @override
  String get intensitySubtle => 'Subtle';

  @override
  String get intensityNormal => 'Normal';

  @override
  String get intensityExtreme => 'Extreme';

  @override
  String viewfinderStyleButton(String name) {
    return 'Style: $name. Tap to choose';
  }

  @override
  String get viewfinderPrevStyle => 'Previous style';

  @override
  String get viewfinderNextStyle => 'Next style';

  @override
  String get viewfinderMetersTooltip =>
      'Live sound, light and movement. Tap for help';

  @override
  String get viewfinderHint =>
      'Sound, light and movement bend the picture. Swipe to change style.';

  @override
  String get helpTitle => 'How it works';

  @override
  String get helpOpen => 'How it works';

  @override
  String get helpSwipe =>
      'Swipe left or right on the picture, or use the arrows, to change style.';

  @override
  String get helpAutoShot =>
      'Auto shot waits and takes the photo by itself on a loud sound or a sudden move.';

  @override
  String get styleSheetRandom => 'Random';

  @override
  String get styleSheetMatch => 'Match this place';

  @override
  String get styleDescStatic => 'Digital bands and tearing';

  @override
  String get styleDescTape => 'Worn VHS: wobble, lines and grain';

  @override
  String get styleDescPhosphor => 'Old CRT screen with green trails';

  @override
  String get styleDescRipple => 'Sound spreads like waves on water';

  @override
  String get styleDescThermal => 'Heat-camera colours and contours';

  @override
  String get styleDescPrism => 'Flowing warp that splits colours';

  @override
  String get resultLayoutHintFull => 'Just the photo.';

  @override
  String get resultLayoutHintSoundStrip =>
      'Adds a band with the sound, light and movement.';

  @override
  String get resultLayoutHintPoster =>
      'A framed print with the style and readings.';

  @override
  String get processingLabel => 'Processing';

  @override
  String get resultReadingsLabel => 'Readings';

  @override
  String get resultReadingsFull => 'Full';

  @override
  String get resultReadingsNumbers => 'Numbers';

  @override
  String get resultReadingsHidden => 'Hidden';

  @override
  String get resultReadingsHintFull => 'Numbers, ladders and spectrum.';

  @override
  String get resultReadingsHintNumbers => 'Only the numbers and their labels.';

  @override
  String get resultReadingsHintHidden => 'No readings. The photo ID stays.';
}
