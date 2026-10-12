import 'package:alera/src/features/runs/infra/recipe_repository.dart';
import 'package:alera/src/features/runs/infra/run_repository.dart';
import 'package:alera/src/features/runs/infra/runtime_run_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_providers.g.dart';

@Riverpod(keepAlive: true)
RunRepository runRepository(Ref ref) => RuntimeRunRepository(
  ref.watch(runtimeHostClientProvider),
  ref.watch(runtimeChangeCoalescerProvider),
);

@Riverpod(keepAlive: true)
RecipeRepository recipeRepository(Ref ref) =>
    RecipeRepository(ref.watch(runtimeHostClientProvider));

/// The clock run rows and timelines measure ages against; tests pin it.
@riverpod
DateTime Function() runClock(Ref ref) => DateTime.now;
