import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const primary = Color(0xFF625BD2);
  static const lightCanvas = Color(0xFFF8F8FC);
  static const darkCanvas = Color(0xFF10111A);
  static const lightSuccess = Color(0xFF287A62);
  static const darkSuccess = Color(0xFF6FC5AA);
  static const lightWarning = Color(0xFF9A6717);
  static const darkWarning = Color(0xFFE0B465);
}

@immutable
class NirangSemanticColors extends ThemeExtension<NirangSemanticColors> {
  const NirangSemanticColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  @override
  NirangSemanticColors copyWith({Color? success, Color? warning}) =>
      NirangSemanticColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
      );

  @override
  NirangSemanticColors lerp(covariant NirangSemanticColors? other, double t) =>
      other == null
      ? this
      : NirangSemanticColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

extension NirangThemeContext on BuildContext {
  NirangSemanticColors get semanticColors =>
      Theme.of(this).extension<NirangSemanticColors>()!;
}

abstract final class AppTheme {
  static final ThemeData light = _theme(Brightness.light, false);
  static final ThemeData dark = _theme(Brightness.dark, false);
  static final ThemeData lightPerformance = _theme(Brightness.light, true);
  static final ThemeData darkPerformance = _theme(Brightness.dark, true);

  static ThemeData _theme(Brightness brightness, bool reducedEffects) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primary,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? AppPalette.darkCanvas
          : AppPalette.lightCanvas,
      extensions: [
        NirangSemanticColors(
          success: isDark ? AppPalette.darkSuccess : AppPalette.lightSuccess,
          warning: isDark ? AppPalette.darkWarning : AppPalette.lightWarning,
        ),
      ],
      visualDensity: VisualDensity.compact,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: reducedEffects
              ? const FadeUpwardsPageTransitionsBuilder()
              : const ZoomPageTransitionsBuilder(
                  allowEnterRouteSnapshotting: true,
                ),
        },
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .55),
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface.withValues(alpha: .78),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow.withValues(alpha: isDark ? .76 : .82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .45)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        minVerticalPadding: 8,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 1),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 2,
        backgroundColor: scheme.surfaceContainerHigh.withValues(
          alpha: isDark ? .91 : .93,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 2,
        modalBackgroundColor: scheme.surfaceContainer.withValues(
          alpha: isDark ? .94 : .96,
        ),
        modalBarrierColor: scheme.scrim.withValues(alpha: .28),
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
