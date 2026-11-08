import 'package:flutter/material.dart';

import '../../ambient/ambient_state.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';

/// The values that were measured when the picture was taken.
class ResultMeasurements extends StatelessWidget {
  const ResultMeasurements({super.key, required this.ambient});

  final AmbientState ambient;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rawDb = ambient.rawDb;
    final light = _levelWord(l10n, ambient.light);
    final motion = _levelWord(l10n, ambient.motion, masculine: true);
    final readings = <Widget>[
      _Reading(
        label: l10n.levelNoise,
        value: rawDb == null
            ? _levelWord(l10n, ambient.noise, masculine: true)
            : '\u2248${rawDb.round()} dB',
        semanticsLabel: rawDb == null
            ? null
            : l10n.resultNoiseLabel(rawDb.round()),
        color: AppTheme.accent,
      ),
      _Reading(
        label: l10n.levelLight,
        value: light,
        semanticsLabel: l10n.resultLightLabel(light),
        color: AppTheme.warm,
      ),
      _Reading(
        label: l10n.levelMotion,
        value: motion,
        semanticsLabel: l10n.resultMotionLabel(motion),
        color: AppTheme.signalCyan,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth / scale < 200;
        if (stacked) {
          return Column(
            key: const ValueKey('res-readings'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < readings.length; i++) ...[
                if (i > 0) const SizedBox(height: AppTheme.spaceSm),
                readings[i],
              ],
            ],
          );
        }
        return Row(
          key: const ValueKey('res-readings'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final reading in readings) Expanded(child: reading)],
        );
      },
    );
  }

  // Light is feminine in Spanish; noise and motion are masculine.
  String _levelWord(
    AppLocalizations l10n,
    double value, {
    bool masculine = false,
  }) {
    if (value < 0.33) {
      return masculine ? l10n.resultLevelLowMasculine : l10n.resultLevelLow;
    }
    if (value < 0.66) {
      return masculine
          ? l10n.resultLevelMediumMasculine
          : l10n.resultLevelMedium;
    }
    return masculine ? l10n.resultLevelHighMasculine : l10n.resultLevelHigh;
  }
}

/// One instrument readout; the spoken noise value retains its calibration caveat.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.value,
    required this.color,
    this.semanticsLabel,
  });
  final String label;
  final String value;
  final Color color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticsLabel,
    excludeSemantics: semanticsLabel != null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: MicroLabel(label),
        ),
        const SizedBox(height: AppTheme.spaceXs),
        Row(
          children: [
            SizedBox.square(
              dimension: AppTheme.spaceXs,
              child: ColoredBox(color: color),
            ),
            const SizedBox(width: AppTheme.spaceXs),
            Flexible(
              child: Text(
                value.isEmpty
                    ? value
                    : '${value[0].toUpperCase()}${value.substring(1)}',
                style: AppTheme.readout,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
