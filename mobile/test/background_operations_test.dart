import 'dart:async';

import 'package:alera_mobile/src/features/workbench/application/background_operations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retains work without listeners, rejects duplicates, and completes once',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final jobs = container.read(backgroundOperationsProvider.notifier);
      final completion = Completer<String?>();
      var successes = 0;
      expect(
        jobs.submit(
          operationKey: 'ship/one',
          title: 'Ship',
          action: () => completion.future,
          onSuccess: () => successes++,
        ),
        isTrue,
      );
      expect(
        jobs.submit(
          operationKey: 'ship/one',
          title: 'Ship',
          action: () async => fail('Duplicate write'),
        ),
        isFalse,
      );
      await container.pump();
      expect(container.read(backgroundOperationsProvider).single.error, isNull);
      completion.complete(null);
      await container.pump();
      expect(container.read(backgroundOperationsProvider), isEmpty);
      expect(successes, 1);
    },
  );

  test(
    'keeps returned and thrown failures until explicitly dismissed',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final jobs = container.read(backgroundOperationsProvider.notifier);
      var restored = 0;
      jobs.submit(
        title: 'Comment',
        action: () async => 'Offline',
        restore: () => restored++,
      );
      jobs.submit(
        title: 'Link',
        action: () => throw StateError('Disconnected'),
      );
      await container.pump();
      final failures = container.read(backgroundOperationsProvider);
      expect(failures, hasLength(2));
      expect(failures.first.error, 'Offline');
      expect(failures.last.error, contains('Disconnected'));
      expect(restored, 0);
      failures.first.restore!();
      expect(restored, 1);
      jobs.dismiss(failures.first.id);
      expect(container.read(backgroundOperationsProvider), hasLength(1));
    },
  );
}
