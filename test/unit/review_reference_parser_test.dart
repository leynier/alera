import 'package:alera/src/features/pull_requests/application/review_reference_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseReviewReference', () {
    test('parses a bare number', () {
      expect(parseReviewReference('123'), 123);
    });

    test('parses a #-prefixed number', () {
      expect(parseReviewReference('#123'), 123);
    });

    test('parses a GitHub pull URL', () {
      expect(parseReviewReference('https://github.com/o/r/pull/456'), 456);
    });

    test('parses an Azure DevOps pullrequest URL', () {
      expect(
        parseReviewReference('https://dev.azure.com/o/p/_git/r/pullrequest/7'),
        7,
      );
    });

    test('returns null for unparseable input', () {
      expect(parseReviewReference('not-a-pr'), isNull);
      expect(parseReviewReference('   '), isNull);
    });
  });
}
