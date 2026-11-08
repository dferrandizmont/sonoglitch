import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// The bar of Retake, Share and Save at the bottom of the result screen.
class ResultToolbar extends StatelessWidget {
  const ResultToolbar({
    super.key,
    required this.busy,
    required this.ready,
    required this.onRetake,
    required this.onShare,
    required this.onSave,
  });

  /// Whether the platform is saving or sharing.
  final bool busy;

  /// Whether the picture of the selections can be exported.
  final bool ready;

  final VoidCallback onRetake;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.outline, width: AppTheme.borderWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final stacked = constraints.maxWidth / scale < 220;
              final verticalIcons = !stacked && constraints.maxWidth < 340;
              final actions = [
                TextButton(
                  onPressed: busy ? null : onRetake,
                  style: _actionStyle(context).copyWith(
                    foregroundColor: const WidgetStatePropertyAll(
                      AppTheme.textSecondary,
                    ),
                  ),
                  child: _actionContent(
                    Icons.replay,
                    l10n.resultRetake,
                    verticalIcons,
                  ),
                ),
                OutlinedButton(
                  onPressed: ready ? onShare : null,
                  style: _actionStyle(context),
                  child: _actionContent(
                    Icons.share_outlined,
                    l10n.resultShare,
                    verticalIcons,
                  ),
                ),
                FilledButton(
                  onPressed: ready ? onSave : null,
                  style: _actionStyle(context),
                  child: _actionContent(
                    Icons.download_outlined,
                    l10n.resultSave,
                    verticalIcons,
                  ),
                ),
              ];
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppTheme.spaceXs),
                      actions[i],
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppTheme.spaceSm),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _actionContent(IconData icon, String label, bool vertical) {
    final text = Text(label, textAlign: TextAlign.center);
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(height: AppTheme.spaceXs),
          text,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon),
        const SizedBox(width: AppTheme.spaceSm),
        Flexible(child: text),
      ],
    );
  }

  ButtonStyle _actionStyle(BuildContext context) => ButtonStyle(
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: AppTheme.spaceXs,
        vertical: AppTheme.spaceXs,
      ),
    ),
    minimumSize: const WidgetStatePropertyAll(
      Size.square(AppTheme.touchTarget),
    ),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppTheme.pressDuration,
  );
}
