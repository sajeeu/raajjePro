import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/form_draft_store.dart';
import 'package:raajjepro/features/auth/presentation/widgets/generic_error_copy.dart';

class ChangeFormState {
  const ChangeFormState({
    this.busy = false,
    this.fieldErrors = const {},
    this.offline = false,
    this.done = false,
  });
  final bool busy;
  final Map<String, String> fieldErrors;
  final bool offline;
  final bool done;
  ChangeFormState copyWith({
    bool? busy,
    Map<String, String>? fieldErrors,
    bool? offline,
    bool? done,
  }) => ChangeFormState(
    busy: busy ?? this.busy,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    offline: offline ?? this.offline,
    done: done ?? this.done,
  );
}

/// Shared error mapping for the three change forms. A dead session saves the
/// draft so the Session Expired promise holds (controller ruling #1:
/// non-secret fields only — never a password).
abstract class ChangeFormController extends Notifier<ChangeFormState> {
  @override
  ChangeFormState build() => const ChangeFormState();

  String get draftKey;

  Future<T?> run<T>(
    Future<T> Function() action, {
    required Map<String, String> draft,
    Map<String, String> Function(ApiException e)? mapError,
  }) async {
    state = state.copyWith(busy: true, fieldErrors: const {}, offline: false);
    try {
      final result = await action();
      state = state.copyWith(busy: false, done: true);
      return result;
    } on ApiException catch (e) {
      if (e.code == 'SESSION_EXPIRED') {
        ref.read(formDraftStoreProvider).save(draftKey, draft);
      }
      final errors = <String, String>{
        for (final f in e.fieldErrors) f.path.split('.').first: f.message,
      };
      state = state.copyWith(
        busy: false,
        fieldErrors: errors.isEmpty
            ? (mapError?.call(e) ?? {'form': genericErrorCopy})
            : errors,
      );
    } on ApiNetworkException {
      state = state.copyWith(busy: false, offline: true);
    }
    return null;
  }

  void local(Map<String, String> errors) =>
      state = state.copyWith(fieldErrors: errors);
  void clear(String path) => state = state.copyWith(
    fieldErrors: Map.of(state.fieldErrors)..remove(path),
  );
}

final changePasswordControllerProvider =
    NotifierProvider<ChangePasswordController, ChangeFormState>(
      ChangePasswordController.new,
    );

class ChangePasswordController extends ChangeFormController {
  @override
  String get draftKey => '/account/password';

  /// Brief-vs-toolchain: the brief passed `changePassword` (returns
  /// `Future<void>`) straight to `run<T>` and compared the result with
  /// `!= null`. Under Dart 3.13 a bare `void` return can't be compared to
  /// `null` (`void` excludes it), so `run`'s inferred `T` would be `void`
  /// and `ok != null` fails analysis. Wrapping the call so it resolves to
  /// `true` gives `run` a real `bool` to carry.
  Future<bool> submit(String current, String next, String confirm) async {
    if (next != confirm) {
      local({'confirmPassword': "Passwords don't match"});
      return false;
    }
    if (next.length < 8) {
      local({'newPassword': 'At least 8 characters'});
      return false;
    }
    final ok = await run<bool>(
      () async {
        await ref.read(authApiProvider).changePassword(current, next);
        return true;
      },
      draft: const {},
      mapError: (e) => e.code == 'INVALID_CREDENTIALS'
          ? {'currentPassword': 'Your current password is not right'}
          : {'form': genericErrorCopy},
    );
    return ok ?? false;
  }
}

final changeEmailControllerProvider =
    NotifierProvider<ChangeEmailController, ChangeFormState>(
      ChangeEmailController.new,
    );

class ChangeEmailController extends ChangeFormController {
  @override
  String get draftKey => '/account/change-email';

  Future<VerificationOutcome?> submit(
    String newEmail,
    String currentPassword,
  ) => run(
    () => ref
        .read(authApiProvider)
        .requestEmailChange(newEmail.trim(), currentPassword),
    draft: {'newEmail': newEmail},
    mapError: (e) => switch (e.code) {
      'EMAIL_IN_USE' => {
        'newEmail': 'This email already has a RaajjePro account.',
      },
      'EMAIL_UNCHANGED' => {'newEmail': 'That is already your email address'},
      'INVALID_CREDENTIALS' => {
        'currentPassword': 'Your current password is not right',
      },
      'OTP_RATE_LIMITED' => {
        'form':
            'Too many codes requested — wait ${e.retryAfterSeconds ?? 60} seconds and try again',
      },
      _ => {'form': genericErrorCopy},
    },
  );
}

final changePhoneControllerProvider =
    NotifierProvider<ChangePhoneController, ChangeFormState>(
      ChangePhoneController.new,
    );

class ChangePhoneController extends ChangeFormController {
  @override
  String get draftKey => '/account/phone';

  Future<UserAccount?> submit(String dialCode, String number) async {
    final user = await run(
      () =>
          ref.read(authApiProvider).changePhone(dialCode.trim(), number.trim()),
      draft: {'dialCode': dialCode, 'number': number},
      mapError: (e) => e.code == 'PHONE_IN_USE'
          ? {'phone': 'This number belongs to a verified provider account.'}
          : {'form': genericErrorCopy},
    );
    if (user != null) ref.read(authControllerProvider.notifier).applyUser(user);
    return user;
  }
}
