import 'dart:async';
import 'package:alera/src/features/orchestration/infra/foreground_board_watch.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/run_board_fixtures.dart';

void main() {
  test(
    'initially hidden does no reads, forwards errors and cancels cleanly',
    () {
      fakeAsync((time) {
        final foreground = BoardTestForeground()..visible = false;
        final source = StreamController<int>.broadcast(sync: true);
        var starts = 0;
        final values = <int>[];
        final errors = <Object>[];
        final subscription = foregroundBoardWatch(foreground, () {
          starts++;
          return source.stream;
        }).listen(values.add, onError: errors.add);
        time.flushMicrotasks();
        expect(starts, 0);
        foreground.setVisible(true);
        time.flushMicrotasks();
        source.add(1);
        source.addError(StateError('disconnected'));
        time.flushMicrotasks();
        expect(values, [1]);
        expect(errors.single, isA<StateError>());
        foreground.setVisible(false);
        source.add(2);
        time.flushMicrotasks();
        expect(values, [1]);
        foreground.setVisible(true);
        foreground.setVisible(false);
        foreground.setVisible(true);
        time.flushMicrotasks();
        expect(starts, 2);
        unawaited(subscription.cancel());
        time.flushMicrotasks();
        expect(source.hasListener, isFalse);
        expect(foreground.events.hasListener, isFalse);
        foreground.dispose();
        unawaited(source.close());
        time.flushMicrotasks();
      });
    },
  );
}
