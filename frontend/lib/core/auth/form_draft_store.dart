import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps what a user was typing across a session-expired → sign-in → return
/// path. That is the one promise the Session Expired screen makes, and it
/// must be true. In memory only; a process restart legitimately loses it,
/// and the screen's copy never claims more than "after you sign in".
class FormDraftStore {
  final Map<String, Map<String, String>> _drafts = {};
  void save(String formKey, Map<String, String> fields) =>
      _drafts[formKey] = Map.of(fields);
  Map<String, String>? take(String formKey) => _drafts.remove(formKey);
  Map<String, String>? peek(String formKey) => _drafts[formKey];
}

final formDraftStoreProvider = Provider<FormDraftStore>(
  (_) => FormDraftStore(),
);
