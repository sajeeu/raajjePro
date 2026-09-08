import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/features/auth/presentation/session_expired_screen.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/features/gallery/presentation/gallery_screen.dart';
import 'package:raajjepro/features/legal/presentation/legal_placeholder_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// Root widget. Routing is a plain named-route table; the root route is the
/// AuthGate, which switches on the one auth state. Account routes are added
/// by Tasks 8–9 (import `account_settings_screen.dart` once it exists; that
/// file does not exist yet, so `/account` stays an unregistered route the
/// signed-in home links to — same gap Task 6 left at `/account/change-email`).
class RaajjeProApp extends ConsumerStatefulWidget {
  const RaajjeProApp({super.key});
  @override
  ConsumerState<RaajjeProApp> createState() => _RaajjeProAppState();
}

class _RaajjeProAppState extends ConsumerState<RaajjeProApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authControllerProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RaajjePro',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (_) => const AuthGate(),
        SignInScreen.routeName: (_) => const SignInScreen(),
        RegisterScreen.routeName: (_) => const RegisterScreen(),
        '/forgot-password': (_) =>
            const _ComingSoon(title: 'Forgot password', phase: '3b'),
        '/legal/terms': (_) =>
            const LegalPlaceholderScreen(title: 'Terms of Service'),
        '/legal/privacy': (_) =>
            const LegalPlaceholderScreen(title: 'Privacy Policy'),
        GalleryScreen.routeName: (_) => const GalleryScreen(),
        // Task 8 adds: AccountSettingsScreen.routeName and its sub-screens.
      },
      onGenerateRoute: (settings) {
        if (settings.name == VerifyEmailScreen.routeName) {
          return MaterialPageRoute<void>(
            builder: (_) => VerifyEmailScreen(
              args: VerifyEmailArgs.fromRouteArguments(settings.arguments),
            ),
          );
        }
        return null;
      },
    );
  }
}

/// Picks the root screen from the auth state (spec §8). Guests browse freely.
///
/// `AuthController.restore()` maps a launch-time network failure to
/// [AuthGuest] while leaving any stored tokens in place (plan: offline is not
/// signed out) — so a user who launched offline reads as a guest until
/// something asks again. This listens for the app returning to the
/// foreground and, only when still a guest with tokens still on file, retries
/// `restore()` so connectivity coming back is picked up without a restart.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _retryIfStillGuest);
  }

  Future<void> _retryIfStillGuest() async {
    if (ref.read(authControllerProvider) is! AuthGuest) return;
    final tokens = await ref.read(tokenStoreProvider).read();
    if (tokens == null) return;
    await ref.read(authControllerProvider.notifier).restore();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return switch (state) {
      AuthUnknown() => const Scaffold(
        body: SkeletonLoader(child: SkeletonRow()),
      ),
      AuthSessionExpired() => const SessionExpiredScreen(),
      AuthGuest() => const _PlaceholderHome(user: null),
      AuthSignedIn(:final user) => _PlaceholderHome(user: user),
    };
  }
}

/// Phase 0's boot screen, still the home until Phase 16. Phase 3 adds the
/// two entries it needs — Sign in for a guest, Account settings for a user —
/// the latter a temporary bridge until Phase 6's Profile owns that row.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome({required this.user});
  final UserAccount? user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader.brand(),
          Expanded(
            child: Center(
              child: Padding(
                padding: AppSpacing.screenInsets,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('RaajjePro', style: context.type.screenTitle),
                    const SizedBox(height: AppSpacing.xl),
                    if (user == null)
                      AppButton.primary(
                        label: 'Sign in',
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed(SignInScreen.routeName),
                      )
                    else
                      AppButton.secondary(
                        label: 'Account settings',
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/account'),
                      ),
                    if (user != null && !user!.emailVerified) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppButton.text(
                        label: 'Verify your email',
                        onPressed: () => Navigator.of(context).pushNamed(
                          VerifyEmailScreen.routeName,
                          arguments: VerifyEmailArgs(
                            email: user!.email,
                            purpose: OtpPurpose.verifyEmail,
                          ),
                        ),
                      ),
                    ],
                    if (kDebugMode) ...[
                      const SizedBox(height: AppSpacing.xl),
                      AppButton.text(
                        label: 'Component gallery',
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed(GalleryScreen.routeName),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.phase});
  final String title;
  final String phase;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        AppHeader.page(
          title: title,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: AppSpacing.screenInsets,
              child: EmptyState(
                icon: Icons.construction_outlined,
                title: 'Not built yet',
                body: 'This flow arrives in Phase $phase.',
                actionLabel: 'Back',
                onAction: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
