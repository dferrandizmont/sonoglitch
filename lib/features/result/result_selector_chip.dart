import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A square option tile with explicit selected and disabled states.
class ResultSelectorChip extends StatelessWidget {
  const ResultSelectorChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.pressDuration,
        color: selected
            ? AppTheme.accentTint
            : AppTheme.surface.withValues(alpha: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          side: BorderSide(
            color: selected ? AppTheme.accent : AppTheme.edge,
            width: AppTheme.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppTheme.touchTarget,
              minHeight: AppTheme.touchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spaceMd - AppTheme.space2xs,
                vertical: AppTheme.spaceXs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
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
    ),
  );
}
