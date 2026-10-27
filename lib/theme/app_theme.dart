import 'package:flutter/material.dart';

/// Design tokens for Sonoglitch.
///
/// Every colour, spacing and radius used by the UI lives here, so the screens
/// stay coherent and a tweak is a one line change. The app is dark only: a
/// camera viewfinder should not blind the user.
class AppTheme {
  const AppTheme._();

  // Colours -----------------------------------------------------------------

  /// Page background, almost black so the preview dominates.
  static const Color background = Color(0xFF0D0D11);

  /// Cards, sheets and other raised surfaces.
  static const Color surface = Color(0xFF16161C);

  /// Slightly lighter surface used for pressed or selected states.
  static const Color surfaceHigh = Color(0xFF1F1F27);

  /// Hairlines and disabled borders.
  static const Color outline = Color(0xFF2C2C36);

  /// Visible edges of interactive controls.
  static const Color edge = Color(0xFF3D3D4A);

  /// Control edges over the live image.
  static const Color overlayEdge = Color(0x1FFFFFFF);

  /// Unlit meter segments, white at 16% over the live scene scrim.
  static const Color meterTrack = Color(0x29FFFFFF);

  /// Primary accent (violet), used for the shutter ring and selected chips.
  static const Color accent = Color(0xFFB69CFF);

  static const Color onAccent = Color(0xFF17121F);
  static const Color accentTint = Color(0x24B69CFF);

  /// Dimmed accent reserved for switch tracks.
  static const Color accentMuted = Color(0xFF6E5AA8);

  /// Warm signal reserved for the light meter and capturing indicator.
  static const Color warm = Color(0xFFFFB37A);

  /// Motion meter and chromatic fringe signals.
  static const Color signalCyan = Color(0xFF55E5F2);
  static const Color signalMagenta = Color(0xFFF36CCB);

  /// Error / destructive accent.
  static const Color danger = Color(0xFFFF6B6B);

  /// Primary text colour.
  static const Color textPrimary = Color(0xFFF3F3F6);

  /// Secondary text colour.
  static const Color textSecondary = Color(0xFFA5A5B2);

  /// Quiet labels and disabled controls.
  static const Color textTertiary = Color(0xFF82828F);

  /// Translucent dark violet used behind the overlay controls.
  static const Color scrim = Color(0xB30C0A12);

  /// Stronger scrim used behind overlay labels.
  ///
  /// It is darker than [scrim] so the words of a label keep their contrast
  /// over a bright scene.
  static const Color scrimStrong = Color(0xD90C0A12);

  /// Focus and press overlays, kept separate from signal colours.
  static const Color focusOverlay = Color(0x3DB69CFF);
  static const Color pressedOverlay = Color(0x1AFFFFFF);

  // Spacing -----------------------------------------------------------------

  static const double space2xs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceSmMd = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  /// Margin kept between the overlay controls and the screen edges.
  static const double safeMargin = 8;

  // Radii -------------------------------------------------------------------

  static const double radiusNone = 0;
  static const double radiusXs = 2;
  static const double radiusSm = 4;
  static const double radiusMd = 6;
  static const double radiusLg = 8;

  // Typography --------------------------------------------------------------

