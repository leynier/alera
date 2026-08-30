import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero pauses yield to microtasks before the next event', () {
    fakeAsync((clock) {
      final events = <String>[];
      unawaited(Future.pause().then((_) => events.add('implicit zero')));
      unawaited(
        Future.pause(Duration.zero).then((_) => events.add('explicit zero')),
      );
      scheduleMicrotask(() => events.add('microtask'));
      clock.flushMicrotasks();
      expect(events, ['microtask']);
      clock.elapse(Duration.zero);
      expect(events, ['microtask', 'implicit zero', 'explicit zero']);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('nonzero pauses keep the duration and completion order', () {
    fakeAsync((clock) {
      final events = <String>[];
      unawaited(
        Future.pause(const Duration(milliseconds: 5))
            .then((_) => events.add('five')),
      );
      unawaited(
        Future.pause(const Duration(milliseconds: 10))
            .then((_) => events.add('ten')),
      );
      clock.elapse(const Duration(milliseconds: 4));
      expect(events, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(events, ['five']);
      clock.elapse(const Duration(milliseconds: 5));
      expect(events, ['five', 'ten']);
      expect(clock.pendingTimers, isEmpty);
    });
  });
}
