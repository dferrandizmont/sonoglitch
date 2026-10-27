import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ambient/ambient_state.dart';
import '../../ambient/signal_intensity.dart';
import '../../app_config.dart';
import '../../camera/camera_metrics.dart';
import '../../debug/capture_metrics.dart';
import '../../debug/debug_log.dart';
import '../../debug/device_summary.dart';
import '../../debug/diagnostic_exporter.dart';
import '../../debug/diagnostic_report.dart';
import '../../l10n/app_localizations.dart';
import '../../export/export_file_type.dart';
import '../../export/export_quality.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';
import 'app_settings.dart';

Future<bool> _openExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// The settings of the app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.log,
    required this.exporter,
    required this.ambient,
    required this.metrics,
    required this.capture,
    required this.styleId,
    required this.device,
    this.donationUrl = AppConfig.donationUrl,
    this.openLink = _openExternally,
  });

  /// The switches.
  final AppSettings settings;

  /// The link of the "Support the project" row; empty hides the row.
  final String donationUrl;

  /// Opens a link outside the app.
  final Future<bool> Function(Uri uri) openLink;

  /// The logger.
  final DebugLog log;

  /// Used to share the diagnostic report.
  final DiagnosticExporter exporter;

  /// The current ambient state, for the report.
  final ValueListenable<AmbientState> ambient;

  /// The current camera measurements, for the report.
  final ValueListenable<CameraMetricsData> metrics;

  /// The timings of the last capture, for the report.
  final CaptureMetrics capture;

  /// The style that is being drawn, for the report.
  final String styleId;

  /// What is known about the device, for the report.
  final DeviceSummary device;

  Future<void> _exportReport(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final report = DiagnosticReport.build(
      ambient: ambient.value,
      metrics: metrics.value,
      styleId: styleId,
      timings: capture.value,
      device: device,
      appVersion: AppConfig.appVersion,
      buildMode: kReleaseMode ? 'release' : 'debug',
      logs: log.recentLines,
    );
    try {
      await exporter.share(report);
    } catch (error, stackTrace) {
      log.error(
        'settings',
        'the report could not be shared',
        error,
        stackTrace,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.debugShareFailed)));
    }
  }

  Future<void> _openDonation() async {
    final url = donationUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      log.warning('settings', 'the donation link is not an https link');
      return;
    }
    if (!await openLink(uri)) {
      log.warning('settings', 'the donation link could not be opened');
    }
  }

  /// Brings the tip of the viewfinder back.
  Future<void> _resetTips(BuildContext context) async {
    await settings.resetTips();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).settingsTipsReset)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      // The body is a list and not a column inside a scroll view: the rows
      // that are below the fold are only built when they are needed, so the
      // screen scrolls without building everything at once.
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm),
        children: [
          _SectionTitle(l10n.settingsCameraSectionTitle),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListTile(
              title: Text(l10n.settingsQualityTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DropdownField<ExportQuality>(
                    value: settings.exportQuality,
                    items: [
                      DropdownMenuItem(
                        value: ExportQuality.standard,
                        child: Text(
                          l10n.qualityStandard,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ExportQuality.high,
                        child: Text(
                          l10n.qualityHigh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ExportQuality.maximum,
                        child: Text(
                          l10n.qualityMaximum,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.setExportQuality(value);
                    },
                  ),
                  Text(l10n.settingsQualitySubtitle),
                ],
              ),
            ),
          ),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListTile(
              title: Text(l10n.settingsIntensityTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DropdownField<SignalIntensity>(
                    value: settings.intensity,
                    items: [
                      DropdownMenuItem(
                        value: SignalIntensity.subtle,
                        child: Text(
                          l10n.intensitySubtle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: SignalIntensity.normal,
                        child: Text(
                          l10n.intensityNormal,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: SignalIntensity.extreme,
                        child: Text(
                          l10n.intensityExtreme,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.setIntensity(value);
                    },
                  ),
                  Text(l10n.settingsIntensitySubtitle),
                ],
              ),
            ),
          ),
          // Every switch listens to the settings, so the value that is on
          // the screen is the value that is stored: a tap that changes the
          // setting rebuilds the switch and a second tap reverses it.
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => SwitchListTile(
              value: settings.contextLineEnabled,
              onChanged: settings.setContextLineEnabled,
              title: Text(l10n.settingsContextLineTitle),
              subtitle: Text(l10n.settingsContextLineSubtitle),
            ),
          ),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => SwitchListTile(
              value: settings.watermarkEnabled,
              onChanged: settings.setWatermarkEnabled,
              title: Text(l10n.settingsWatermarkTitle),
              subtitle: Text(l10n.settingsWatermarkSubtitle),
            ),
          ),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => SwitchListTile(
              value: settings.momentKeepArmed,
              onChanged: settings.setMomentKeepArmed,
              title: Text(l10n.settingsMomentKeepArmedTitle),
              subtitle: Text(l10n.settingsMomentKeepArmedSubtitle),
            ),
          ),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListTile(
              title: Text(l10n.settingsFileTypeTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DropdownField<ExportFileType>(
                    value: settings.fileType,
                    items: [
                      DropdownMenuItem(
                        value: ExportFileType.png,
                        child: Text(
                          l10n.fileTypePng,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ExportFileType.jpeg,
                        child: Text(
                          l10n.fileTypeJpeg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.setFileType(value);
                    },
                  ),
                  Text(l10n.settingsFileTypeSubtitle),
                ],
              ),
            ),
          ),
          ListTile(
            onTap: () => _resetTips(context),
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(l10n.settingsTipsTitle),
            subtitle: Text(l10n.settingsTipsSubtitle),
          ),
          const Divider(),
          _SectionTitle(l10n.settingsTroubleshootingTitle),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => SwitchListTile(
              value: settings.diagnosticsEnabled,
              onChanged: settings.setDiagnosticsEnabled,
              title: Text(l10n.settingsDiagnosticsTitle),
              subtitle: Text(l10n.settingsDiagnosticsSubtitle),
            ),
          ),
          ListTile(
            onTap: () => _exportReport(context),
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.settingsExportReportTitle),
            subtitle: Text(l10n.settingsExportReportSubtitle),
          ),
          const Divider(),
          _SectionTitle(l10n.settingsAboutTitle),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceMd,
              vertical: AppTheme.spaceXs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsVersion(AppConfig.appVersion),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  l10n.settingsLicense(AppConfig.license),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceMd,
              vertical: AppTheme.spaceSm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsPrivacyTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  l10n.settingsPrivacyBody,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (donationUrl.isNotEmpty)
            ListTile(
              onTap: _openDonation,
              leading: const Icon(Icons.favorite_outline),
              title: Text(l10n.settingsSupportTitle),
            ),
          const SizedBox(height: AppTheme.spaceLg),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spaceMd,
        AppTheme.spaceLg,
        AppTheme.spaceMd,
        AppTheme.spaceSm,
      ),
      child: MicroLabel(title),
    );
  }
}

/// Keeps the existing typed dropdown API inside a square, full-height field.
class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: AppTheme.touchTarget,
    margin: const EdgeInsets.symmetric(vertical: AppTheme.spaceXs),
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceSmMd),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      border: Border.all(color: AppTheme.edge, width: AppTheme.borderWidth),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        itemHeight: AppTheme.touchTarget,
        dropdownColor: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        style: AppTheme.bodySmall.copyWith(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        icon: const Icon(
          Icons.expand_more,
          size: AppTheme.overlayIconSize,
          color: AppTheme.textSecondary,
        ),
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}