  static const TextStyle headline = TextStyle(
    fontFamily: 'Roboto',
    color: textPrimary,
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );
  static const TextStyle title = TextStyle(
    fontFamily: 'Roboto',
    color: textPrimary,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle sheetTitle = TextStyle(
    fontFamily: 'Roboto',
    color: textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle body = TextStyle(
    fontFamily: 'Roboto',
    color: textPrimary,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'Roboto',
    color: textSecondary,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle label = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  static const TextStyle micro = TextStyle(
    fontFamily: 'Roboto',
    color: textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );
  static const TextStyle readout = TextStyle(
    fontFamily: 'Roboto',
    color: textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle readoutSmall = TextStyle(
    fontFamily: 'Roboto',
    color: textTertiary,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Motion ------------------------------------------------------------------

  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Duration sheetDuration = Duration(milliseconds: 220);
  static const Duration fringeDuration = Duration(milliseconds: 180);
  static const Curve motionCurve = Curves.easeOutCubic;

  /// Apply to every UI transition; feedback visibility is not an animation.
  static Duration motionDuration(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  // Metrics -----------------------------------------------------------------

  static const double borderWidth = 1;
  static const double overlayIconSize = 20;
  static const double buttonIconSize = 18;
  static const double styleNameFontSize = 13;
  static const double fringeOpacity = 0.55;
  static const double fringeTextOffset = 3;
  static const double fringeTextAlpha = 0.9;
  static const double fringeRingOffset = 1.5;

  /// Viewfinder geometry, typography and motion.
  static const double stylePillMaxWidth = 220;
  static const double diagnosticsMinWidth = 420;
  static const double shutterSideOffset = 94;
  static const double pulseRingDiameter = 92;
  static const double swipeEdgeDeadZone = 24;
  static const double hintMinViewportHeight = 520;
  static const double controlFontSize = 14;
  static const double statusFontSize = 12;
  static const double hintLineHeight = 1.3;
  static const double ringStrokeWidth = 2;
  static const double shutterStrokeWidth = 3;
  static const double shutterInset = 5;
  static const Duration styleFeedbackDuration = Duration(milliseconds: 1500);
  static const Duration styleFeedbackReducedDuration = Duration(
    milliseconds: 2500,
  );
  static const Duration feedbackTransitionDuration = Duration(
    milliseconds: 160,
  );

  /// Diameter of the round shutter button.
  static const double shutterSize = 76;

  /// Hit area side length of square overlay icon buttons (flip, settings).
  static const double iconButtonSize = 48;

  /// Smallest size a finger can hit without aiming.
  static const double touchTarget = 48;

  /// Size of the icons of the legend of the three levels.
  static const double legendIconSize = 14;

  /// Size of the icons of the three levels of the meters card.
  static const double meterIconSize = 16;

  /// Size of the icon that says that the meters card opens the help.
  static const double meterInfoIconSize = 14;

  /// Length of the bars of the three levels of the meters card.
  static const double meterBarLength = 56;

  /// Thickness of the bars of the three levels of the meters card.
  static const double meterBarThickness = 4;

  /// Height that the card of the three levels reserves in the viewfinder.
  static const double legendHeight = 72;

  /// Height of the row of the style chips of the viewfinder.
  static const double styleChipsHeight = 36;

  /// Height of the row that shows the name of the style of the viewfinder.
  static const double styleBarHeight = 48;

  /// Height of the line that says what the camera is doing.
  ///
  /// The space is always reserved, so the shutter never moves when the
  /// message appears or disappears.
  static const double statusSlotHeight = 24;

  /// Fraction of the screen that the sheet of the styles may use.
  static const double styleSheetMaxHeightFactor = 0.7;

  /// Height of the message that says the picture is being taken.
  static const double capturingHeight = 22;

  /// Height of the tip card of the viewfinder.
  ///
  /// The card is short on purpose: it must not push the shutter or the
  /// style chips out of the screen.
  static const double tipCardMaxHeight = 64;

  /// Width of the tip card of the viewfinder.
  static const double tipCardMaxWidth = 360;

  /// The dark Material 3 theme used by the whole app.
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: surfaceHigh,
      onPrimaryContainer: textPrimary,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: surfaceHigh,
      onSecondaryContainer: textPrimary,
      error: danger,
      onError: Color(0xFF2A0E0E),
      surface: surface,
      onSurface: textPrimary,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: textSecondary,
      surfaceTint: Colors.transparent,
      outline: edge,
      outlineVariant: outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      focusColor: focusOverlay,
      splashFactory: InkRipple.splashFactory,
    );
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
    );
    const controlSize = WidgetStatePropertyAll(Size(64, touchTarget));
    final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) return pressedOverlay;
      if (states.contains(WidgetState.focused)) return focusOverlay;
      return null;
    });
    final buttonStyle = ButtonStyle(
      minimumSize: controlSize,
      shape: const WidgetStatePropertyAll(controlShape),
      textStyle: const WidgetStatePropertyAll(label),
      iconSize: const WidgetStatePropertyAll(buttonIconSize),
      overlayColor: overlay,
      animationDuration: pressDuration,
    );
    const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
      borderSide: BorderSide(color: edge, width: borderWidth),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            displayLarge: headline,
            displayMedium: headline,
            displaySmall: headline,
            headlineLarge: headline,
            headlineMedium: headline,
            headlineSmall: headline,
            titleLarge: title,
            titleMedium: sheetTitle,
            titleSmall: readout,
            bodyLarge: body,
            bodyMedium: body,
            bodySmall: bodySmall,
            labelLarge: label,
            labelMedium: label,
            labelSmall: micro,
          ),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? textTertiary
                : textPrimary,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: edge, width: borderWidth),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.square(touchTarget)),
          shape: const WidgetStatePropertyAll(controlShape),
          iconSize: const WidgetStatePropertyAll(overlayIconSize),
          overlayColor: overlay,
          animationDuration: pressDuration,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        titleTextStyle: title,
        shape: Border(
          bottom: BorderSide(color: outline, width: borderWidth),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          side: BorderSide(color: outline, width: borderWidth),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: accentTint,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected) ? accent : edge,
            width: borderWidth,
          ),
        ),
        labelStyle: bodySmall,
        shape: controlShape,
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        filled: true,
        fillColor: surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spaceSmMd,
          vertical: spaceSmMd,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
          borderSide: BorderSide(color: accent, width: borderWidth),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
          borderSide: BorderSide(color: danger, width: borderWidth),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
          borderSide: BorderSide(color: danger, width: borderWidth),
        ),
        labelStyle: bodySmall,
        hintStyle: bodySmall,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onAccent : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : background,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : edge,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(borderWidth),
        overlayColor: overlay,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: spaceMd),
        titleTextStyle: readout.copyWith(
          fontWeight: FontWeight.w500,
          fontFeatures: const [],
        ),
        subtitleTextStyle: bodySmall,
        selectedColor: accent,
        selectedTileColor: accentTint,
        shape: controlShape,
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        space: borderWidth,
        thickness: borderWidth,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
          side: BorderSide(color: outline, width: borderWidth),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        textStyle: bodySmall,
        decoration: BoxDecoration(
          color: surfaceHigh,
          borderRadius: BorderRadius.all(Radius.circular(radiusXs)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
          side: BorderSide(color: outline, width: borderWidth),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: sheetTitle,
        contentTextStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: outline, width: borderWidth),
        ),
      ),
    );
  }
}
