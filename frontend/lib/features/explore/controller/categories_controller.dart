import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/features/explore/data/category_api.dart';

// Riverpod 3's exponential-backoff auto-retry is off here for the same reason
// the account controllers turn it off: the screen offers an explicit "Try
// again", and a silent background retry fights it and outlives the test.
Duration? _noRetry(int retryCount, Object error) => null;

final categoriesControllerProvider =
    AsyncNotifierProvider<CategoriesController, List<ServiceCategory>>(
      CategoriesController.new,
      retry: _noRetry,
    );

/// The catalogue behind the Explore grid.
///
/// It holds no fallback list. A hardcoded twelve here would hide exactly the
/// failure §Phase 4's Done-when is about — the grid must be the endpoint's
/// answer or an honest error, never a stale copy compiled into the app.
class CategoriesController extends AsyncNotifier<List<ServiceCategory>> {
  @override
  Future<List<ServiceCategory>> build() => ref.read(categoryApiProvider).list();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
