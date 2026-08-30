import 'package:alera_configuration/alera_configuration.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'configuration_sync_controller.g.dart';

@riverpod
class ConfigurationSyncController extends _$ConfigurationSyncController {
  @override
  Future<ConfigurationScreenState> build(
    ConfigurationSyncService service,
  ) async => ConfigurationScreenState(review: await service.review());

  Future<void> refresh({int? revision}) => _run(
    () async => state.requireValue.copyWith(
      review: await service.review(historicalRevision: revision),
    ),
  );
  Future<void> loadHistory() => _run(
    () async =>
        state.requireValue.copyWith(history: await service.cloud.history()),
  );
  void choose(ConfigurationDifference difference, ConfigurationChoice choice) {
    difference.choice = choice;
    difference.customResult = null;
    state = AsyncData(state.requireValue.copyWith());
  }

  void rename(ConfigurationDifference difference, String name) {
    difference.rename(name);
    state = AsyncData(state.requireValue.copyWith());
  }

  void chooseAll(ConfigurationChoice choice) {
    state.requireValue.review!.merge.chooseAll(choice);
    state = AsyncData(state.requireValue.copyWith());
  }

  Future<void> apply({required bool upload}) => _run(() async {
    await service.apply(state.requireValue.review!, upload: upload);
    return ConfigurationScreenState(review: await service.review());
  });
  Future<void> retry() => _run(() async {
    await service.retryPending();
    return ConfigurationScreenState(review: await service.review());
  });
  Future<void> _run(
    Future<ConfigurationScreenState> Function() operation,
  ) async {
    if (state.requireValue.busy) return;
    final keepAlive = ref.keepAlive();
    final releaseService = service.retain?.call();
    state = AsyncData(state.requireValue.copyWith(busy: true));
    try {
      final next = await operation();
      if (ref.mounted) state = AsyncData(next);
    } catch (error, stack) {
      Logger(
        'ConfigurationSync',
      ).warning('Configuration operation failed', error, stack);
      if (!ref.mounted) return;
      var previous = state.requireValue;
      try {
        final review = previous.review;
        if (review != null) {
          previous = previous.copyWith(
            review: await service.recoverReview(review),
          );
        }
      } catch (_) {
        /* Keep the original failure when the target disconnected. */
      }
      if (ref.mounted) {
        state = AsyncData(previous.copyWith(error: error.toString()));
      }
    } finally {
      releaseService?.call();
      keepAlive.close();
    }
  }
}
