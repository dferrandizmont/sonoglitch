import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @settingsContextLineTitle.
  ///
  /// In en, this message translates to:
  /// **'Context line'**
  String get settingsContextLineTitle;

  /// No description provided for @settingsContextLineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adds the shot’s date, direction and pressure to Sound strip and Poster.'**
  String get settingsContextLineSubtitle;

  /// Tooltip and semantic label of the Auto shot button.
  ///
  /// In en, this message translates to:
  /// **'Auto shot: takes the photo on a loud sound or sudden move'**
  String get viewfinderMomentTooltip;

  /// Small label shown while the camera waits for the peak.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a loud sound or a sudden move'**
  String get viewfinderMomentArmed;

  /// One-line explanation of the style chosen from the current ambience.
  ///
  /// In en, this message translates to:
  /// **'Calm and bright: {style}'**
  String stylePickCalmBright(String style);

  /// One-line explanation of the style chosen from the current ambience.
  ///
  /// In en, this message translates to:
  /// **'Calm and dark: {style}'**
  String stylePickCalmDark(String style);

  /// One-line explanation of the style chosen from the current ambience.
  ///
  /// In en, this message translates to:
  /// **'Loud place: {style}'**
  String stylePickLoud(String style);

  /// One-line explanation of the style chosen from the current ambience.
  ///
  /// In en, this message translates to:
  /// **'In motion: {style}'**
  String stylePickMoving(String style);

  /// One-line explanation of the style chosen from the current ambience.
  ///
  /// In en, this message translates to:
  /// **'Mixed ambience: {style}'**
  String stylePickMixed(String style);

  /// Title of the first screen.
  ///
  /// In en, this message translates to:
  /// **'A camera that lets the place distort the photo'**
  String get onboardingHeadline;

  /// One sentence explaining the idea of the app.
  ///
  /// In en, this message translates to:
  /// **'The noise, the light and the movement around you are measured and used to distort the picture.'**
  String get onboardingIdea;

  /// One sentence explaining that no audio is recorded.
  ///
  /// In en, this message translates to:
  /// **'Audio is never recorded. Only the volume level is read, in memory, and it never leaves the phone.'**
  String get onboardingPrivacy;

  /// Button that asks for the camera and microphone permissions.
  ///
  /// In en, this message translates to:
  /// **'Allow camera and microphone'**
  String get onboardingGrant;

  /// Shown when the camera permission was refused.
  ///
  /// In en, this message translates to:
  /// **'The camera permission is needed to take a photo.'**
  String get onboardingCameraDenied;

  /// Small notice shown when only the microphone permission was refused.
  ///
  /// In en, this message translates to:
  /// **'No microphone: the noise stays at zero and the photo only shows the light and the movement.'**
  String get onboardingMicrophoneDeniedNotice;

  /// Shown when a permission is permanently denied.
  ///
  /// In en, this message translates to:
  /// **'Permission refused. Enable it in the system settings to continue.'**
  String get onboardingPermanentlyDenied;

  /// Button that opens the system settings page of the app.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get onboardingOpenSettings;

  /// Button that continues when the microphone was refused.
  ///
  /// In en, this message translates to:
  /// **'Continue without microphone'**
  String get onboardingSkip;

  /// Tooltip of the shutter button.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get viewfinderShutterTooltip;

  /// Tooltip of the flip camera button.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get viewfinderFlipTooltip;

  /// Tooltip of the settings button.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get viewfinderSettingsTooltip;

  /// Short non blocking progress message while the photo is taken.
  ///
  /// In en, this message translates to:
  /// **'Capturing…'**
  String get viewfinderCapturing;

  /// Message shown when the camera fails to start.
  ///
  /// In en, this message translates to:
  /// **'The camera could not be started.'**
  String get viewfinderCameraError;

  /// Tooltip of the icon of the noise level.
  ///
  /// In en, this message translates to:
  /// **'Noise: how loud the place is'**
  String get viewfinderLegendNoiseTooltip;

  /// Tooltip of the icon of the light level.
  ///
  /// In en, this message translates to:
  /// **'Light: bright or in shadow'**
  String get viewfinderLegendLightTooltip;

  /// Tooltip of the icon of the movement level.
  ///
  /// In en, this message translates to:
  /// **'Movement: how much the phone shakes'**
  String get viewfinderLegendMotionTooltip;

  /// Explanation of the noise level in the sheet.
  ///
  /// In en, this message translates to:
  /// **'Noise is how loud the place is. The louder it is, the more the photo breaks.'**
  String get viewfinderLegendNoiseBody;

  /// Explanation of the light level in the sheet.
  ///
  /// In en, this message translates to:
  /// **'Light is whether the scene is bright or in shadow. The darker it is, the stronger the effect.'**
  String get viewfinderLegendLightBody;

  /// Explanation of the movement level in the sheet.
  ///
  /// In en, this message translates to:
  /// **'Movement is how much the phone is being shaken. The more it moves, the more the photo breaks.'**
  String get viewfinderLegendMotionBody;

  /// Tooltip and semantics label of the button that closes the tip.
  ///
  /// In en, this message translates to:
  /// **'Dismiss the tip'**
  String get viewfinderTipDismiss;

  /// Label of the noise level indicator.
  ///
  /// In en, this message translates to:
  /// **'Noise'**
  String get levelNoise;

  /// Label of the light level indicator.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get levelLight;

  /// Label of the movement level indicator.
  ///
  /// In en, this message translates to:
  /// **'Movement'**
  String get levelMotion;

  /// Title of the styles screen.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get stylesTitle;

  /// Badge shown next to the selected style.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get stylesSelected;

  /// Title of the result screen.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get resultTitle;

  /// Measured noise level. The dB figure is not calibrated.
  ///
  /// In en, this message translates to:
  /// **'Noise: about {db} dB (approximate)'**
  String resultNoiseLabel(int db);

  /// Measured light level.
  ///
  /// In en, this message translates to:
  /// **'Light: {level}'**
  String resultLightLabel(String level);

  /// Measured movement level.
  ///
  /// In en, this message translates to:
  /// **'Movement: {level}'**
  String resultMotionLabel(String level);

  /// Low level label.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get resultLevelLow;

  /// Medium level label.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get resultLevelMedium;

  /// High level label.
  ///
  /// In en, this message translates to:
  /// **'high'**
  String get resultLevelHigh;

  /// Label of the export format selector.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get resultFormatLabel;

  /// Original aspect ratio.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get resultFormatOriginal;

  /// Square crop.
  ///
  /// In en, this message translates to:
  /// **'Square 1:1'**
  String get resultFormatSquare;

  /// Portrait crop.
  ///
  /// In en, this message translates to:
  /// **'Portrait 4:5'**
  String get resultFormatPortrait;

  /// Vertical crop for the stories.
  ///
  /// In en, this message translates to:
  /// **'Story 9:16'**
  String get resultFormatStory;

  /// Label of the export layout selector.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get resultLayoutLabel;

  /// Layout with the picture alone.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get resultLayoutFull;

  /// Layout with a band of the measured values under the picture.
  ///
  /// In en, this message translates to:
  /// **'Sound strip'**
  String get resultLayoutSoundStrip;

  /// Layout with a frame and the measured values.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get resultLayoutPoster;

  /// Tooltip of the button that brings the processed photo back.
  ///
  /// In en, this message translates to:
  /// **'Show the processed photo'**
  String get resultShowProcessedTooltip;

  /// Tooltip and semantics label of the button that compares the photo with the original one.
  ///
  /// In en, this message translates to:
  /// **'Compare with the original (or hold the photo)'**
  String get resultCompareTooltip;

  /// Button that saves the photo in the gallery.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get resultSave;

  /// Button that shares the photo.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get resultShare;

  /// Button that goes back to the viewfinder.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get resultRetake;

  /// Snackbar shown after saving the photo.
  ///
  /// In en, this message translates to:
  /// **'Photo saved in the gallery.'**
  String get resultSaved;

  /// Snackbar shown after sharing the photo.
  ///
  /// In en, this message translates to:
  /// **'Shared.'**
  String get resultShared;

  /// Snackbar shown when saving fails.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be saved.'**
  String get resultSaveFailed;

  /// Snackbar shown when sharing fails.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be shared.'**
  String get resultShareFailed;

  /// Title of the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Title of the section of the settings of the camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get settingsCameraSectionTitle;

  /// Title of the section of the settings that help when something goes wrong.
  ///
  /// In en, this message translates to:
  /// **'Troubleshooting'**
  String get settingsTroubleshootingTitle;

  /// Title of the watermark switch.
  ///
  /// In en, this message translates to:
  /// **'Watermark'**
  String get settingsWatermarkTitle;

  /// Subtitle of the watermark switch.
  ///
  /// In en, this message translates to:
  /// **'Adds a discreet \"sonoglitch\" signature to the exported photo.'**
  String get settingsWatermarkSubtitle;

  /// Title of the diagnostics switch.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnosticsTitle;

  /// Subtitle of the diagnostics switch.
  ///
  /// In en, this message translates to:
  /// **'Shows the on screen panel with the measured values.'**
  String get settingsDiagnosticsSubtitle;

  /// Title of the switch that keeps the auto shot mode armed.
  ///
  /// In en, this message translates to:
  /// **'Auto shot: keep waiting'**
  String get settingsMomentKeepArmedTitle;

  /// Subtitle of the switch that keeps the auto shot mode armed.
  ///
  /// In en, this message translates to:
  /// **'Keeps waiting after every photo, so the next peak is caught too.'**
  String get settingsMomentKeepArmedSubtitle;

  /// Title of the row that brings the tip of the viewfinder back.
  ///
  /// In en, this message translates to:
  /// **'Show tips again'**
  String get settingsTipsTitle;

  /// Subtitle of the row that brings the tip back.
  ///
  /// In en, this message translates to:
  /// **'Brings back the tip that explains the three controls.'**
  String get settingsTipsSubtitle;

  /// Snackbar shown after the tip is brought back.
  ///
  /// In en, this message translates to:
  /// **'The tip will show again on the camera screen.'**
  String get settingsTipsReset;

  /// Title of the row that exports the diagnostic report.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostic report'**
  String get settingsExportReportTitle;

  /// Subtitle of the diagnostic report row.
  ///
  /// In en, this message translates to:
  /// **'Shares a JSON report and the log file.'**
  String get settingsExportReportSubtitle;

  /// Title of the about section.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutTitle;

  /// Application version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersion(String version);

  /// Licence of the application.
  ///
  /// In en, this message translates to:
  /// **'Licence: {license}'**
  String settingsLicense(String license);

  /// Title of the privacy statement.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacyTitle;

  /// Body of the privacy statement.
  ///
  /// In en, this message translates to:
  /// **'Everything happens on the phone. No accounts, no servers, no analytics. The microphone is only read for the volume level: no audio is stored or sent.'**
  String get settingsPrivacyBody;

  /// Title of the optional donation row.
  ///
  /// In en, this message translates to:
  /// **'Support the project'**
  String get settingsSupportTitle;

  /// Button that copies the diagnostic report to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get debugCopyReport;

  /// Button that shares the log file.
  ///
  /// In en, this message translates to:
  /// **'Share logs'**
  String get debugShareLogs;

  /// Snackbar shown after copying the report.
  ///
  /// In en, this message translates to:
  /// **'Report copied to the clipboard.'**
  String get debugReportCopied;

  /// Snackbar shown when sharing the logs fails.
  ///
  /// In en, this message translates to:
  /// **'The logs could not be shared.'**
  String get debugShareFailed;

  /// Badge of the diagnostics panel when the values are measured.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get debugAuto;

  /// Label of the switch and badge of the manual mode of the diagnostics panel.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get debugManual;

  /// Close button.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @settingsQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo quality'**
  String get settingsQualityTitle;

  /// No description provided for @settingsQualitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Standard: up to 2048 px. High: up to 4096 px. Maximum: native size, up to 24 MP. Device limits may reduce the size. PNG preserves the exported pixels.'**
  String get settingsQualitySubtitle;

  /// No description provided for @qualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get qualityStandard;

  /// No description provided for @qualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get qualityHigh;

  /// No description provided for @qualityMaximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get qualityMaximum;

  /// No description provided for @settingsFileTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'File type'**
  String get settingsFileTypeTitle;

  /// No description provided for @settingsFileTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'PNG is lossless and keeps every exported pixel. JPEG is smaller and is encoded by the phone at quality 95.'**
  String get settingsFileTypeSubtitle;

  /// No description provided for @fileTypePng.
  ///
  /// In en, this message translates to:
  /// **'PNG (lossless)'**
  String get fileTypePng;

  /// No description provided for @fileTypeJpeg.
  ///
  /// In en, this message translates to:
  /// **'JPEG (high quality)'**
  String get fileTypeJpeg;

  /// No description provided for @processingMegapixels.
  ///
  /// In en, this message translates to:
  /// **'Processing {megapixels} MP…'**
  String processingMegapixels(String megapixels);

  /// No description provided for @settingsIntensityTitle.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get settingsIntensityTitle;

  /// No description provided for @settingsIntensitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How strongly noise and movement affect your photos. Light is not affected.'**
  String get settingsIntensitySubtitle;

  /// No description provided for @intensitySubtle.
  ///
  /// In en, this message translates to:
  /// **'Subtle'**
  String get intensitySubtle;

  /// No description provided for @intensityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get intensityNormal;

  /// No description provided for @intensityExtreme.
  ///
  /// In en, this message translates to:
  /// **'Extreme'**
  String get intensityExtreme;

  /// Semantics label of the button that opens the sheet of the styles.
  ///
  /// In en, this message translates to:
  /// **'Style: {name}. Tap to choose'**
  String viewfinderStyleButton(String name);

  /// Tooltip and semantics label of the button that selects the previous style.
  ///
  /// In en, this message translates to:
  /// **'Previous style'**
  String get viewfinderPrevStyle;

  /// Tooltip and semantics label of the button that selects the next style.
  ///
  /// In en, this message translates to:
  /// **'Next style'**
  String get viewfinderNextStyle;

  /// Tooltip and semantics label of the card of the three levels.
  ///
  /// In en, this message translates to:
  /// **'Live sound, light and movement. Tap for help'**
  String get viewfinderMetersTooltip;

  /// Text of the hint that is shown the first time the viewfinder is opened.
  ///
  /// In en, this message translates to:
  /// **'Sound, light and movement bend the picture. Swipe to change style.'**
  String get viewfinderHint;

  /// Title of the sheet that explains how the app works.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get helpTitle;

  /// Label of the button that opens the sheet that explains how the app works.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get helpOpen;

  /// Explanation of how the style is changed, in the help sheet.
  ///
  /// In en, this message translates to:
  /// **'Swipe left or right on the picture, or use the arrows, to change style.'**
  String get helpSwipe;

  /// Explanation of the auto shot mode, in the help sheet.
  ///
  /// In en, this message translates to:
  /// **'Auto shot waits and takes the photo by itself on a loud sound or a sudden move.'**
  String get helpAutoShot;

  /// Button that selects a random style.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get styleSheetRandom;

  /// Button that selects the style that fits the place.
  ///
  /// In en, this message translates to:
  /// **'Match this place'**
  String get styleSheetMatch;

  /// One-line description of the Static style.
  ///
  /// In en, this message translates to:
  /// **'Digital bands and tearing'**
  String get styleDescStatic;

  /// One-line description of the Tape style.
  ///
  /// In en, this message translates to:
  /// **'Worn VHS: wobble, lines and grain'**
  String get styleDescTape;

  /// One-line description of the Phosphor style.
  ///
  /// In en, this message translates to:
  /// **'Old CRT screen with green trails'**
  String get styleDescPhosphor;

  /// One-line description of the Ripple style.
  ///
  /// In en, this message translates to:
  /// **'Sound spreads like waves on water'**
  String get styleDescRipple;

  /// One-line description of the Thermal style.
  ///
  /// In en, this message translates to:
  /// **'Heat-camera colours and contours'**
  String get styleDescThermal;

  /// One-line description of the Prism style.
  ///
  /// In en, this message translates to:
  /// **'Flowing warp that splits colours'**
  String get styleDescPrism;

  /// Hint that explains the layout with the picture alone.
  ///
  /// In en, this message translates to:
  /// **'Just the photo.'**
  String get resultLayoutHintFull;

  /// Hint that explains the layout with the band of the measured values.
  ///
  /// In en, this message translates to:
  /// **'Adds a band with the sound, light and movement.'**
  String get resultLayoutHintSoundStrip;

  /// Hint that explains the layout with the frame.
  ///
  /// In en, this message translates to:
  /// **'A framed print with the style and readings.'**
  String get resultLayoutHintPoster;

  /// Accessibility label of the glitch loader shown while the picture is processed.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processingLabel;

  /// Label of the selector of the readings printed by the sound strip and the poster.
  ///
  /// In en, this message translates to:
  /// **'Readings'**
  String get resultReadingsLabel;

  /// Readings mode: numbers, ladders and spectrum.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get resultReadingsFull;

  /// Readings mode: only the numbers and their labels.
  ///
  /// In en, this message translates to:
  /// **'Numbers'**
  String get resultReadingsNumbers;

  /// Readings mode: no readings.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get resultReadingsHidden;

  /// Hint that explains the full readings mode.
  ///
  /// In en, this message translates to:
  /// **'Numbers, ladders and spectrum.'**
  String get resultReadingsHintFull;

  /// Hint that explains the numbers readings mode.
  ///
  /// In en, this message translates to:
  /// **'Only the numbers and their labels.'**
  String get resultReadingsHintNumbers;

  /// Hint that explains the hidden readings mode.
  ///
  /// In en, this message translates to:
  /// **'No readings. The photo ID stays.'**
  String get resultReadingsHintHidden;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
