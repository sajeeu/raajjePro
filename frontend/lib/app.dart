import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/routes.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/features/account/presentation/active_sessions_screen.dart';
import 'package:raajjepro/features/account/presentation/change_email_screen.dart';
import 'package:raajjepro/features/account/presentation/change_password_screen.dart';
import 'package:raajjepro/features/account/presentation/change_phone_screen.dart';
import 'package:raajjepro/features/account/presentation/delete_account_screen.dart';
import 'package:raajjepro/features/account/presentation/download_data_screen.dart';
import 'package:raajjepro/features/auth/presentation/forgot_password_screen.dart';
import 'package:raajjepro/features/auth/presentation/register_screen.dart';
import 'package:raajjepro/features/auth/presentation/session_expired_screen.dart';
import 'package:raajjepro/features/auth/presentation/sign_in_screen.dart';
import 'package:raajjepro/features/auth/presentation/verify_email_screen.dart';
import 'package:raajjepro/features/explore/presentation/explore_screen.dart';
import 'package:raajjepro/features/gallery/presentation/gallery_screen.dart';
import 'package:raajjepro/features/legal/presentation/legal_index_screen.dart';
import 'package:raajjepro/features/legal/presentation/legal_placeholder_screen.dart';
import 'package:raajjepro/features/profile/controller/role_switch.dart';
import 'package:raajjepro/features/profile/presentation/profile_screen.dart';
import 'package:raajjepro/shared/shared.dart';

/// Root widget. Routing is a plain named-route table; the root route is the
/// AuthGate, which switches on the one auth state. Task 8 adds `/account`,
/// `/account/sessions`, `/account/download` and `/account/delete`. Task 9
/// adds `/account/password`, `/account/change-email` and `/account/phone` —
/// the last two close the gap Task 6 left where `VerifyEmailScreen`'s "Not
/// your address? Change it" link and `AccountSettingsScreen`'s row already
/// pushed those names.
class RaajjeProApp extends ConsumerStatefulWidget {
  const RaajjeProApp({super.key});

  /// Shared with the Navigator so [_RaajjeProAppState] can pop back to root
  /// from outside the widget tree that pushed the open route — the only way
  /// a session expiring under a pushed screen (`/account/phone`, say) can
  /// reach [AuthGate] and show [SessionExpiredScreen] instead of leaving that
  /// screen on top forever.
  static final navigatorKey = GlobalKey<NavigatorState>();

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
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is AuthSessionExpired) {
        RaajjeProApp.navigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
    });
    return MaterialApp(
      title: 'RaajjePro',
      navigatorKey: RaajjeProApp.navigatorKey,
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (_) => const AuthGate(),
        SignInScreen.routeName: (_) => const SignInScreen(),
        RegisterScreen.routeName: (_) => const RegisterScreen(),
        ForgotPasswordScreen.routeName: (_) => const ForgotPasswordScreen(),
        '/legal/terms': (_) =>
            const LegalPlaceholderScreen(title: 'Terms of Service'),
        '/legal/privacy': (_) =>
            const LegalPlaceholderScreen(title: 'Privacy Policy'),
        ExploreScreen.routeName: (_) => const ExploreScreen(),
        GalleryScreen.routeName: (_) => const GalleryScreen(),
        AccountSettingsScreen.routeName: (_) => const AccountSettingsScreen(),
        ActiveSessionsScreen.routeName: (_) => const ActiveSessionsScreen(),
        DownloadDataScreen.routeName: (_) => const DownloadDataScreen(),
        DeleteAccountScreen.routeName: (_) => const DeleteAccountScreen(),
        ChangePasswordScreen.routeName: (_) => const ChangePasswordScreen(),
        ChangeEmailScreen.routeName: (_) => const ChangeEmailScreen(),
        ChangePhoneScreen.routeName: (_) => const ChangePhoneScreen(),

        // Phase 6. Profile itself, plus every destination its five rows,
        // four booking tiles and role switcher reach. A row that navigates
        // nowhere would leave §Phase 6's Done-when unprovable and a user
        // unable to tell a dead control from a slow one, so each name is
        // real and the ones whose screens do not exist yet land on
        // `UnbuiltScreen` naming the phase that owes them.
        ProfileScreen.routeName: (_) => const ProfileScreen(),
        LegalIndexScreen.routeName: (_) => const LegalIndexScreen(),
        AppRoutes.saved: (_) =>
            const UnbuiltScreen(title: 'Saved', owedBy: 'Phase 14'),
        AppRoutes.savedPreferences: (_) => const UnbuiltScreen(
          title: 'Saved preferences',
          // Deferred out of Phase 3's Account settings and past Phase 6:
          // labelled addresses need `Island`
          // (`docs/decisions/12-phase-3-identity.md`, decision 2).
          //
          // 🔧 **Phase 7 built `Island` and did not take this screen.**
          // §Phase 7's bullets and Done-when name it nowhere, and no section
          // of the plan specifies its entity shape or endpoints, so Phase 7
          // declined to invent them
          // (`docs/decisions/19-phase-7-service-areas.md`, decision 1).
          // §1h is what asks for it — saved addresses, preferred windows and
          // standing instructions "reused across bookings" and "carried
          // forward by Book Again" — which is Phase 17.4's slice, and before
          // bookings exist a saved preference has nothing to be used by.
          owedBy: 'Phase 17.4',
        ),
        AppRoutes.help: (_) =>
            const UnbuiltScreen(title: 'Help & support', owedBy: 'Phase 19b'),
        RoleSwitch.onboardingRoute: (_) =>
            const UnbuiltScreen(title: 'Become a Provider', owedBy: 'Phase 6a'),
        RoleSwitch.dashboardRoute: (_) =>
            const UnbuiltScreen(title: 'My Services', owedBy: 'Phase 10'),
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

  /// Guards against two quick resumes overlapping: without it, a resume
  /// while a previous `restore()` is still in flight fires a second `me`
  /// call before the first returns. Idempotent either way, but there is no
  /// reason to make two calls for one resume.
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _retryIfStillGuest);
  }

  Future<void> _retryIfStillGuest() async {
    if (_restoring) return;
    if (ref.read(authControllerProvider) is! AuthGuest) return;
    // Set before the first `await`: two resumes fired back to back (no
    // intervening event-loop turn) both pass the checks above before either
    // yields, so the flag has to be claimed synchronously here for the
    // second call to see it — setting it after the token read would still
    // let both through.
    _restoring = true;
    try {
      final tokens = await ref.read(tokenStoreProvider).read();
      if (tokens == null) return;
      await ref.read(authControllerProvider.notifier).restore();
    } finally {
      _restoring = false;
    }
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
/// two entries it needs — Sign in for a guest, and for a signed-in user the
/// entry that was a temporary Account-settings bridge until Phase 6 built
/// Profile; it now goes to Profile, which carries Account settings as one of
/// its rows. Phase 4 adds Explore, reachable by everyone: the category grid
/// is public and a guest must be able to browse it (§0.2).
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
                    AppButton.primary(
                      label: 'Explore services',
                      onPressed: () =>
                          Navigator.of(context)
                              .pushNamed(ExploreScreen.routeName),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (user == null)
                      AppButton.secondary(
                        label: 'Sign in',
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed(SignInScreen.routeName),
                      )
                    else
                      AppButton.secondary(
                        label: 'Profile',
                        onPressed: () =>
                            Navigator.of(context)
                                .pushNamed(ProfileScreen.routeName),
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
