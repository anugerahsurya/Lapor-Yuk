import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kFont = 'PlusJakartaSans';

/// Brand colour families. One dominant colour + white; amber is a small
/// accent only (sun, primary action), like a single highlight.
enum AccentScheme { royal, navy, pink, orange }

const _royal = Color(0xFF2F5FEA);
const _navy = Color(0xFF1F3170);
const _pink = Color(0xFFE24C86);
const _orange = Color(0xFFEC6A2C);

/// Design tokens.
///  * [brand]   strong fill (buttons, nav, selected states) with [onBrand] text
///  * [primary] tint for text/icons on neutral surfaces
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.line,
    required this.primary,
    required this.primarySoft,
    required this.brand,
    required this.onBrand,
    required this.accent,
    required this.success,
    required this.danger,
    required this.navBg,
    required this.navInk,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color line;
  final Color primary;
  final Color primarySoft;
  final Color brand;
  final Color onBrand;
  final Color accent;
  final Color success;
  final Color danger;
  final Color navBg;
  final Color navInk;

  static Color brandOf(AccentScheme s) => switch (s) {
    AccentScheme.royal => _royal,
    AccentScheme.navy => _navy,
    AccentScheme.pink => _pink,
    AccentScheme.orange => _orange,
  };

  factory AppColors.of(Brightness b, AccentScheme scheme) {
    final brand = brandOf(scheme);
    if (b == Brightness.light) {
      return AppColors(
        bg: const Color(0xFFF4F6FB),
        surface: const Color(0xFFFFFFFF),
        surface2: const Color(0xFFEDF1F9),
        ink: const Color(0xFF111A33),
        muted: const Color(0xFF66708A),
        line: const Color(0xFFE1E6F0),
        primary: brand,
        primarySoft: Color.lerp(Colors.white, brand, .1)!,
        brand: brand,
        onBrand: Colors.white,
        accent: const Color(0xFFF5B83D),
        success: const Color(0xFF2F9E6E),
        danger: const Color(0xFFD9483F),
        navBg: brand,
        navInk: Colors.white,
      );
    }
    final (fill, tint) = switch (scheme) {
      AccentScheme.royal => (_royal, const Color(0xFF86A4FF)),
      AccentScheme.navy => (const Color(0xFF2E4592), const Color(0xFF9DB0EC)),
      AccentScheme.pink => (const Color(0xFFC13B6E), const Color(0xFFF59CBE)),
      AccentScheme.orange => (const Color(0xFFCB5A20), const Color(0xFFF6B183)),
    };
    const surface = Color(0xFF121A2C);
    return AppColors(
      bg: const Color(0xFF0A0F1C),
      surface: surface,
      surface2: const Color(0xFF19233A),
      ink: const Color(0xFFE8EDF7),
      muted: const Color(0xFF8A95AE),
      line: const Color(0xFF222D46),
      primary: tint,
      primarySoft: Color.lerp(surface, tint, .16)!,
      brand: fill,
      onBrand: Colors.white,
      accent: const Color(0xFFF5BE4E),
      success: const Color(0xFF4CC08D),
      danger: const Color(0xFFF07167),
      navBg: fill,
      navInk: Colors.white,
    );
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      primary: l(primary, other.primary),
      primarySoft: l(primarySoft, other.primarySoft),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      accent: l(accent, other.accent),
      success: l(success, other.success),
      danger: l(danger, other.danger),
      navBg: l(navBg, other.navBg),
      navInk: l(navInk, other.navInk),
    );
  }
}

extension AppThemeX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

ThemeData buildTheme(Brightness b, AccentScheme scheme) {
  final c = AppColors.of(b, scheme);
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: kFont,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: b,
      primary: c.primary,
      surface: c.surface,
      error: c.danger,
    ),
  );
  TextStyle s(double size, FontWeight w, {double h = 1.3, double ls = 0}) =>
      TextStyle(fontFamily: kFont, fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: c.ink);

  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: TextTheme(
      displaySmall: s(34, FontWeight.w800, h: 1.1, ls: -1.0),
      headlineMedium: s(26, FontWeight.w800, h: 1.15, ls: -0.6),
      headlineSmall: s(21, FontWeight.w700, h: 1.2, ls: -0.3),
      titleLarge: s(18, FontWeight.w700, ls: -0.2),
      titleMedium: s(15.5, FontWeight.w600),
      titleSmall: s(13.5, FontWeight.w600),
      bodyLarge: s(15.5, FontWeight.w400, h: 1.45),
      bodyMedium: s(14, FontWeight.w400, h: 1.45),
      bodySmall: s(12.5, FontWeight.w500, h: 1.4).copyWith(color: c.muted),
      labelLarge: s(14.5, FontWeight.w700),
      labelMedium: s(12.5, FontWeight.w600),
      labelSmall: s(11, FontWeight.w700, ls: 0.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.ink,
      systemOverlayStyle: b == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: c.muted.withValues(alpha: .8), fontWeight: FontWeight.w400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger, width: 1.6),
      ),
      errorStyle: TextStyle(color: c.danger, fontWeight: FontWeight.w500),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primary,
      selectionColor: c.primary.withValues(alpha: .25),
      selectionHandleColor: c.primary,
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.surface,
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.navBg,
      contentTextStyle: TextStyle(fontFamily: kFont, color: c.navInk, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}

/// Shared motion tokens so every interaction feels like the same app.
abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
  static const ease = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;
}
