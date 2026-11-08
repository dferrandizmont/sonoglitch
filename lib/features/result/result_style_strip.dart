import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../effects/style_definition.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';

/// A horizontal strip with the photo in every style.
///
/// The style of the capture comes first. A tile shows the small preview that
/// the screen has drawn so far, or an empty tile while it is not ready; it
/// can be tapped either way.
class ResultStyleStrip extends StatelessWidget {
  const ResultStyleStrip({
    super.key,
    required this.styles,
    required this.selectedId,
    required this.enabled,
    required this.imageFor,
    required this.onSelect,
  });

  final List<StyleDefinition> styles;
  final String selectedId;
  final bool enabled;

  /// The preview of a style, null while it is not drawn.
  final ui.Image? Function(String styleId) imageFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.resultStyleLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
            child: ExcludeSemantics(child: MicroLabel(l10n.resultStyleLabel)),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          SingleChildScrollView(
            key: const ValueKey('res-style-strip'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < styles.length; index++) ...[
                  if (index > 0)
                    const SizedBox(width: AppTheme.spaceSm - AppTheme.space2xs),
                  ResultStyleTile(
                    key: ValueKey('res-style-${styles[index].id}'),
                    name: styles[index].name,
                    semanticLabel: l10n.resultStyleSemantics(
                      styles[index].name,
                    ),
                    selected: styles[index].id == selectedId,
                    image: imageFor(styles[index].id),
                    onTap: enabled ? () => onSelect(styles[index].id) : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ),
    );
  }
}

/// One style of the strip: the preview of the photo and the name below it.
///
/// It borrows the shape of the selector chips: the same radius, border and
/// selected tint.
class ResultStyleTile extends StatelessWidget {
  const ResultStyleTile({
    super.key,
    required this.name,
    required this.semanticLabel,
    required this.selected,
    required this.image,
    required this.onTap,
  });

  /// The side of the preview, and the width of the tile.
  static const double side = AppTheme.touchTarget + AppTheme.spaceLg;

  final String name;
  final String semanticLabel;
  final bool selected;
  final ui.Image? image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusSm);
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: SizedBox(
          width: side,
          child: Material(
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppTheme.pressDuration,
            color: selected
                ? AppTheme.accentTint
                : AppTheme.surface.withValues(alpha: 0),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: selected ? AppTheme.accent : AppTheme.edge,
                width: AppTheme.borderWidth,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: side,
                    height: side,
                    child: image == null
                        ? const ColoredBox(color: AppTheme.surface)
                        : RawImage(
                            key: ValueKey('res-style-image-$name'),
                            image: image,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceXs,
                      vertical: AppTheme.spaceXs,
                    ),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall.copyWith(
                        color: selected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
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
