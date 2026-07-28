import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automation references decode, encode, and validate scope', () {
    final target = BrowserAutomationRef.fromJson(<String, Object?>{
      'pageId': 'page-1',
      'snapshotId': 'snapshot-1',
      'ref': 'node-1',
    });

    expect(target.toJson(), <String, Object?>{
      'pageId': 'page-1',
      'snapshotId': 'snapshot-1',
      'ref': 'node-1',
    });
    expect(
      () => target.validateFor(pageId: 'page-1', snapshotId: 'snapshot-1'),
      returnsNormally,
    );
    expect(
      () => target.validateFor(pageId: 'page-2', snapshotId: 'snapshot-1'),
      throwsA(
        isA<BrowserFailure>().having(
          (failure) => failure.code,
          'code',
          BrowserErrorCode.staleAutomationReference,
        ),
      ),
    );
  });

  test('automation references reject every malformed required field', () {
    for (final payload in <Map<String, Object?>>[
      <String, Object?>{'snapshotId': 'snapshot-1', 'ref': 'node-1'},
      <String, Object?>{'pageId': 'page-1', 'ref': 'node-1'},
      <String, Object?>{'pageId': 'page-1', 'snapshotId': 'snapshot-1'},
    ]) {
      expect(
        () => BrowserAutomationRef.fromJson(payload),
        throwsFormatException,
      );
    }
  });
}
