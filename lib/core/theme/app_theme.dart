import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
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
        elevation: 0,
        barrierColor: scheme.scrim.withValues(alpha: isDark ? .24 : .06),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: scheme.scrim.withValues(alpha: isDark ? .24 : .06),
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}

enum NirangGlassStyle { surface, chrome, popover, dialog, bottomSheet }

/// Shared glass values. Keeping them here prevents light surfaces from turning
/// into opaque white panels while individual widgets drift to unrelated blur
/// and tint values.
abstract final class NirangGlassTokens {
  // Light chrome keeps a low tint above the filtered backdrop so the effect is
  // visible on pale Android surfaces instead of reading as an opaque card.
  static const lightSurfaceAlpha = .56;
  static const lightChromeAlpha = .58;
  static const lightPopoverAlpha = .56;
  static const lightDialogAlpha = .62;
  static const lightBottomSheetAlpha = .58;
  static const lightSurfaceBlur = 12.0;
  static const lightChromeBlur = 12.0;
  static const lightPopoverBlur = 14.0;
  static const lightDialogBlur = 14.0;
  static const lightBottomSheetBlur = 14.0;

  // Dark values intentionally stay aligned with the existing, approved look.
  static const darkSurfaceTopAlpha = .72;
  static const darkSurfaceBottomAlpha = .50;
  static const darkSurfaceBlur = 9.0;
  static const darkPopoverAlpha = .90;
  static const darkPopoverBlur = 7.0;
  static const darkChromeAlpha = .82;
  static const darkChromeBlur = 7.0;
  static const darkDialogAlpha = .80;
  static const darkDialogBlur = 10.0;
  static const darkBottomSheetAlpha = .86;
  static const darkBottomSheetBlur = 9.0;

  static const reducedLightAlpha = 1.0;
  static const reducedDarkAlpha = 1.0;
  static const lightBorderAlpha = .46;
  static const darkBorderAlpha = .48;
  static const lightShadowAlpha = .07;
  static const darkShadowAlpha = .18;

  static double blur(ThemeData theme, NirangGlassStyle style) {
    final dark = theme.brightness == Brightness.dark;
    if (dark) {
      return switch (style) {
        NirangGlassStyle.surface => darkSurfaceBlur,
        NirangGlassStyle.chrome => darkChromeBlur,
        NirangGlassStyle.popover => darkPopoverBlur,
        NirangGlassStyle.dialog => darkDialogBlur,
        NirangGlassStyle.bottomSheet => darkBottomSheetBlur,
      };
    }
    return switch (style) {
      NirangGlassStyle.surface => lightSurfaceBlur,
      NirangGlassStyle.chrome => lightChromeBlur,
      NirangGlassStyle.popover => lightPopoverBlur,
      NirangGlassStyle.dialog => lightDialogBlur,
      NirangGlassStyle.bottomSheet => lightBottomSheetBlur,
    };
  }

  static double alpha(ThemeData theme, NirangGlassStyle style) {
    if (theme.brightness == Brightness.dark) {
      return switch (style) {
        NirangGlassStyle.surface => darkSurfaceTopAlpha,
        NirangGlassStyle.chrome => darkChromeAlpha,
        NirangGlassStyle.popover => darkPopoverAlpha,
        NirangGlassStyle.dialog => darkDialogAlpha,
        NirangGlassStyle.bottomSheet => darkBottomSheetAlpha,
      };
    }
    return switch (style) {
      NirangGlassStyle.surface => lightSurfaceAlpha,
      NirangGlassStyle.chrome => lightChromeAlpha,
      NirangGlassStyle.popover => lightPopoverAlpha,
      NirangGlassStyle.dialog => lightDialogAlpha,
      NirangGlassStyle.bottomSheet => lightBottomSheetAlpha,
    };
  }

  static double borderAlpha(ThemeData theme) =>
      theme.brightness == Brightness.dark ? darkBorderAlpha : lightBorderAlpha;

  static double shadowAlpha(ThemeData theme) =>
      theme.brightness == Brightness.dark ? darkShadowAlpha : lightShadowAlpha;
}

abstract final class NirangVisualEffects {
  static BoxDecoration shellBackground(
    ThemeData theme, {
    required bool reducedEffects,
  }) {
    final background = theme.scaffoldBackgroundColor;
    if (reducedEffects) return BoxDecoration(color: background);

    final scheme = theme.colorScheme;
    if (theme.brightness == Brightness.dark) {
      return BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.72, -.82),
          radius: 1.45,
          colors: [
            scheme.primary.withValues(alpha: .14),
            scheme.secondary.withValues(alpha: .055),
            background,
          ],
          stops: const [0, .38, 1],
        ),
      );
    }

    // Keep every light-mode gradient stop opaque. Transparent gradient stops
    // can be composited as black by some Android GPU drivers when combined
    // with a backdrop filter.
    final primaryGlow = Color.alphaBlend(
      scheme.primary.withValues(alpha: .075),
      background,
    );
    final secondaryGlow = Color.alphaBlend(
      scheme.secondary.withValues(alpha: .028),
      background,
    );
    return BoxDecoration(
      color: background,
      gradient: RadialGradient(
        center: const Alignment(.78, -.94),
        radius: 1.55,
        colors: [primaryGlow, secondaryGlow, background],
        stops: const [0, .48, 1],
      ),
    );
  }
}
