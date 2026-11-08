import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ambient/ambient_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/fringe.dart';
import 'level_legend.dart';

/// The meters and the button that opens the settings.
class ViewfinderTopRow extends StatelessWidget {
  const ViewfinderTopRow({
    super.key,
    required this.ambient,
    required this.onHelp,
    required this.onSettings,
  });
  final AmbientController ambient;
  final VoidCallback onHelp;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LevelLegend(
        key: const ValueKey('vf-meters'),
        ambient: ambient,
        onExplain: onHelp,
      ),
      ViewfinderOverlayButton(
        key: const ValueKey('vf-settings'),
        icon: Icons.settings_outlined,
        label: AppLocalizations.of(context).viewfinderSettingsTooltip,
        onPressed: onSettings,
      ),
    ],
  );
}

/// The rail that names the style and steps through the styles.
class ViewfinderStyleBar extends StatelessWidget {
  const ViewfinderStyleBar({
    super.key,
    required this.name,
    required this.styleId,
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    required this.onChoose,
  });
  final String name;
  final String styleId;
  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(AppTheme.radiusSm);
    return Center(
      child: Container(
        height: AppTheme.styleBarHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.scrimStrong,
          borderRadius: radius,
          // A foreground border does not subtract space from the 48 dp targets.
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: AppTheme.overlayEdge,
            width: AppTheme.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              key: const ValueKey('vf-style-prev'),
              dimension: AppTheme.touchTarget,
              child: ViewfinderPressTarget(
                label: l10n.viewfinderPrevStyle,
                onPressed: onPrevious,
                builder: (_, pressed) => _railFace(
                  pressed: pressed,
                  child: const Icon(
                    Icons.chevron_left,
                    size: AppTheme.overlayIconSize,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppTheme.touchTarget,
                  maxWidth: AppTheme.stylePillMaxWidth,
                ),
                child: SizedBox(
                  key: const ValueKey('vf-style-bar'),
                  height: AppTheme.styleBarHeight,
                  child: ViewfinderPressTarget(
                    label: l10n.viewfinderStyleButton(name),
                    onPressed: onChoose,
                    builder: (_, pressed) => _railFace(
                      pressed: pressed,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            top: AppTheme.spaceSmMd,
                            bottom: AppTheme.spaceSmMd,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.symmetric(
                                  vertical: BorderSide(
                                    color: AppTheme.overlayEdge,
                                    width: AppTheme.borderWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spaceSmMd,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: FringeText(
                                    name.toUpperCase(),
                                    value: ValueKey(styleId),
                                    style: AppTheme.micro.copyWith(
                                      color: AppTheme.textPrimary,
                                      fontSize: AppTheme.styleNameFontSize,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: AppTheme.spaceXs + AppTheme.space2xs,
                                ),
                                Text(
                                  '${(index + 1).toString().padLeft(2, '0')}/${count.toString().padLeft(2, '0')}',
                                  style: AppTheme.readoutSmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: AppTheme.spaceXs),
                                const Icon(
                                  Icons.unfold_more,
                                  size: AppTheme.meterIconSize,
                                  color: AppTheme.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox.square(
              key: const ValueKey('vf-style-next'),
              dimension: AppTheme.touchTarget,
              child: ViewfinderPressTarget(
                label: l10n.viewfinderNextStyle,
                onPressed: onNext,
                builder: (_, pressed) => _railFace(
                  pressed: pressed,
                  child: const Icon(
                    Icons.chevron_right,
                    size: AppTheme.overlayIconSize,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railFace({required bool pressed, required Widget child}) =>
      ColoredBox(
        color: pressed ? AppTheme.pressedOverlay : Colors.transparent,
        child: Center(child: child),
      );
}

/// The line that says what the camera is doing.
class ViewfinderStatusSlot extends StatelessWidget {
  const ViewfinderStatusSlot({
    super.key,
    required this.capturing,
    required this.armed,
    this.error,
  });
  final bool capturing;
  final bool armed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label =
        error ??
        (capturing
            ? l10n.viewfinderCapturing
            : armed
            ? l10n.viewfinderMomentArmed
            : null);
    return SizedBox(
      key: const ValueKey('vf-status'),
      height: AppTheme.statusSlotHeight,
      width: double.infinity,
      child: label == null
          ? null
          : Center(
              child: Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('vf-status-tag'),
                  height: AppTheme.statusSlotHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.scrimStrong,
                    borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusLed(
                        blinking: capturing && error == null,
                        color: error != null
                            ? AppTheme.danger
                            : capturing
                            ? AppTheme.warm
                            : AppTheme.accent,
                      ),
                      const SizedBox(
                        width: AppTheme.spaceXs + AppTheme.space2xs,
                      ),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textPrimary,
                            fontSize: AppTheme.statusFontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The capture LED has one on/off cycle per second; errors stay steadily lit.
class _StatusLed extends StatefulWidget {
  const _StatusLed({required this.color, required this.blinking});
  final Color color;
  final bool blinking;

  @override
  State<_StatusLed> createState() => _StatusLedState();
}

class _StatusLedState extends State<_StatusLed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBlink();
  }

  @override
  void didUpdateWidget(_StatusLed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBlink();
  }

  void _syncBlink() {
    final duration = AppTheme.motionDuration(
      context,
      const Duration(seconds: 1),
    );
    if (widget.blinking && duration != Duration.zero) {
      _blink.duration = duration;
      if (!_blink.isAnimating) _blink.repeat();
    } else {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _blink,
    child: SizedBox.square(
      key: const ValueKey('vf-status-led'),
      dimension: AppTheme.spaceXs + AppTheme.space2xs,
      child: ColoredBox(color: widget.color),
    ),
    builder: (_, child) =>
        Opacity(opacity: _blink.value < 0.5 ? 1 : 0, child: child),
  );
}

/// The transient line that names the style that was chosen.
class ViewfinderStyleFeedback extends StatelessWidget {
  const ViewfinderStyleFeedback({
    super.key,
    required this.message,
    required this.styleId,
  });

  /// The line to show, null when nothing was chosen recently.
  final String? message;

  /// The style that the line belongs to.
  final String styleId;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedSwitcher(
      key: ValueKey(styleId),
      duration: AppTheme.motionDuration(
        context,
        AppTheme.feedbackTransitionDuration,
      ),
      child: message == null
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey(message),
              liveRegion: true,
              child: Container(
                key: const ValueKey('style-feedback'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceSmMd,
                  vertical: AppTheme.spaceSm,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.scrimStrong,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  message!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ),
    ),
  );
}

/// A button of the overlay, over the live picture.
class ViewfinderOverlayButton extends StatelessWidget {
  const ViewfinderOverlayButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: AppTheme.touchTarget,
    child: ViewfinderPressTarget(
      label: label,
      onPressed: onPressed,
      builder: (context, pressed) => Center(
        child: AnimatedContainer(
          duration: AppTheme.motionDuration(context, AppTheme.pressDuration),
          curve: AppTheme.motionCurve,
          width: AppTheme.touchTarget - AppTheme.spaceXs,
          height: AppTheme.touchTarget - AppTheme.spaceXs,
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.scrim,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: selected
                ? null
                : Border.all(
                    color: AppTheme.overlayEdge,
                    width: AppTheme.borderWidth,
                  ),
          ),
          foregroundDecoration: pressed
              ? BoxDecoration(
                  color: AppTheme.pressedOverlay,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                )
              : null,
          child: Icon(
            icon,
            size: AppTheme.overlayIconSize,
            color: onPressed == null
                ? AppTheme.textTertiary
                : selected
                ? AppTheme.onAccent
                : AppTheme.textPrimary,
          ),
        ),
      ),
    ),
  );
}

/// Shared accessible hit area. Its visual child can be smaller than the target.
class ViewfinderPressTarget extends StatefulWidget {
  const ViewfinderPressTarget({
    super.key,
    required this.label,
    required this.onPressed,
    required this.builder,
    this.enabled,
    this.circularFocus = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool pressed) builder;
  final bool? enabled;
  final bool circularFocus;

  @override
  State<ViewfinderPressTarget> createState() => _PressTargetState();
}

class _PressTargetState extends State<ViewfinderPressTarget> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.onPressed != null,
    includeFocusSemantics: false,
    onShowFocusHighlight: (value) {
      if (_focused != value) setState(() => _focused = value);
    },
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        },
      ),
    },
    child: Semantics(
      button: true,
      enabled: widget.enabled ?? (widget.onPressed == null ? false : null),
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onPressed,
          onTapDown: widget.onPressed == null ? null : (_) => _setPressed(true),
          onTapUp: widget.onPressed == null ? null : (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              shape: widget.circularFocus
                  ? BoxShape.circle
                  : BoxShape.rectangle,
              borderRadius: widget.circularFocus
                  ? null
                  : BorderRadius.circular(AppTheme.radiusSm),
              color: _focused ? AppTheme.focusOverlay : null,
              border: _focused
                  ? Border.all(
                      color: AppTheme.accent,
                      width: AppTheme.borderWidth,
                    )
                  : null,
            ),
            child: widget.builder(context, _pressed),
          ),
        ),
      ),
    ),
  );
}
