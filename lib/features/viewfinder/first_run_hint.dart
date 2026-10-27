import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';

/// A first-run explanation with explicit help and dismissal targets.
class FirstRunHint extends StatelessWidget {
  const FirstRunHint({
    super.key,
    required this.onDismiss,
    required this.onHelp,
  });

  final VoidCallback onDismiss;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: AppTheme.tipCardMaxWidth),
      padding: const EdgeInsets.all(AppTheme.spaceSmMd),
      decoration: BoxDecoration(
        color: AppTheme.scrimStrong,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.overlayEdge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.viewfinderHint,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textPrimary),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: TextButton(
                  style: TextButton.styleFrom(
                    animationDuration: AppTheme.motionDuration(
                      context,
                      AppTheme.pressDuration,
                    ),
                    minimumSize: const Size(
                      AppTheme.touchTarget,
                      AppTheme.touchTarget,
                    ),
                  ),
                  onPressed: onHelp,
                  child: MicroLabel(
                    l10n.helpOpen,
                    color: AppTheme.accent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox.square(
                dimension: AppTheme.touchTarget,
                child: IconButton(
                  tooltip: l10n.viewfinderTipDismiss,
                  onPressed: onDismiss,
                  style: IconButton.styleFrom(
                    animationDuration: AppTheme.motionDuration(
                      context,
                      AppTheme.pressDuration,
                    ),
                  ),
                  icon: Icon(
                    Icons.close,
                    size: AppTheme.buttonIconSize,
                    semanticLabel: l10n.viewfinderTipDismiss,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
