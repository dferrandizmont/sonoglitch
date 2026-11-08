import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The picture of the result screen, with the button that shows the
/// original.
class ResultPicture extends StatelessWidget {
  const ResultPicture({
    super.key,
    required this.composed,
    required this.original,
    required this.showOriginal,
    required this.photo,
    required this.compareLabel,
    required this.onToggleOriginal,
    required this.onHoldingChanged,
  });

  /// The composed picture.
  final ui.Image? composed;

  /// The cropped original, when there is a source to compare with.
  final ui.Image? original;

  /// Whether the original photo is the one that is shown.
  final bool showOriginal;

  /// The bounds of the photo inside the composed picture.
  final Rect photo;

  /// What the button of the comparison says.
  final String compareLabel;

  final VoidCallback onToggleOriginal;
  final ValueChanged<bool> onHoldingChanged;

  @override
  Widget build(BuildContext context) {
    final image = showOriginal && original != null ? original : composed;
    if (image == null) return const SizedBox.shrink();
    // Fit the stack to the image so Compare follows the actual photo corner.
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = applyBoxFit(
          BoxFit.contain,
          Size(image.width.toDouble(), image.height.toDouble()),
          constraints.biggest,
        ).destination;
        final photoRect = showOriginal && original != null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : photo;
        return SizedBox.fromSize(
          size: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onLongPressStart: (_) => onHoldingChanged(true),
                  onLongPressEnd: (_) => onHoldingChanged(false),
                  onLongPressCancel: () => onHoldingChanged(false),
                  child: RawImage(image: image, fit: BoxFit.contain),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('res-photo-frame'),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppTheme.overlayEdge.withValues(alpha: 0.08),
                        width: AppTheme.borderWidth,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: AppTheme.spaceXs + (1 - photoRect.right) * size.width,
                top: AppTheme.spaceXs + photoRect.top * size.height,
                child: Semantics(
                  button: true,
                  enabled: original != null,
                  label: compareLabel,
                  onTap: original == null ? null : onToggleOriginal,
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey('res-compare'),
                    onPressed: original == null ? null : onToggleOriginal,
                    tooltip: compareLabel,
                    icon: Ink(
                      width: AppTheme.touchTarget - AppTheme.spaceSm,
                      height: AppTheme.touchTarget - AppTheme.spaceSm,
                      decoration: BoxDecoration(
                        color: AppTheme.scrim,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Icon(
                        showOriginal ? Icons.image_outlined : Icons.compare,
                        size: AppTheme.overlayIconSize,
                      ),
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: AppTheme.touchTarget,
                      height: AppTheme.touchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      disabledForegroundColor: AppTheme.textSecondary,
                      animationDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppTheme.pressDuration,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
