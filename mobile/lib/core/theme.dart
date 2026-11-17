import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Hoop Archive palette: near-black instrument panels with a single volt
/// accent. Volt is reserved for the active selection, the leader, and live
/// alerts. Everything else is ground, hairline, and gray.
class Hue {
  const Hue._();

  static const Color ground = Color(0xFF0A0A0A);
  static const Color panel = Color(0xFF131313);
  static const Color raised = Color(0xFF1B1B1B);
  static const Color hairline = Color(0xFF262626);
  static const Color hairlineStrong = Color(0xFF333333);
  static const Color track = Color(0xFF2A2A2A);
  static const Color line = Color(0xFF6E6E6A);

  static const Color textHi = Color(0xFFF2F2F0);
  static const Color textMid = Color(0xFFA3A39F);
  static const Color textLo = Color(0xFF85857F);

  static const Color volt = Color(0xFFD8F03F);
  static const Color onVolt = Color(0xFF0A0A0A);
  static const Color alert = Color(0xFFFF7A66);
}

/// Type scale. SF Pro carries everything; numerals are heavy and tabular so
/// figures don't jitter while scrubbing.
class Txt {
  const Txt._();

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static const TextStyle numeralXL = TextStyle(
    fontSize: 84,
    height: 0.95,
    fontWeight: FontWeight.w800,
    letterSpacing: -3.2,
    color: Hue.textHi,
    fontFeatures: _tabular,
  );

  static const TextStyle numeralL = TextStyle(
    fontSize: 56,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -2.0,
    color: Hue.textHi,
    fontFeatures: _tabular,
  );

  static const TextStyle numeralM = TextStyle(
    fontSize: 28,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: Hue.textHi,
    fontFeatures: _tabular,
  );

  static const TextStyle numeralS = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: Hue.textHi,
    fontFeatures: _tabular,
  );

  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    color: Hue.textHi,
  );

  static const TextStyle title = TextStyle(
    fontSize: 26,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: Hue.textHi,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: Hue.textHi,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    color: Hue.textHi,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: Hue.textMid,
  );

  /// Small tracked caps. Callers pass the text already uppercased where it is
  /// a label; data (team codes, metric keys) is uppercase by nature.
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
    color: Hue.textMid,
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Hue.volt,
      onPrimary: Hue.onVolt,
      secondary: Hue.textHi,
      onSecondary: Hue.ground,
      error: Hue.alert,
      onError: Hue.ground,
      surface: Hue.ground,
      onSurface: Hue.textHi,
      onSurfaceVariant: Hue.textMid,
      surfaceContainerLowest: Hue.ground,
      surfaceContainerLow: Hue.panel,
      surfaceContainer: Hue.panel,
      surfaceContainerHigh: Hue.raised,
      surfaceContainerHighest: Hue.raised,
      outline: Hue.hairlineStrong,
      outlineVariant: Hue.hairline,
      inverseSurface: Hue.textHi,
      onInverseSurface: Hue.ground,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Hue.ground,
      canvasColor: Hue.ground,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.white.withValues(alpha: 0.04),
      hoverColor: Colors.white.withValues(alpha: 0.03),
      dividerColor: Hue.hairline,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Hue.textHi,
        displayColor: Hue.textHi,
      ),
      dividerTheme: const DividerThemeData(
        color: Hue.hairline,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Hue.volt,
        selectionColor: Hue.volt.withValues(alpha: 0.32),
        selectionHandleColor: Hue.volt,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Hue.volt),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Hue.volt,
          foregroundColor: Hue.onVolt,
          minimumSize: const Size(44, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Hue.textHi,
          minimumSize: const Size(44, 50),
          side: const BorderSide(color: Hue.hairlineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Hue.volt,
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Hue.panel,
        modalBackgroundColor: Hue.panel,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: Hue.hairlineStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Hue.textLo.withValues(alpha: 0.5)),
        thickness: const WidgetStatePropertyAll(3),
        radius: const Radius.circular(3),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Hue.raised,
        contentTextStyle: Txt.body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Hue.hairline),
        ),
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: Hue.volt,
        primaryContrastingColor: Hue.onVolt,
        scaffoldBackgroundColor: Hue.ground,
        barBackgroundColor: Hue.ground,
        textTheme: CupertinoTextThemeData(
          primaryColor: Hue.volt,
          navLargeTitleTextStyle: Txt.largeTitle,
          navTitleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: Hue.textHi,
          ),
          navActionTextStyle: TextStyle(
            fontSize: 17,
            letterSpacing: -0.4,
            color: Hue.volt,
          ),
          tabLabelTextStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          textStyle: Txt.body,
        ),
      ),
    );
  }
}
