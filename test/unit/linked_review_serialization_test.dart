import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkedReview wire format', () {
    test('serializes the keys and provider string the host expects', () {
      final review = LinkedReview.linked(
        workspaceId: 'w1',
        provider: GitHostingProvider.azureDevops,
        number: 42,
        url: 'https://dev.azure.com/o/p/_git/r/pullrequest/42',
        linkedAt: DateTime.utc(2026, 7, 9),
      );
      final map = review.toMap();
      expect(map['workspaceId'], 'w1');
      expect(map['dismissed'], false);
      expect(map['provider'], 'azureDevops');
      expect(map['number'], 42);
      expect(map['url'], 'https://dev.azure.com/o/p/_git/r/pullrequest/42');
      // chrono on the host parses RFC3339; a UTC DateTime must serialize with Z.
      expect(map['linkedAt'], isA<String>());
      expect((map['linkedAt'] as String).endsWith('Z'), isTrue);
    });

    test('round-trips a linked review through fromJson', () {
      final review = LinkedReview.linked(
        workspaceId: 'w1',
        provider: GitHostingProvider.github,
        number: 7,
        url: 'https://github.com/o/r/pull/7',
        linkedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final restored = LinkedReview.fromJson(review.toMap());
      expect(restored.hasReview, isTrue);
      expect(restored.provider, GitHostingProvider.github);
      expect(restored.number, 7);
      expect(restored.workspaceId, 'w1');
      expect(restored.linkedAt.toUtc(), review.linkedAt);
    });

    test('an exact dismissal round-trips and reports no linked review', () {
      final dismissal = LinkedReview.dismissal(
        workspaceId: 'w1',
        provider: GitHostingProvider.github,
        number: 7,
        url: 'https://github.com/o/r/pull/7',
      );
      final map = dismissal.toMap();
      expect(map['dismissed'], true);
      expect(map['number'], 7);
      final restored = LinkedReview.fromJson(map);
      expect(restored.dismissed, isTrue);
      expect(restored.hasReview, isFalse);
      expect(restored.hasDismissedReview, isTrue);
    });

    test('legacy dismissals without review identity remain readable', () {
      final dismissal = LinkedReview.dismissal(workspaceId: 'w1');
      final restored = LinkedReview.fromJson(dismissal.toMap());
      expect(restored.dismissed, isTrue);
      expect(restored.hasDismissedReview, isFalse);
    });
  });
}
