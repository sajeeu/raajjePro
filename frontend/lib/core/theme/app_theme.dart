import 'package:flutter/material.dart';

import 'package:raajjepro/core/theme/app_colors.dart';
import 'package:raajjepro/core/theme/app_geometry.dart';
import 'package:raajjepro/core/theme/app_motion.dart';
import 'package:raajjepro/core/theme/app_typography.dart';

export 'package:raajjepro/core/theme/accent_tokens.dart';
export 'package:raajjepro/core/theme/app_colors.dart';
export 'package:raajjepro/core/theme/app_geometry.dart';
export 'package:raajjepro/core/theme/app_motion.dart';
export 'package:raajjepro/core/theme/app_typography.dart';

/// Builds the one [ThemeData] the app runs on. Tokens live in the two
/// `ThemeExtension`s; the Material colour scheme is filled from them so the
/// framework's own widgets (dialogs, text selection, ripples) match without
/// per-widget overrides.
abstract final class AppTheme {
  static ThemeData light() {
    const colors = AppColors.light();
    final type = AppTypography.inter(colors);

    final scheme = ColorScheme.light(
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      secondary: colors.accentText,
      onSecondary: colors.onPrimary,
      error: colors.error,
      onError: colors.onError,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.divider,
      surfaceContainerHighest: colors.neutralTint,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.divider,
      splashFactory: InkSparkle.splashFactory,
      // The Material floor is 48 too; stated here so nobody lowers it.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        headlineMedium: type.screenTitle,
        titleMedium: type.sectionHeading,
        titleSmall: type.cardTitle,
        bodyMedium: type.body,
        bodyLarge: type.bodyStrong,
        bodySmall: type.secondary,
        labelSmall: type.caption,
        labelLarge: type.button,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: colors.ink,
        titleTextStyle: type.sectionHeading,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colors.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: AppSizes.dividerStroke,
        space: AppSizes.dividerStroke,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.accentTint,
        selectionHandleColor: colors.primary,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
        },
      ),
      extensions: [colors, type],
    );
  }
}

/// `screenIn` from motion.css: fade plus a 26px slide from the trailing
/// edge, [AppMotion.page] long, on [AppMotion.easeOut]. Mirrors under RTL
/// because the offset is expressed in text direction. Under reduced motion
/// the route simply appears — the fade is kept at zero duration rather
/// than replaced, so there is one code path.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final motion = AppMotion.of(context);
    if (motion.reduced) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.easeOut);
    final direction = Directionality.of(context);
    final sign = direction == TextDirection.rtl ? -1.0 : 1.0;
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(sign * AppMotion.screenSlide * (1 - curved.value), 0),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

/// `context.colors`, `context.type`, `context.motion` — the only sanctioned
/// way for a widget to reach a token.
extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  AppTypography get type => Theme.of(this).extension<AppTypography>()!;
  ResolvedMotion get motion => AppMotion.of(this);
}
