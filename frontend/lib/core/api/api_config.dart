/// Where the API lives. Set with `--dart-define=API_BASE_URL=https://…`;
/// the default reaches a dev server on the same machine (an Android emulator
/// wants `http://10.0.2.2:3000`, passed the same way).
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
}
