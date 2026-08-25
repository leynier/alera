import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeepAliveSnapshot', () {
    test('active snapshot reports system and display locks', () {
      const snapshot = KeepAliveSnapshot.active();

      expect(snapshot.active, isTrue);
      expect(snapshot.system, isTrue);
      expect(snapshot.display, isTrue);
      expect(snapshot.error, isNull);
      expect(snapshot.hasError, isFalse);
    });

    test('inactive snapshot is off until an error is attached', () {
      const snapshot = KeepAliveSnapshot.inactive();

      expect(snapshot.active, isFalse);
      expect(snapshot.system, isFalse);
      expect(snapshot.display, isFalse);
      expect(snapshot.error, isNull);
      expect(snapshot.hasError, isFalse);
    });

    test('blank error text is not treated as a failure', () {
      const empty = KeepAliveSnapshot.inactive(error: '');
      const whitespace = KeepAliveSnapshot.inactive(error: '   ');

      expect(empty.hasError, isFalse);
      expect(whitespace.hasError, isFalse);
    });

    test('explicit fields can report a failed lock', () {
      const snapshot = KeepAliveSnapshot(
        active: false,
        system: false,
        display: false,
        error: 'not supported',
      );

      expect(snapshot.active, isFalse);
      expect(snapshot.system, isFalse);
      expect(snapshot.display, isFalse);
      expect(snapshot.error, 'not supported');
      expect(snapshot.hasError, isTrue);
    });
  });
}
