import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/fringe.dart';
import 'viewfinder_controls.dart';

/// The row of the shutter, the auto shot and the flip.
class ViewfinderShutterRow extends StatelessWidget {
  // The shared theme has no tokens for these required shutter-only values.
  // Keep them local until the theme owner supplies the shared tokens.
  static const _pressedScale = 0.92;
  static const _haloOpacity = 0.35;

  const ViewfinderShutterRow({
    super.key,
    required this.armed,
    required this.busy,
    required this.pulse,
    required this.onAutoShot,
    required this.onShutter,
    required this.onFlip,
    required this.shutterLabel,
  });
  final bool armed;
  final bool busy;
  final Animation<double> pulse;
  final VoidCallback onAutoShot;
  final VoidCallback onShutter;
  final VoidCallback onFlip;
  final String shutterLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: AppTheme.shutterSize,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            toggled: armed,
            child: ViewfinderOverlayButton(
              key: const ValueKey('vf-auto-shot'),
              icon: Icons.graphic_eq,
              label: l10n.viewfinderMomentTooltip,
              onPressed: onAutoShot,
              selected: armed,
            ),
          ),
          const SizedBox(
            width:
                AppTheme.shutterSideOffset -
                AppTheme.touchTarget / 2 -
                AppTheme.shutterSize / 2,
          ),
          SizedBox.square(
            key: const ValueKey('vf-shutter'),
            dimension: AppTheme.shutterSize,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (armed)
                  Positioned.fill(
                    left:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    right:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    top:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    bottom:
                        -(AppTheme.pulseRingDiameter - AppTheme.shutterSize) /
                        2,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: pulse,
                        builder: (context, _) {
                          final reduced = MediaQuery.disableAnimationsOf(
                            context,
                          );
                          final t = reduced ? 1.0 : pulse.value;
                          return Transform.scale(
                            scale: reduced
                                ? 1
                                : AppTheme.shutterSize /
                                          AppTheme.pulseRingDiameter +
                                      (1 -
                                              AppTheme.shutterSize /
                                                  AppTheme.pulseRingDiameter) *
                                          t,
                            child: Container(
                              key: const ValueKey('moment-ring'),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.accent.withValues(
                                    alpha: reduced ? 1 : 1 - t / 2,
                                  ),
                                  width: AppTheme.ringStrokeWidth,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ViewfinderPressTarget(
                  label: shutterLabel,
                  circularFocus: true,
                  enabled: !busy,
                  onPressed: busy ? null : onShutter,
                  builder: (context, pressed) => Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.background.withValues(
                                alpha: _haloOpacity,
                              ),
                              width: AppTheme.borderWidth,
                            ),
                          ),
                          child: CustomPaint(
                            key: const ValueKey('vf-shutter-ring'),
                            painter: FringeRingPainter(
                              color: busy || armed
                                  ? AppTheme.accent
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        // The shared painter insets the ring by its fringe offset.
                        padding: const EdgeInsets.all(
                          AppTheme.fringeRingOffset +
                              AppTheme.shutterStrokeWidth +
                              AppTheme.shutterInset,
                        ),
                        child: AnimatedScale(
                          key: const ValueKey('vf-shutter-disc'),
                          scale: pressed && !busy ? _pressedScale : 1,
                          duration: AppTheme.motionDuration(
                            context,
                            AppTheme.pressDuration,
                          ),
                          curve: AppTheme.motionCurve,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: busy
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width:
                AppTheme.shutterSideOffset -
                AppTheme.touchTarget / 2 -
                AppTheme.shutterSize / 2,
          ),
          ViewfinderOverlayButton(
            key: const ValueKey('vf-flip'),
            icon: Icons.cameraswitch_outlined,
            label: l10n.viewfinderFlipTooltip,
            onPressed: onFlip,
          ),
        ],
      ),
    );
  }
}
