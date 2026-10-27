import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'style_controller.dart';
import 'style_copy.dart';
import 'style_sheet.dart';

/// The list of the available styles.
///
/// Every style is free for now: the paid packs come later.
class StylesScreen extends StatelessWidget {
  const StylesScreen({super.key, required this.styles});

  /// The styles and the one that is selected.
  final StyleController styles;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stylesTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceMd),
            child: Center(
              child: Text(
                styles.styles.length.toString().padLeft(2, '0'),
                style: AppTheme.readoutSmall,
              ),
            ),
          ),
        ],
      ),
      // The list listens to the controller, so the check, the badge and the
      // selected semantics move to the style that was chosen.
      body: ListenableBuilder(
        listenable: styles,
        builder: (context, _) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm),
          itemCount: styles.styles.length,
          itemBuilder: (context, index) {
            final style = styles.styles[index];
            return StyleTile(
              style: style,
              index: index,
              description: styleDescription(l10n, style.id),
              isSelected: style.id == styles.style.id,
              selectedBadgeLabel: l10n.stylesSelected,
              onTap: () => styles.select(style),
            );
          },
        ),
      ),
    );
  }
}
