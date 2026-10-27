import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ambient/ambient_state.dart';
import '../../effects/style_definition.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/micro_label.dart';
import 'smart_pick.dart';
import 'style_controller.dart';
import 'style_copy.dart';

/// The sheet that shows every style and lets the user choose one.
///
/// The sheet does not know how a style is selected: the caller tells it
/// with [onSelect], [onRandom] and [onMatch], so it can be used and tested
/// without a camera. The sheet closes itself after every one of those
/// actions, so the caller only has to show what happened.
class StyleSheet extends StatelessWidget {
  const StyleSheet({
    super.key,
    required this.styles,
    required this.selectedStyleId,
    required this.onSelect,
    required this.onRandom,
    required this.onMatch,
  });

  /// Every style that can be chosen.
  final List<StyleDefinition> styles;

  /// The id of the style that is selected.
  final String selectedStyleId;

  /// Called with the id of the style the user chose.
  final void Function(String styleId) onSelect;

  /// Called when the user asks for a random style.
  final VoidCallback onRandom;

  /// Called when the user asks for the style that fits the place.
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppTheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      // Foreground chrome stays above the ink without covering row feedback.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.outline)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMd),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.stylesTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.sheetTitle,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    Text(
                      styles.length.toString().padLeft(2, '0'),
                      style: AppTheme.readoutSmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _Action(
                        icon: Icons.casino_outlined,
                        label: l10n.styleSheetRandom,
                        onPressed: () => _close(context, onRandom),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(
                      child: _Action(
                        icon: Icons.auto_awesome_outlined,
                        label: l10n.styleSheetMatch,
                        onPressed: () => _close(context, onMatch),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceSmMd),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
                  itemCount: styles.length,
                  itemBuilder: (context, index) {
                    final style = styles[index];
                    return StyleTile(
                      style: style,
                      index: index,
                      description: styleDescription(l10n, style.id),
                      isSelected: style.id == selectedStyleId,
                      onTap: () {
                        onSelect(style.id);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Runs an action and closes the sheet.
  void _close(BuildContext context, VoidCallback action) {
    action();
    Navigator.of(context).pop();
  }
}

/// Shows the sheet of the styles.
///
/// The sheet may use the [AppTheme.styleSheetMaxHeightFactor] of the
/// screen, so it never covers the whole picture of the camera.
Future<void> showStyleSheet(
  BuildContext context, {
  required List<StyleDefinition> styles,
  required String selectedStyleId,
  required void Function(String styleId) onSelect,
  required VoidCallback onRandom,
  required VoidCallback onMatch,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle(
      duration: AppTheme.motionDuration(context, AppTheme.sheetDuration),
      reverseDuration: AppTheme.motionDuration(context, AppTheme.sheetDuration),
    ),
    backgroundColor: AppTheme.surface,
    constraints: BoxConstraints(
      maxHeight:
          MediaQuery.sizeOf(context).height *
          AppTheme.styleSheetMaxHeightFactor,
    ),
    builder: (context) => StyleSheet(
      styles: styles,
      selectedStyleId: selectedStyleId,
      onSelect: onSelect,
      onRandom: onRandom,
      onMatch: onMatch,
    ),
  );
}

/// One of the two actions of the sheet of the styles.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  /// The icon that names the action.
  final IconData icon;

  /// The name of the action.
  final String label;

  /// Called when the action is pressed.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTheme.touchTarget,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: const BorderSide(color: AppTheme.edge),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          minimumSize: const Size.square(AppTheme.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm),
          animationDuration: AppTheme.motionDuration(
            context,
            AppTheme.pressDuration,
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AppTheme.buttonIconSize),
            const SizedBox(width: AppTheme.spaceSm),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered style row, shared by the picker and the styles screen.
class StyleTile extends StatelessWidget {
  const StyleTile({
    super.key,
    required this.style,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.selectedBadgeLabel,
    this.index,
  });

  final StyleDefinition style;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final String? selectedBadgeLabel;

  /// Zero-based position in the caller's selectable list.
  final int? index;

  @override
  Widget build(BuildContext context) {
    final position = index ?? kStyles.indexWhere((item) => item.id == style.id);
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      label: style.name,
      child: InkWell(
        onTap: onTap,
        highlightColor: AppTheme.pressedOverlay,
        splashColor: AppTheme.pressedOverlay,
        focusColor: AppTheme.focusOverlay,
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentTint : AppTheme.surface,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppTheme.accent : AppTheme.surface,
                width: AppTheme.space2xs,
              ),
              bottom: const BorderSide(color: AppTheme.outline),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppTheme.touchTarget + AppTheme.spaceSmMd,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spaceMd,
                vertical: AppTheme.spaceSm,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: AppTheme.spaceLg + AppTheme.spaceXs,
                    child: ExcludeSemantics(
                      child: Text(
                        (position + 1).toString().padLeft(2, '0'),
                        style: AppTheme.readoutSmall,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          style.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.readout.copyWith(
                            fontFeatures: const [],
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppTheme.space2xs),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodySmall,
                        ),
                        if (isSelected && selectedBadgeLabel != null) ...[
                          const SizedBox(height: AppTheme.spaceXs),
                          _SelectedBadge(label: selectedBadgeLabel!),
                        ],
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: AppTheme.spaceSm),
                    const Icon(
                      Icons.check,
                      size: AppTheme.overlayIconSize,
                      color: AppTheme.accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppTheme.spaceXs,
      vertical: AppTheme.space2xs,
    ),
    decoration: BoxDecoration(
      color: AppTheme.accentTint,
      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
    ),
    child: MicroLabel(
      label,
      color: AppTheme.accent,
      fontSize: AppTheme.spaceSm + AppTheme.space2xs,
    ),
  );
}

/// The actions of the sheet of the styles.
///
/// They keep the logic of the random pick and of the Smart pick out of the
/// widgets, so the camera and the sheet share them and the tests can drive
/// them without a camera.
class StyleSheetActions {
  StyleSheetActions({required this.styles, required this.ambient});

  /// The registry of the styles and the one that is selected.
  final StyleController styles;

  /// The readings of the place.
  final ValueListenable<AmbientState> ambient;

  /// Picks a style at random and returns the one that was chosen.
  Future<StyleDefinition> random() async {
    await styles.selectRandom();
    return styles.style;
  }

  /// Picks the style that fits the place and returns it.
  Future<StyleDefinition> match() async {
    final style = pickStyle(ambient.value, styles.styles);
    await styles.select(style);
    return style;
  }
}
