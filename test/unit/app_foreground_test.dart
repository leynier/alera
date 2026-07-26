import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlwaysForeground', () {
    test('never parks and never reports a change', () async {
      // The default wherever there is no running app to observe. Reporting a
      // permanent foreground is what makes parking opt-in: a missed wiring
      // degrades to the behavior from before parking existed rather than to
      // work that nothing would ever restart.
      const foreground = AlwaysForeground();

      expect(foreground.isForeground, isTrue);
      expect(await foreground.changes.isEmpty, isTrue);
    });

    test('disposing is a no-op', () {
      const foreground = AlwaysForeground();

      expect(foreground.dispose, returnsNormally);
      expect(foreground.isForeground, isTrue);
    });
  });
}
