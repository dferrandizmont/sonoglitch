import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ambient/ambient_state.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';

const _rowGap = AppTheme.spaceXs + AppTheme.space2xs;
const _rowHeight = AppTheme.legendIconSize;
const _meterHeight = _rowHeight * 3 + _rowGap * 2;

/// Compact, tappable readout of the three ambient controls.
class LevelLegend extends StatelessWidget {
  const LevelLegend({
    super.key,
    required this.ambient,
    required this.onExplain,
  });

  final ValueListenable<AmbientState> ambient;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return ValueListenableBuilder<AmbientState>(
      valueListenable: ambient,
      builder: (context, state, _) => Semantics(
        container: true,
        button: true,
        label: l10n.viewfinderMetersTooltip,
        onTap: onExplain,
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: onExplain,
          child: Tooltip(
            message: l10n.viewfinderMetersTooltip,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AppTheme.touchTarget,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spaceSm + AppTheme.space2xs,
                vertical: AppTheme.spaceSm,
              ),
              decoration: BoxDecoration(
                color: AppTheme.scrim,
                borderRadius: radius,
              ),
              // Foreground chrome does not add layout padding: the card is 70 dp.
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AppTheme.overlayEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Positioned(
                        left: AppTheme.legendIconSize + _rowGap,
                        top: 0,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: const Size(
                              SegmentedMeterPainter.scaleWidth,
                              _meterHeight,
                            ),
                            painter: SegmentedMeterPainter(
                              noise: state.noise,
                              light: state.light,
                              motion: state.motion,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LevelEntry(
                            icon: Icons.mic_none,
                            label: l10n.levelNoise,
                            tooltip: l10n.viewfinderLegendNoiseTooltip,
                            value: state.noise,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(height: _rowGap),
                          _LevelEntry(
                            icon: Icons.wb_sunny_outlined,
                            label: l10n.levelLight,
                            tooltip: l10n.viewfinderLegendLightTooltip,
                            value: state.light,
                            color: AppTheme.warm,
                          ),
                          const SizedBox(height: _rowGap),
                          _LevelEntry(
                            icon: Icons.open_with,
                            label: l10n.levelMotion,
                            tooltip: l10n.viewfinderLegendMotionTooltip,
                            value: state.motion,
                            color: AppTheme.signalCyan,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  const Icon(
                    Icons.info_outline,
                    size: AppTheme.meterInfoIconSize,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelEntry extends StatelessWidget {
  const _LevelEntry({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      container: true,
      label: '$label ${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _rowHeight, color: color),
          const SizedBox(width: _rowGap),
          const SizedBox(
            width: SegmentedMeterPainter.scaleWidth,
            height: _rowHeight,
          ),
        ],
      ),
    ),
  );
}

/// Paints all three scales in one pass, only when a lit count changes.
class SegmentedMeterPainter extends CustomPainter {
  SegmentedMeterPainter({
    required double noise,
    required double light,
    required double motion,
  }) : noiseCount = litCount(noise),
       lightCount = litCount(light),
       motionCount = litCount(motion);

  static const segmentCount = 12;
  static const _segmentSize = AppTheme.spaceXs;
  static const _segmentGap = AppTheme.borderWidth;
  static const scaleWidth =
      segmentCount * _segmentSize + (segmentCount - 1) * _segmentGap;

  final int noiseCount;
  final int lightCount;
  final int motionCount;

  static int litCount(double value) =>
      (value.clamp(0.0, 1.0) * segmentCount).round();

  @override
  void paint(Canvas canvas, Size size) {
    final counts = [noiseCount, lightCount, motionCount];
    const colors = [AppTheme.accent, AppTheme.warm, AppTheme.signalCyan];
    const unlit = AppTheme.meterTrack;
    final paint = Paint();
    for (var row = 0; row < counts.length; row++) {
      for (var segment = 0; segment < segmentCount; segment++) {
        paint.color = segment < counts[row] ? colors[row] : unlit;
        canvas.drawRect(
          Rect.fromLTWH(
            segment * (_segmentSize + _segmentGap),
            row * (_rowHeight + _rowGap) + (_rowHeight - _segmentSize) / 2,
            _segmentSize,
            _segmentSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SegmentedMeterPainter oldDelegate) =>
      noiseCount != oldDelegate.noiseCount ||
      lightCount != oldDelegate.lightCount ||
      motionCount != oldDelegate.motionCount;
}

/// Explains the controls, style browsing and automatic capture.
class HowItWorksSheet extends StatelessWidget {
  const HowItWorksSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
        border: Border(top: BorderSide(color: AppTheme.outline)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.helpTitle, style: AppTheme.sheetTitle),
              const SizedBox(height: AppTheme.spaceMd),
              _Explanation(
                title: l10n.levelNoise,
                body: l10n.viewfinderLegendNoiseBody,
                color: AppTheme.accent,
              ),
              const _Hairline(),
              _Explanation(
                title: l10n.levelLight,
                body: l10n.viewfinderLegendLightBody,
                color: AppTheme.warm,
              ),
              const _Hairline(),
              _Explanation(
                title: l10n.levelMotion,
                body: l10n.viewfinderLegendMotionBody,
                color: AppTheme.signalCyan,
              ),
              const _Hairline(),
              Text(l10n.helpSwipe, style: _explanationBody),
              const _Hairline(),
              Text(l10n.helpAutoShot, style: _explanationBody),
              const SizedBox(height: AppTheme.spaceSm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.square(AppTheme.touchTarget),
                    animationDuration: AppTheme.motionDuration(
                      context,
                      AppTheme.pressDuration,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Use the shared compact prose token without introducing a local text scale.
const _explanationBody = AppTheme.bodySmall;

class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MicroLabel(title, color: color),
      const SizedBox(height: AppTheme.spaceXs),
      Text(body, style: _explanationBody),
    ],
  );
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppTheme.spaceSmMd),
    child: Divider(height: AppTheme.borderWidth),
  );
}
