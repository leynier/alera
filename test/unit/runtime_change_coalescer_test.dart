import 'dart:async';

import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collapses repeat schedules inside the debounce window', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 20),
      maxDelay: const Duration(milliseconds: 200),
    );
    addTearDown(coalescer.dispose);
    var runs = 0;

    for (var i = 0; i < 10; i++) {
      coalescer.schedule('key', () async => runs += 1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(runs, 0, reason: 'still inside the debounce window');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(runs, 1);
  });

  test('maxDelay stops continuous churn from starving a run', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 30),
      maxDelay: const Duration(milliseconds: 50),
    );
    addTearDown(coalescer.dispose);
    var runs = 0;

    final ticker = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => coalescer.schedule('key', () async => runs += 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    ticker.cancel();

    expect(
      runs,
      greaterThanOrEqualTo(2),
      reason: 'a pure trailing debounce would never fire here',
    );
  });

  test('keys are independent', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 10),
      maxDelay: const Duration(milliseconds: 100),
    );
    addTearDown(coalescer.dispose);
    final ran = <String>[];

    coalescer.schedule('a', () async => ran.add('a'));
    coalescer.schedule('b', () async => ran.add('b'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(ran..sort(), <String>['a', 'b']);
  });

  test('flush skips the debounce', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(seconds: 30),
      maxDelay: const Duration(seconds: 60),
    );
    addTearDown(coalescer.dispose);
    var runs = 0;

    coalescer.schedule('key', () async => runs += 1);
    expect(runs, 0);

    await coalescer.flush('key');
    expect(runs, 1);
  });

  test('flush re-runs once when a run is already in flight', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 5),
      maxDelay: const Duration(milliseconds: 50),
    );
    addTearDown(coalescer.dispose);
    var runs = 0;
    final gate = Completer<void>();

    coalescer.schedule('key', () async {
      runs += 1;
      if (runs == 1) {
        await gate.future;
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(runs, 1);

    final flushed = coalescer.flush('key');
    gate.complete();
    await flushed;

    expect(runs, 2);
  });

  test('cancel and dispose leave no pending run', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 10),
      maxDelay: const Duration(milliseconds: 100),
    );
    var runs = 0;

    coalescer.schedule('key', () async => runs += 1);
    coalescer.cancel('key');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(runs, 0);

    coalescer.schedule('other', () async => runs += 1);
    coalescer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(runs, 0);
  });
}
