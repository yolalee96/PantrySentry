import 'package:flutter/material.dart';

/// Design tokens grounded in the app's actual subject — fresh food, cold
/// storage, a pantry shelf — rather than a generic productivity-app
/// palette. Deliberately avoids the two most common AI-generated
/// defaults: a warm cream+terracotta look, and the "every card identical,
/// same soft shadow" SaaS-card treatment. Hierarchy here comes from
/// contrast (solid "hero" fills vs quiet hairline cards), not uniformity.
class AppTheme {
  // ---- Core palette --------------------------------------------------
  /// Deep, saturated herb green — richer than a flat default green.
  static const seedColor = Color(0xFF1F6E44);
  static const basilLight = Color(0xFFDCEEE1);

  /// Burnt paprika — used for waste/danger states instead of a stock red.
  static const paprika = Color(0xFFC1442D);
  static const paprikaLight = Color(0xFFF7E1DC);

  /// Warm honey gold — "expiring soon" / caution, instead of flat amber.
  static const honey = Color(0xFFB9832A);
  static const honeyLight = Color(0xFFF3E4C7);

  /// Muted ocean blue — cold storage / informational accent.
  static const ocean = Color(0xFF2B6CA3);
  static const oceanLight = Color(0xFFDCE9F2);

  /// Deep green-charcoal ink instead of flat black — ties body text back
  /// into the palette rather than using a neutral default.
  static const ink = Color(0xFF1B2420);

  /// Soft, near-white app canvas.
  static const backgroundColor = Color(0xFFF7FAF8);

  /// Cool neutral border tone for hairline cards/inputs on the white base.
  static const borderColor = Color(0xFFC7D0CB);

  /// Bold, tabular-figure treatment for headline stat numbers — the
  /// recurring signature motif, since this app is fundamentally about
  /// numbers (counts, percentages, days left).
  static const TextStyle statNumberStyle = TextStyle(
    fontWeight: FontWeight.w900,
    letterSpacing: -1.2,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A "hero" card treatment — solid colour fill, white text — for the
  /// headline content on a screen. Use sparingly (one or two per screen)
  /// so it still reads as emphasis rather than becoming the new uniform.
  static BoxDecoration heroFill(Color color) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      );

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(seedColor: seedColor).copyWith(
      error: paprika,
      tertiary: honey,
    );

    final baseTextTheme = ThemeData.light().textTheme;
    final textTheme = baseTextTheme.copyWith(
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.15,
        color: ink,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: ink,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: ink),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.4, color: ink.withValues(alpha: 0.75)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.grey.shade200, width: 1.2),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderColor, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderColor, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 2.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: paprika, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: paprika, width: 2),
        ),
        floatingLabelStyle: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: borderColor, width: 1.4),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey.shade100,
        selectedColor: colorScheme.primary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? colorScheme.primary : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.white : ink),
          side: WidgetStateProperty.all(const BorderSide(color: borderColor, width: 1.4)),
          textStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        indicatorColor: colorScheme.primary,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colorScheme.primary : Colors.grey.shade600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? Colors.white : Colors.grey.shade500);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.grey.shade300,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade300, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: Colors.grey.shade700,
        titleTextStyle: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Days-left -> colour, used consistently across item cards / lists.
/// Basil -> honey -> paprika, mirroring the app's core palette rather
/// than a generic traffic-light red/amber/green.
Color urgencyColor(int daysLeft) {
  if (daysLeft < 0) return const Color(0xFF8C2E1E); // overdue: darker paprika
  if (daysLeft <= 1) return AppTheme.paprika;
  if (daysLeft <= 3) return const Color(0xFFCB6A28); // between honey and paprika
  if (daysLeft <= 7) return AppTheme.honey;
  return AppTheme.seedColor;
}
