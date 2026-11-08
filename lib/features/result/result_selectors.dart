import 'package:flutter/material.dart';

import '../../export/export_format.dart';
import '../../export/export_layout.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';
import 'result_selector_chip.dart';

/// The format, layout and readings selectors of the result screen.
class ResultSelectors extends StatelessWidget {
  const ResultSelectors({
    super.key,
    required this.format,
    required this.layout,
    required this.readingsMode,
    required this.enabled,
    required this.onSelectFormat,
    required this.onSelectLayout,
    required this.onSelectReadingsMode,
  });

  final ExportFormat format;
  final ExportLayout layout;
  final ExportReadingsMode readingsMode;
  final bool enabled;
  final ValueChanged<ExportFormat> onSelectFormat;
  final ValueChanged<ExportLayout> onSelectLayout;
  final ValueChanged<ExportReadingsMode> onSelectReadingsMode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MicroLabel(l10n.resultFormatLabel),
          const SizedBox(height: AppTheme.spaceXs),
          Wrap(
            spacing: AppTheme.spaceSm - AppTheme.space2xs,
            runSpacing: AppTheme.spaceSm - AppTheme.space2xs,
            children: [
              for (final value in ExportFormat.values)
                ResultSelectorChip(
                  key: ValueKey('res-format-${value.name}'),
                  label: _formatLabel(l10n, value),
                  selected: value == format,
                  onTap: enabled ? () => onSelectFormat(value) : null,
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceMd),
          MicroLabel(l10n.resultLayoutLabel),
          const SizedBox(height: AppTheme.spaceXs),
          // The hint explains what the chosen layout does. It may take two
          // lines on a small screen, so it never pushes the chips out of the
          // way.
          Text(
            _layoutHint(l10n, layout),
            key: const ValueKey('res-layout-hint'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Wrap(
            spacing: AppTheme.spaceSm - AppTheme.space2xs,
            runSpacing: AppTheme.spaceSm - AppTheme.space2xs,
            children: [
              for (final value in ExportLayout.values)
                ResultSelectorChip(
                  key: ValueKey('res-layout-${value.name}'),
                  label: _layoutLabel(l10n, value),
                  selected: value == layout,
                  onTap: enabled ? () => onSelectLayout(value) : null,
                ),
            ],
          ),
          // The readings only exist in the strip and the poster.
          AnimatedSize(
            duration: AppTheme.motionDuration(context, AppTheme.sheetDuration),
            curve: AppTheme.motionCurve,
            alignment: Alignment.topLeft,
            child: layout == ExportLayout.full
                ? const SizedBox(width: double.infinity, height: 0)
                : _readingsSelector(l10n, theme),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ),
    );
  }

  /// The selector of the readings, under the chips of the layout.
  Widget _readingsSelector(AppLocalizations l10n, ThemeData theme) => Column(
    key: const ValueKey('res-readings'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: AppTheme.spaceMd),
      MicroLabel(l10n.resultReadingsLabel),
      const SizedBox(height: AppTheme.spaceXs),
      Text(
        _readingsHint(l10n, readingsMode),
        key: const ValueKey('res-readings-hint'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppTheme.textSecondary,
        ),
      ),
      const SizedBox(height: AppTheme.spaceXs),
      Wrap(
        spacing: AppTheme.spaceSm - AppTheme.space2xs,
        runSpacing: AppTheme.spaceSm - AppTheme.space2xs,
        children: [
          for (final mode in ExportReadingsMode.values)
            ResultSelectorChip(
              key: ValueKey('res-readings-${mode.name}'),
              label: _readingsLabel(l10n, mode),
              selected: mode == readingsMode,
              onTap: enabled ? () => onSelectReadingsMode(mode) : null,
            ),
        ],
      ),
    ],
  );

  String _readingsLabel(AppLocalizations l10n, ExportReadingsMode mode) =>
      switch (mode) {
        ExportReadingsMode.full => l10n.resultReadingsFull,
        ExportReadingsMode.numbers => l10n.resultReadingsNumbers,
        ExportReadingsMode.hidden => l10n.resultReadingsHidden,
      };

  /// The line that explains what the chosen readings mode does.
  String _readingsHint(AppLocalizations l10n, ExportReadingsMode mode) =>
      switch (mode) {
        ExportReadingsMode.full => l10n.resultReadingsHintFull,
        ExportReadingsMode.numbers => l10n.resultReadingsHintNumbers,
        ExportReadingsMode.hidden => l10n.resultReadingsHintHidden,
      };

  String _formatLabel(AppLocalizations l10n, ExportFormat format) {
    switch (format) {
      case ExportFormat.original:
        return l10n.resultFormatOriginal;
      case ExportFormat.square:
        return l10n.resultFormatSquare;
      case ExportFormat.portrait:
        return l10n.resultFormatPortrait;
      case ExportFormat.story:
        return l10n.resultFormatStory;
    }
  }

  String _layoutLabel(AppLocalizations l10n, ExportLayout layout) {
    switch (layout) {
      case ExportLayout.full:
        return l10n.resultLayoutFull;
      case ExportLayout.soundStrip:
        return l10n.resultLayoutSoundStrip;
      case ExportLayout.poster:
        return l10n.resultLayoutPoster;
    }
  }

  /// The line that explains what the chosen layout does.
  String _layoutHint(AppLocalizations l10n, ExportLayout layout) {
    switch (layout) {
      case ExportLayout.full:
        return l10n.resultLayoutHintFull;
      case ExportLayout.soundStrip:
        return l10n.resultLayoutHintSoundStrip;
      case ExportLayout.poster:
        return l10n.resultLayoutHintPoster;
    }
  }
}
