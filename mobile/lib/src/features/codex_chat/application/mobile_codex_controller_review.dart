part of 'mobile_codex_controller.dart';

// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

final class const MobileCodexReviewBranches({
  final List<String> branches = const <String>[],
  final bool lookupFailed = false,
});

extension MobileCodexControllerReview on MobileCodexController {
  Future<MobileCodexReviewBranches> reviewBranches() async {
    final client = _client;
    if (client == null) {
      return const MobileCodexReviewBranches(lookupFailed: true);
    }
    try {
      final result = await client.codexRequest(
        'codex.review.branches',
        <String, Object?>{'tabId': tabId},
      );
      final currentBranch = _string(result['currentBranch'])?.trim();
      final branchValues = result['branches'];
      final branches =
          <String>{
                if (branchValues is List)
                  for (final branch in branchValues.whereType<String>())
                    branch.trim(),
              }
              .where((branch) {
                return branch.isNotEmpty && branch != currentBranch;
              })
              .toList(growable: false)
            ..sort(_compareMobileReviewBranches);
      return MobileCodexReviewBranches(branches: branches);
    } catch (error, stackTrace) {
      _logger.warning(
        'Codex review branches could not be loaded.',
        error,
        stackTrace,
      );
      return const MobileCodexReviewBranches(lookupFailed: true);
    }
  }

  Future<void> review({
    String target = 'uncommittedChanges',
    String? argument,
    String? commitTitle,
    String? delivery,
  }) {
    final targetPayload = <String, Object?>{'type': target};
    if (argument != null && argument.trim().isNotEmpty) {
      final key = switch (target) {
        'baseBranch' => 'branch',
        'commit' => 'sha',
        'custom' => 'instructions',
        _ => null,
      };
      if (key != null) targetPayload[key] = argument.trim();
    }
    if (target == 'commit' && commitTitle?.trim().isNotEmpty == true) {
      targetPayload['title'] = commitTitle!.trim();
    }
    return _simpleRequest('codex.review.start', <String, Object?>{
      'tabId': tabId,
      'target': targetPayload,
      if (delivery != null && delivery.isNotEmpty) 'delivery': delivery,
    });
  }
}

int _compareMobileReviewBranches(String left, String right) {
  const preferred = <String>['main', 'origin/main', 'master', 'origin/master'];
  final leftIndex = preferred.indexOf(left);
  final rightIndex = preferred.indexOf(right);
  if (leftIndex >= 0 || rightIndex >= 0) {
    if (leftIndex < 0) return 1;
    if (rightIndex < 0) return -1;
    return leftIndex.compareTo(rightIndex);
  }
  return left.toLowerCase().compareTo(right.toLowerCase());
}
